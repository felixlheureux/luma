import Foundation
import Observation

public enum ScanTarget: String, Sendable, Hashable, CaseIterable {
    case overview, generatedData, applications, leftovers, footprint, storage, duplicates
    public var title: String {
        switch self {
        case .overview: "Local check"
        case .generatedData: "Generated data"
        case .applications: "Applications"
        case .leftovers: "Potential leftovers"
        case .footprint: "Application inspection"
        case .storage: "Folder analysis"
        case .duplicates: "Duplicate analysis"
        }
    }
}

public struct ScanRequest: Sendable {
    public let target: ScanTarget
    public let root: URL?
    public let application: ApplicationRecord?
    public init(_ target: ScanTarget, root: URL? = nil, application: ApplicationRecord? = nil) {
        self.target = target; self.root = root; self.application = application
    }
    public var scope: String { application?.url.path ?? root?.path ?? target.title }
}

public struct ScanPulse: Sendable {
    public let phase: String
    public let current: String
    public let completed: Int
    public let total: Int?
    public let entries: Int
    public let bytes: Int64
    public init(_ phase: String, current: String = "", completed: Int = 0, total: Int? = nil, entries: Int = 0, bytes: Int64 = 0) {
        self.phase = phase; self.current = current; self.completed = completed
        self.total = total; self.entries = entries; self.bytes = bytes
    }
}

public enum ScanEvent: Sendable {
    case progress(ScanPulse)
    case item(CleanupItem)
    case application(ApplicationRecord)
    case duplicate(DuplicateGroup)
    case coverage(ScanCoverage)
    case notice(String)
}
public typealias ScanEmitter = @Sendable (ScanEvent) -> Void

public struct ScanResult: Sendable {
    public var report: ScanReport
    public var applications: [ApplicationRecord]
    public var duplicates: [DuplicateGroup]
    public var storageIndex: StorageIndex?
    public init(report: ScanReport = ScanReport(), applications: [ApplicationRecord] = [], duplicates: [DuplicateGroup] = [], storageIndex: StorageIndex? = nil) {
        self.report = report; self.applications = applications; self.duplicates = duplicates; self.storageIndex = storageIndex
    }
}

public enum ScanStopReason: String, Sendable { case cancelled, replaced, timedOut }
public enum ScanPhase: Sendable, Equatable {
    case running, stopping(ScanStopReason), completed, completedWithExclusions, cancelled, replaced, timedOut, failed
    public var isTerminal: Bool {
        switch self { case .running, .stopping: false; default: true }
    }
}

public struct ScanSession: Identifiable, Sendable {
    public let id: UUID
    public let request: ScanRequest
    public let startedAt: Date
    public var lastProgressAt: Date
    public var endedAt: Date?
    public var phase: ScanPhase = .running
    public var progress = ScanPulse("Starting")
    public var stalled = false
    public var detail: String?
    public var failureCoverage: CoverageState?
    public var preview = ScanPreview()
}

/// Preview storage is bounded independently of full, completed scanner output.
/// These values carry no authority to create an executable snapshot.
public struct ScanPreview: Sendable {
    public var items: [CleanupItem] = []
    public var applications: [ApplicationRecord] = []
    public var duplicates: [DuplicateGroup] = []
    public var coverage: [ScanCoverage] = []
    public var notices: [String] = []
    public var truncated = false
}

public struct ScanSnapshot: Sendable {
    public let sessionID: UUID
    public let request: ScanRequest
    public let finishedAt: Date
    public let result: ScanResult
}

public struct ScanLimits: Sendable {
    public let stallAfter: TimeInterval
    public let idleTimeout: TimeInterval
    public let totalTimeout: TimeInterval
    public init(stallAfter: TimeInterval, idleTimeout: TimeInterval, totalTimeout: TimeInterval) {
        self.stallAfter = stallAfter; self.idleTimeout = idleTimeout; self.totalTimeout = totalTimeout
    }
    public static func standard(for target: ScanTarget) -> Self {
        switch target {
        case .duplicates: .init(stallAfter: 30, idleTimeout: 300, totalTimeout: 7_200)
        case .applications, .overview: .init(stallAfter: 20, idleTimeout: 180, totalTimeout: 3_600)
        default: .init(stallAfter: 15, idleTimeout: 120, totalTimeout: 1_800)
        }
    }
}

/// A per-worker coalescing mailbox prevents a callback Task for every file.
/// No suspension or thread-local policy crosses its short lock sections.
private final class ScanMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var changed = false
    private var pulse = ScanPulse("Starting")
    private var updatedAt = Date()
    private var preview = ScanPreview()
    private var items: [Data: CleanupItem] = [:]
    private var applications: [Data: ApplicationRecord] = [:]
    private var groups: [String: DuplicateGroup] = [:]

    func send(_ event: ScanEvent) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        changed = true; updatedAt = Date()
        switch event {
        case .progress(let value): pulse = value
        case .item(let item):
            let key = Data(item.url.path.utf8)
            if items.count < 1_500 || items[key] != nil { items[key] = item } else { preview.truncated = true }
        case .application(let app):
            let key = Data(app.url.path.utf8)
            if applications.count < 5_000 || applications[key] != nil { applications[key] = app } else { preview.truncated = true }
        case .duplicate(let group):
            if groups.count < 500 || groups[group.id] != nil { groups[group.id] = group } else { preview.truncated = true }
        case .coverage(let value):
            if preview.coverage.count < 1_500 { preview.coverage.append(value) } else { preview.truncated = true }
        case .notice(let value):
            if preview.notices.count < 200 { preview.notices.append(value) } else { preview.truncated = true }
        }
    }
    func disable() { lock.lock(); enabled = false; lock.unlock() }
    func take() -> (ScanPulse, Date, ScanPreview)? {
        lock.lock(); defer { lock.unlock() }
        guard changed else { return nil }
        changed = false
        var value = preview
        value.items = Array(items.values)
        value.applications = Array(applications.values)
        value.duplicates = Array(groups.values)
        return (pulse, updatedAt, value)
    }
}

/// One expensive worker at a time. Replacement has a single last-request-wins
/// queue slot and waits for the cancelled worker to return from any OS call.
@MainActor @Observable public final class ScanController {
    public private(set) var session: ScanSession?
    public private(set) var queuedRequest: ScanRequest?
    public private(set) var snapshots: [ScanTarget: ScanSnapshot] = [:]
    public private(set) var isBusy = false
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored public var onComplete: (@MainActor (ScanSnapshot) -> Void)?
    @ObservationIgnored private var worker: Task<ScanResult, Error>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var mailbox: ScanMailbox?
    @ObservationIgnored private var queued: Job?
    @ObservationIgnored private var limits: ScanLimits?
    private struct Job {
        let request: ScanRequest
        let limits: ScanLimits
        let work: @Sendable (@escaping ScanEmitter) async throws -> ScanResult
    }

    public init() {}

    deinit {
        worker?.cancel(); ticker?.cancel(); mailbox?.disable()
    }

    public func start(_ request: ScanRequest, limits: ScanLimits? = nil,
                      work: @escaping @Sendable (@escaping ScanEmitter) async throws -> ScanResult) {
        let job = Job(request: request, limits: limits ?? .standard(for: request.target), work: work)
        if isBusy {
            queued = job; queuedRequest = request
            stop(.replaced)
        } else { launch(job) }
    }

    /// Drop completed evidence after a mutation. A worker that is already
    /// scanning remains tracked and must finish normally before replacement.
    public func invalidateSnapshots(for targets: Set<ScanTarget>) {
        for target in targets { snapshots.removeValue(forKey: target) }
        if !isBusy, let current = session, targets.contains(current.request.target) { session = nil }
        onChange?()
    }

    public func cancel() {
        queued = nil; queuedRequest = nil
        stop(.cancelled)
    }

    private func stop(_ reason: ScanStopReason) {
        guard isBusy, session != nil else { return }
        session?.phase = .stopping(reason)
        mailbox?.disable(); worker?.cancel()
        onChange?()
    }

    private func launch(_ job: Job) {
        let id = UUID(), mailbox = ScanMailbox(), started = Date()
        self.mailbox = mailbox; limits = job.limits
        session = ScanSession(id: id, request: job.request, startedAt: started, lastProgressAt: started)
        isBusy = true
        let worker = Task.detached(priority: .utility) { try await job.work { mailbox.send($0) } }
        self.worker = worker
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                if let self { self.poll() } else { return }
            }
        }
        onChange?()
        Task { [weak self] in
            let outcome = await worker.result
            self?.finish(id: id, outcome: outcome)
        }
    }

    /// Explicit time makes timeout/late-event tests deterministic. The worker
    /// still owns the busy slot until it actually exits; time alone never frees it.
    public func poll(now: Date = Date()) {
        guard isBusy, var current = session, current.phase == .running else { return }
        if let (pulse, updated, preview) = mailbox?.take() {
            current.progress = pulse; current.lastProgressAt = updated; current.preview = preview
        }
        let idle = now.timeIntervalSince(current.lastProgressAt)
        current.stalled = idle >= (limits?.stallAfter ?? 15)
        session = current
        if idle >= (limits?.idleTimeout ?? 120) || now.timeIntervalSince(current.startedAt) >= (limits?.totalTimeout ?? 1_800) {
            stop(.timedOut)
        } else { onChange?() }
    }

    private func finish(id: UUID, outcome: Result<ScanResult, Error>) {
        guard session?.id == id, isBusy else { return }
        poll()
        guard var current = session, current.id == id else { return }
        mailbox?.disable(); ticker?.cancel(); ticker = nil
        current.endedAt = Date()
        var snapshot: ScanSnapshot?
        if case .stopping(let reason) = current.phase {
            switch reason {
            case .cancelled: current.phase = .cancelled
            case .replaced: current.phase = .replaced
            case .timedOut: current.phase = .timedOut
            }
        } else {
            switch outcome {
            case .success(let result):
                current.phase = result.report.isComplete && result.report.notices.isEmpty ? .completed : .completedWithExclusions
                snapshot = ScanSnapshot(sessionID: id, request: current.request, finishedAt: current.endedAt!, result: result)
            case .failure(let error) where error is CancellationError: current.phase = .cancelled
            case .failure(let error):
                current.phase = .failed; current.detail = error.localizedDescription
                current.failureCoverage = GeneratedDataScanner.failureState(error)
            }
        }
        session = current; worker = nil; mailbox = nil; isBusy = false
        if let snapshot { snapshots[current.request.target] = snapshot; onComplete?(snapshot) }
        onChange?()
        if let next = queued {
            queued = nil; queuedRequest = nil
            if !isBusy { launch(next) }
        }
    }

    public var statusText: String {
        guard let session else { return "Ready when you are" }
        if let queuedRequest { return "Stopping \(session.request.target.title) · queued \(queuedRequest.target.title)" }
        switch session.phase {
        case .running: return session.stalled ? "Still waiting for \(session.progress.current.isEmpty ? session.progress.phase : session.progress.current) · you can cancel" : "\(session.request.target.title) · \(session.progress.phase)"
        case .stopping: return "Stopping scan · waiting for the current filesystem operation"
        case .completed: return "\(session.request.target.title) complete"
        case .completedWithExclusions: return "\(session.request.target.title) finished with exclusions"
        case .cancelled: return "Scan cancelled · preview only · no changes made"
        case .replaced: return "Scan replaced · no changes made"
        case .timedOut: return "Scan timed out · preview only · retry the same scope"
        case .failed: return "Scan could not finish · \(session.detail ?? "retry the same scope")"
        }
    }
}
