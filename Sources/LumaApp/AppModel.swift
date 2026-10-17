import SwiftUI
import LumaCore

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", clean = "Clean", optimizer = "Optimizer", applications = "Applications"
    case storage = "Storage", duplicates = "Duplicates", privacy = "Privacy", system = "System", history = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .optimizer: "slider.horizontal.3"
        case .applications: "square.stack.3d.up"
        case .storage: "internaldrive"
        case .duplicates: "square.on.square"
        case .privacy: "hand.raised"
        case .system: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "A clearer picture of your Mac."
        case .clean: "Generated data, with every decision explained."
        case .optimizer: "Understand what’s running. Change what matters."
        case .applications: "See what’s installed and what it leaves behind."
        case .storage: "Find your space. Decide what stays."
        case .duplicates: "Identical content. Verified locally."
        case .privacy: "Your data and permissions, on your terms."
        case .system: "Real measurements. No arbitrary health scores."
        case .history: "An inspectable record of every change."
        }
    }
}

enum ApplicationTab: String, CaseIterable { case installed = "Installed", leftovers = "Leftovers" }

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    let computerName = Host.current().localizedName ?? "This Mac"
    @ObservationIgnored var showMainWindow: (() -> Void)?
    @ObservationIgnored var showSettingsWindow: (() -> Void)?
    var destination: Destination? = .overview
    var system = SystemSample()
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var cleanup: [CleanupItem] = []
    var storage: [CleanupItem] = []
    var duplicates: [DuplicateGroup] = []
    var applications: [ApplicationRecord] = []
    var applicationTab: ApplicationTab = .installed
    var leftovers: [CleanupItem] = []
    var didScanLeftovers = false
    var footprint: [CleanupItem] = []
    var inspectedApp: ApplicationRecord?
    var selected: Set<String> = []
    var scanTask: Task<Void, Never>?
    var busy = false
    var status = "Ready when you are"
    var lastScan: Date?
    var notices: [String] = []
    var cleanupReport: ScanReport?
    var scanProgress: ScanProgress?
    var recoveryNotices: [RecoveryNotice] = []
    var recoveryLoading = true
    var journalError: String?
    @ObservationIgnored private var journal: CleanupJournal?
    @ObservationIgnored private var recoveryStarted = false
    @ObservationIgnored private var activeScanID: UUID?
    var error: String?
    var reviewItems: [CleanupItem] = []
    var showingReview = false
    var search = ""
    var showingSearch = false
    var storageRoot: URL?
    var duplicateRoot: URL?
    var authorizedRoots: [URL] = []
    var history: [CleanupRecord] = []
    var ignored: Set<String> = []
    var completedScans: Set<Destination> = []
    private var monitorTask: Task<Void, Never>?
    private let ignoreKey = "luma.ignoredPaths"
    var cleanupBytes: Int64 { cleanup.filter { !isIgnored($0) }.reduce(0) { $0 + $1.bytes } }
    func isIgnored(_ item: CleanupItem) -> Bool {
        ignored.contains { Filesystem.isWithin(item.url, root: URL(fileURLWithPath: $0)) }
    }

    init() {
        do { journal = try CleanupJournal() }
        catch { journalError = "Activity could not be loaded. Cleanup is paused to preserve its records: \(error.localizedDescription)" }
        ignored = Set(UserDefaults.standard.stringArray(forKey: ignoreKey) ?? [])
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task {
            var iteration = 0
            while !Task.isCancelled {
                let previous = system.cpuTicks
                let includeProcesses = iteration % 3 == 0 && (destination == .system || destination == .optimizer)
                var next = await Task.detached(priority: .utility) { SystemSample.collect(previous: previous, includeProcesses: includeProcesses) }.value
                if !includeProcesses { next.processes = system.processes; next.processGroups = system.processGroups }
                system = next
                if !previous.isEmpty {
                    cpuHistory = Array((cpuHistory + [system.cpu]).suffix(60))
                    memoryHistory = Array((memoryHistory + [Double(system.usedMemory) / Double(max(1, system.physicalMemory)) * 100]).suffix(60))
                }
                iteration += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func runScan(_ target: Destination? = nil) {
        guard !busy else { return }
        let target = target ?? destination ?? .overview
        let scanID = UUID(); activeScanID = scanID
        busy = true; notices = []; selected = []; scanProgress = nil; status = "Scanning locally…"
        scanTask = Task {
            do {
                switch target {
                case .overview, .clean:
                    let reportProgress: @Sendable (ScanProgress) -> Void = { [self] update in
                        Task { @MainActor [self] in
                            guard activeScanID == scanID else { return }
                            scanProgress = update
                        }
                    }
                    let result = try await offMain { try await GeneratedDataScanner(progress: reportProgress).scan() }
                    try Task.checkCancellation()
                    cleanup = result.items; cleanupReport = result; notices = result.notices; scanProgress = nil; completedScans.insert(.clean)
                    if target == .overview {
                        status = "Generated data checked · inventorying applications…"
                        let inventory = try await offMain { try ApplicationScanner.scan() }
                        try Task.checkCancellation()
                        applications = inventory; completedScans.insert(.applications)
                    }
                case .applications:
                    if applicationTab == .leftovers {
                        status = "Checking installed apps, helpers, and potential leftovers…"
                        let result = try await offMain { try await LeftoverScanner().scan() }
                        try Task.checkCancellation()
                        leftovers = result.items; notices = result.notices; didScanLeftovers = true
                    } else {
                        let result = try await offMain { try ApplicationScanner.scan() }
                        try Task.checkCancellation()
                        applications = result; completedScans.insert(.applications)
                    }
                case .storage:
                    guard let root = storageRoot else { finish(); return }
                    let result = try await offMain { try await FolderScanner(root: root).scan() }
                    try Task.checkCancellation()
                    storage = result.items; notices = result.notices; completedScans.insert(.storage)
                case .duplicates:
                    guard let root = duplicateRoot else { finish(); return }
                    let result = try await offMain { try DuplicateScanner(root: root).scan() }
                    try Task.checkCancellation()
                    duplicates = result.0; notices = result.1; completedScans.insert(.duplicates)
                default: break
                }
                lastScan = Date(); status = notices.isEmpty ? "Scan complete" : "Scan complete with exclusions · \(notices.count) locations skipped"
            } catch is CancellationError { status = "Scan cancelled · no changes made" }
            catch { self.error = error.localizedDescription; status = "Scan could not finish" }
            finish()
        }
    }

    private func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let child = Task.detached(priority: .utility, operation: work)
        return try await withTaskCancellationHandler(operation: { try await child.value }, onCancel: { child.cancel() })
    }
    private func finish() { activeScanID = nil; scanProgress = nil; busy = false; scanTask = nil }
    func cancel() { scanTask?.cancel() }

    func chooseFolder(for target: Destination) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Analyze folder"; panel.message = "Luma scans this folder locally. Nothing is selected for removal."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if target == .storage { storageRoot = url } else { duplicateRoot = url }
        authorizedRoots.append(url); destination = target
        if target == .storage { storage = [] } else { duplicates = [] }
        runScan(target)
    }

    func inspect(_ app: ApplicationRecord) {
        guard !busy else { return }
        busy = true; status = "Finding exact app relationships…"
        Task {
            do {
                let result = try await offMain { try ApplicationScanner.footprint(app) }
                footprint = result; inspectedApp = app
            } catch { self.error = error.localizedDescription }
            status = "Ready when you are"; finish()
        }
    }

    func review(_ items: [CleanupItem]) {
        reviewItems = items.filter { selected.contains($0.id) && !isIgnored($0) }
        if duplicates.contains(where: { group in group.items.allSatisfy { item in reviewItems.contains { $0.id == item.id } } }) {
            error = "Keep at least one file in each duplicate group."
            return
        }
        guard !reviewItems.isEmpty else { return }
        showingReview = true
    }

    func moveToTrash() {
        guard !busy, !reviewItems.isEmpty else { return }
        guard let journal, !recoveryLoading, journalError == nil, recoveryNotices.isEmpty else {
            error = journalError ?? "Review interrupted operations in Activity before cleaning."; return
        }
        let items = reviewItems
        let roots = authorizedRoots
        let exclusions = ignored
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        busy = true; showingReview = false; status = "Validating selected items…"
        Task {
            do {
                // Preflight the whole plan before the first mutation. Each item is checked again immediately before Trash.
                try await offMain {
                    let engine = SafetyEngine(ignoredPaths: exclusions)
                    for item in items { try engine.validate(item, authorizedRoots: roots, runningBundleIDs: running) }
                }
                for item in items {
                    let currentRunning = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                    let record = try await journal.trash(item, authorizedRoots: roots, ignoredPaths: exclusions, runningBundleIDs: currentRunning)
                    history.insert(record, at: 0)
                    cleanup.removeAll { $0.id == item.id }; storage.removeAll { $0.id == item.id }; footprint.removeAll { $0.id == item.id }
                    duplicates = [] // Content groups must be reverified after a move.
                    applications.removeAll { $0.url == item.url }
                    leftovers.removeAll { $0.id == item.id }
                    if item.category == .applications { didScanLeftovers = false }
                }
                selected = []; status = "Moved to Trash · restore from Activity"
            } catch {
                self.error = error.localizedDescription; status = "Stopped · review Activity for completed moves"
                do { apply(try await journal.reconcile()) } catch { journalError = error.localizedDescription }
            }
            finish()
        }
    }

    func loadJournal() async {
        guard !recoveryStarted else { return }
        recoveryStarted = true
        defer { recoveryLoading = false }
        guard let journal else { return }
        do { apply(try await journal.reconcile()) }
        catch { journalError = "Activity recovery needs attention: \(error.localizedDescription)" }
    }

    private func apply(_ snapshot: JournalSnapshot) {
        history = snapshot.records; recoveryNotices = snapshot.unresolved
    }

    func checkRecovery() {
        guard !busy else { return }
        do { journal = try CleanupJournal() }
        catch { journalError = error.localizedDescription; return }
        guard let journal else { return }
        busy = true
        Task {
            do { apply(try await journal.reconcile()); journalError = nil }
            catch { journalError = error.localizedDescription }
            finish()
        }
    }

    func acknowledgeRecovery(_ notice: RecoveryNotice) {
        guard !busy, let journal else { return }
        busy = true
        Task {
            do { apply(try await journal.acknowledge(notice.id)) }
            catch { self.error = error.localizedDescription }
            finish()
        }
    }

    func restore(_ record: CleanupRecord) {
        guard !busy, !recoveryLoading, journalError == nil, let journal else { return }
        busy = true; status = "Checking the item in Trash…"
        Task {
            do {
                try await journal.restore(record)
                apply(await journal.snapshot()); status = "Restored \(record.original.lastPathComponent)"
            } catch {
                self.error = error.localizedDescription
                do { apply(try await journal.reconcile()) } catch { journalError = error.localizedDescription }
            }
            finish()
        }
    }

    func ignore(_ item: CleanupItem) {
        ignored.insert(item.id); selected.remove(item.id)
        UserDefaults.standard.set(Array(ignored), forKey: ignoreKey)
    }
    func unignore(_ path: String) {
        ignored.remove(path); UserDefaults.standard.set(Array(ignored), forKey: ignoreKey)
    }
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:\(anchor)") { NSWorkspace.shared.open(url) }
    }
}
