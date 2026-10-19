import SwiftUI
import LumaCore

private final class CleanupDetailMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: ScanPulse?
    func send(_ pulse: ScanPulse) { lock.withLock { latest = pulse } }
    func take() -> ScanPulse? { lock.withLock { let saved = latest; latest = nil; return saved } }
    func clear() { lock.withLock { latest = nil } }
}

/// Owns mutation lifetime separately from scan/review cancellation.
@MainActor @Observable final class CleanupSessionModel {
    var sessions: [CleanupSession] = []
    var undoAttempts: [UndoAttempt] = []
    var progress: CleanupProgress?
    var stopping = false
    var detail: ScanPulse?
    var startedAt: Date?
    @ObservationIgnored private let details = CleanupDetailMailbox()
    var detailEmitter: @Sendable (ScanPulse) -> Void {
        let mailbox = details
        return { mailbox.send($0) }
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    private(set) var isRunning = false
    @ObservationIgnored var onDrained: (() -> Void)?
    var restoring = false

    func run(_ operation: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        progress = nil; detail = nil; details.clear(); startedAt = Date()
        stopping = false; isRunning = true
        task = Task { [self] in
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    guard let self else { return }
                    if let pulse = self.details.take() { self.detail = pulse }
                }
            }
            await operation()
            ticker.cancel()
            task = nil; stopping = false; progress = nil; detail = nil; details.clear(); isRunning = false
            onDrained?(); onDrained = nil
        }
    }

    func update(_ progress: CleanupProgress) {
        self.progress = progress
        detail = nil; details.clear()
    }
    func stop() { stopping = true; task?.cancel() }
}
