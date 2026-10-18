import SwiftUI
import LumaCore

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", clean = "Clean", optimizer = "Optimizer", applications = "Applications"
    case downloads = "Downloads", projects = "Projects", storage = "Storage", duplicates = "Duplicates", privacy = "Privacy", system = "System", history = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .optimizer: "slider.horizontal.3"
        case .applications: "square.stack.3d.up"
        case .downloads: "arrow.down.circle"
        case .projects: "curlybraces"
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
        case .downloads: "Your downloads. Keep what you still need."
        case .projects: "Build output and dependencies, reviewed project by project."
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
    var storageIndex: StorageIndex?
    var storageDirectory: String?
    var storageFocus: String?

    func navigateStorage(_ id: String) {
        guard storageIndex?.nodes[id]?.canNavigate == true, !operationBusy else { return }
        selected = []; storageFocus = nil; storageDirectory = id
    }

    func reviewStorage() {
        guard !busy, let index = storageIndex, let directory = storageDirectory else { return }
        let ids = selected
        guard !ids.isEmpty else { return }
        let roots = authorizedRoots, exclusions = ignored
        reviewPlan = nil; busy = true; status = "Verifying selection and logical size…"
        scanTask = Task {
            do {
                let plan = try await offMain {
                    let items = try index.reviewItems(ids: ids, directory: directory)
                    let scope = SafetyEngine(ignoredPaths: exclusions)
                    guard items.allSatisfy({ scope.permitsManualSelection(at: $0.url, authorizedRoots: roots) }) else {
                        throw LumaError.rejected("This selection is protected or outside your authorized home-folder scope.")
                    }
                    return try CleanupPlan(items: items, authorizedRoots: roots, ignoredPaths: exclusions, source: .storage)
                }
                try Task.checkCancellation()
                reviewPlan = plan; showingReview = true; status = "Review your selection"
            } catch is CancellationError { status = "Review cancelled · no changes made" }
            catch { self.error = error.localizedDescription; status = "Selection needs a new review" }
            finish()
        }
    }

    func invalidateStorage() {
        storageIndex = nil; storageDirectory = nil; storageFocus = nil
        storage = []; selected = []
        completedScans.remove(.storage); completedSnapshots.removeValue(forKey: .storage)
        scanSessions.invalidateSnapshots(for: [.storage])
    }
    var duplicates: [DuplicateGroup] = []
    var applications: [ApplicationRecord] = []
    var applicationTab: ApplicationTab = .installed
    var leftovers: [CleanupItem] = []
    var didScanLeftovers = false
    var reviewingApplicationReset = false
    var footprint: [CleanupItem] = []
    var footprintDetails: ApplicationFootprint?
    var inspectedApp: ApplicationRecord?
    var selected: Set<String> = []
    var scanTask: Task<Void, Never>?
    let scanSessions = ScanController()
    @ObservationIgnored var scanRunner: @Sendable (ScanRequest, @escaping ScanEmitter) async throws -> ScanResult = {
        try await ScanEngine.run($0, emit: $1)
    }
    private var operationBusy = false
    var busy: Bool {
        get { operationBusy || scanSessions.isBusy }
        set { operationBusy = newValue }
    }
    private var operationStatus = "Ready when you are"
    var status: String {
        get { scanSessions.isBusy ? scanSessions.statusText : operationStatus }
        set { operationStatus = newValue }
    }
    var completedSnapshots: [ScanTarget: ScanSnapshot] = [:]
    var scanRequests: [ScanTarget: ScanRequest] = [:]
    var canStartScan: Bool { !operationBusy }
    var currentScanTarget: ScanTarget? {
        switch destination ?? .overview {
        case .overview: .overview
        case .clean: .generatedData
        case .applications: applicationTab == .leftovers ? .leftovers : .applications
        case .downloads: .downloads
        case .projects: .developerProjects
        case .storage: .storage
        case .duplicates: .duplicates
        default: nil
        }
    }
    var currentNotices: [String] { currentScanTarget.flatMap { completedSnapshots[$0]?.result.report.notices } ?? [] }
    var canCancel: Bool { scanSessions.isBusy || scanTask != nil }
    let cleanupSession = CleanupSessionModel()
    var scanTarget: ScanTarget? { scanSessions.session?.request.target }
    var visibleApplications: [ApplicationRecord] {
        if scanSessions.isBusy, [.applications, .overview].contains(scanTarget) {
            return scanSessions.session?.preview.applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } ?? []
        }
        return applications
    }
    var cleanupReport: ScanReport?
    var recoveryNotices: [RecoveryNotice] = []
    var recoveryLoading = true
    var journalError: String?
    @ObservationIgnored private var journal: CleanupJournal?
    @ObservationIgnored private var recoveryStarted = false
    var error: String?
    var reviewPlan: CleanupPlan?
    var reviewItems: [CleanupItem] { reviewPlan?.items ?? [] }
    var showingReview = false
    var search = ""
    var showingSearch = false
    var downloadsTab = DownloadsTab.files
    var downloadsRoot: URL?
    var downloadsInventory: DownloadsInventory?
    var downloadFocus: String?
    var downloadPreview: DownloadPreview?
    @ObservationIgnored var downloadPreviewTask: Task<Void, Never>?
    var projectRoot: URL?
    var projectInventory: ProjectInventory?
    var storageRoot: URL?
    var duplicateRoot: URL?
    var authorizedRoots: [URL] = []
    var history: [CleanupRecord] = []
    var ignored: Set<String> = []
    var completedScans: Set<Destination> = []
    private var monitorTask: Task<Void, Never>?
    private let ignoreKey = "luma.ignoredPaths"
    var cleanupBytes: Int64 { generatedBytes(cleanup.filter { !isIgnored($0) }) }
    func generatedBytes(_ items: [CleanupItem]) -> Int64 {
        cleanupReport?.generatedAccounting.bytes(for: items) ?? items.reduce(0) { $0 + $1.bytes }
    }
    func isIgnored(_ item: CleanupItem) -> Bool {
        ignored.contains { Filesystem.isWithin(item.url, root: URL(fileURLWithPath: $0)) }
    }

    init() {
        do { journal = try CleanupJournal() }
        catch { journalError = "Activity could not be loaded. Cleanup is paused to preserve its records: \(error.localizedDescription)" }
        ignored = Set(UserDefaults.standard.stringArray(forKey: ignoreKey) ?? [])
        scanSessions.onChange = { [weak self] in
            guard let self else { return }
            self.operationStatus = self.scanSessions.statusText
        }
        scanSessions.onComplete = { [weak self] snapshot in self?.applyScan(snapshot) }
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
        guard !operationBusy else { return }
        let target = target ?? destination ?? .overview
        let request: ScanRequest
        switch target {
        case .overview: request = .init(.overview)
        case .clean: request = .init(.generatedData)
        case .applications: request = .init(applicationTab == .leftovers ? .leftovers : .applications)
        case .storage:
            guard let root = storageRoot else { return }
            request = .init(.storage, root: root)
        case .downloads:
            guard let root = downloadsRoot else { return }
            request = .init(.downloads, root: root, ignoredPaths: ignored)
        case .projects:
            guard let root = projectRoot else { return }
            request = .init(.developerProjects, root: root, ignoredPaths: ignored)
        case .duplicates:
            guard let root = duplicateRoot else { return }
            request = .init(.duplicates, root: root)
        default: return
        }
        startScan(request)
    }

    func startScan(_ input: ScanRequest) {
        guard !operationBusy else { return }
        let request = [.downloads, .developerProjects].contains(input.target)
            ? ScanRequest(input.target, root: input.root, ignoredPaths: ignored) : input
        if request.target == .downloads { downloadsRoot = request.root; clearDownloadPreview() }
        selected = []; reviewPlan = nil; showingReview = false
        if request.target == .developerProjects { projectRoot = request.root }
        if request.target == .storage { storageRoot = request.root }
        if request.target == .duplicates { duplicateRoot = request.root }
        scanRequests[request.target] = request
        let runner = scanRunner
        scanSessions.start(request) { emit in try await runner(request, emit) }
    }

    func retryScan(_ target: ScanTarget) {
        guard let request = scanRequests[target] else { return }
        startScan(request)
    }

    private func applyScan(_ snapshot: ScanSnapshot) {
        let result = snapshot.result
        completedSnapshots[snapshot.request.target] = snapshot
        switch snapshot.request.target {
        case .generatedData, .overview:
            cleanup = result.report.items; cleanupReport = result.report
            completedSnapshots[.generatedData] = snapshot; completedScans.insert(.clean)
            if snapshot.request.target == .overview {
                applications = result.applications; completedScans.insert(.applications)
                completedSnapshots[.applications] = snapshot
            }
        case .applications:
            applications = result.applications; completedScans.insert(.applications)
        case .downloads:
            downloadsInventory = result.downloadsInventory; completedScans.insert(.downloads); clearDownloadPreview()
        case .developerProjects:
            projectInventory = result.projectInventory; completedScans.insert(.projects)
        case .leftovers:
            leftovers = result.report.items; didScanLeftovers = true
        case .storage:
            storage = result.report.items
            storageIndex = result.storageIndex
            storageDirectory = result.storageIndex?.rootID
            storageFocus = nil; selected = []
            completedScans.insert(.storage)
        case .duplicates:
            duplicates = result.duplicates; completedScans.insert(.duplicates)
        case .footprint:
            if inspectedApp?.id == snapshot.request.application?.id {
                footprint = result.report.items
                footprintDetails = result.applicationFootprint
            }
        }
    }

    func snapshot(for target: ScanTarget) -> ScanSnapshot? { completedSnapshots[target] }

    private func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let child = Task.detached(priority: .utility, operation: work)
        return try await withTaskCancellationHandler(operation: { try await child.value }, onCancel: { child.cancel() })
    }
    private func finish() { operationBusy = false; scanTask = nil }
    func cancel() {
        if scanSessions.isBusy { scanSessions.cancel() } else { scanTask?.cancel() }
    }

    func chooseFolder(for target: Destination) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Analyze folder"; panel.message = "Luma scans this folder locally. Nothing is selected for removal."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if target == .downloads { downloadsRoot = url } else if target == .projects { projectRoot = url } else if target == .storage { storageRoot = url } else { duplicateRoot = url }
        authorizedRoots.append(url); destination = target
        runScan(target)
    }

    func inspect(_ app: ApplicationRecord) {
        guard !operationBusy else { return }
        reviewingApplicationReset = false
        footprint = []; footprintDetails = nil; selected = []; inspectedApp = app
        startScan(.init(.footprint, application: app))
    }

    func review(_ items: [CleanupItem], source: CleanupSource? = nil, resetApplication: ApplicationRecord? = nil) {
        guard !busy else { return }
        let items = items.filter { selected.contains($0.id) && !isIgnored($0) }
        guard !items.isEmpty else { return }
        let source = source ?? {
            switch destination {
            case .overview, .clean: CleanupSource.generatedData
            case .applications: applicationTab == .leftovers ? .leftovers : .applications
            case .downloads: .downloads
            case .projects: .developerProjects
            case .duplicates: .duplicates
            default: .storage
            }
        }()
        let target: ScanTarget
        switch source {
        case .generatedData: target = .generatedData
        case .applications, .applicationReset: target = .footprint
        case .leftovers: target = .leftovers
        case .storage: target = .storage
        case .duplicates: target = .duplicates
        case .developerProjects: target = .developerProjects
        case .downloads: target = .downloads
        }
        guard let snapshot = completedSnapshots[target] else {
            error = "Finish a scan before reviewing cleanup. Preview results cannot be selected."; return
        }
        let candidates = target == .duplicates ? snapshot.result.duplicates.flatMap(\.items) : snapshot.result.report.items
        guard items.allSatisfy({ item in candidates.contains { $0 == item } }) else {
            error = "This selection is not part of the completed scan. Scan again before reviewing."; return
        }
        let roots = authorizedRoots, exclusions = ignored
        let downloadSnapshot = downloadsInventory
        let groups = source == .duplicates ? duplicates : source == .downloads ? (downloadsInventory?.duplicates ?? []) : []
        reviewPlan = nil; busy = true; status = "Verifying selection and logical size…"
        scanTask = Task {
            do {
                let plan = try await offMain {
                    if source == .downloads {
                        guard let downloadSnapshot else { throw LumaError.rejected("Finish a Downloads scan before review.") }
                        return try downloadSnapshot.reviewPlan(ids: Set(items.map(\.id)), authorizedRoots: roots, ignoredPaths: exclusions)
                    }
                    return try CleanupPlan(items: items, authorizedRoots: roots, ignoredPaths: exclusions, duplicateGroups: groups, source: source, resetApplication: resetApplication)
                }
                try Task.checkCancellation()
                reviewPlan = plan; showingReview = true; status = "Review your selection"
            } catch is CancellationError { status = "Review cancelled · no changes made" }
            catch { self.error = error.localizedDescription; status = "Selection needs a new review" }
            finish()
        }
    }

    /// Mutation outcomes invalidate the completed generated-data snapshot, even
    /// when only part of a plan moved. No stale category totals enter review.
    func invalidateGeneratedFindings() {
        selected.subtract((cleanupReport?.items ?? cleanup).map(\.id))
        cleanup = []; cleanupReport = nil
        completedScans.remove(.clean)
        completedSnapshots.removeValue(forKey: .generatedData)
        completedSnapshots.removeValue(forKey: .overview)
        scanSessions.invalidateSnapshots(for: [.generatedData, .overview])
    }

    func clearDownloadPreview() {
        downloadPreviewTask?.cancel(); downloadPreviewTask = nil
        downloadFocus = nil; downloadPreview = nil
    }

    func previewDownload(_ file: DownloadFile) {
        guard downloadsInventory?.files.contains(where: { $0.id == file.id }) == true,
              !ignored.contains(where: { Filesystem.isWithin(file.url, root: URL(fileURLWithPath: $0)) }) else { return }
        clearDownloadPreview(); downloadFocus = file.id
        downloadPreviewTask = Task { @MainActor [weak self] in
            do {
                let preview = try await self?.offMain { try DownloadPreviewReader.read(file) }
                try Task.checkCancellation()
                guard self?.downloadFocus == file.id, self?.ignored.contains(where: { Filesystem.isWithin(file.url, root: URL(fileURLWithPath: $0)) }) == false else { return }
                self?.downloadPreview = preview
            } catch is CancellationError { }
            catch { if self?.downloadFocus == file.id { self?.downloadPreview = .unavailable(error.localizedDescription) } }
        }
    }

    func selectDownloadKeeper(group: DuplicateGroup, keeper: CleanupItem) {
        guard !busy, let inventory = downloadsInventory else { return }
        do {
            let otherCopies = try inventory.keeperSelection(groupID: group.id, keeperID: keeper.id, ignoredPaths: ignored)
            selected.subtract(group.items.map(\.id)); selected.formUnion(otherCopies)
        } catch { self.error = error.localizedDescription }
    }

    func invalidateDownloads() {
        selected.subtract(downloadsInventory?.report.items.map(\.id) ?? [])
        downloadsInventory = nil; completedScans.remove(.downloads); clearDownloadPreview()
        completedSnapshots.removeValue(forKey: .downloads)
        scanSessions.invalidateSnapshots(for: [.downloads])
    }

    func invalidateProjects() {
        selected.subtract(projectInventory?.report.items.map(\.id) ?? [])
        projectInventory = nil; completedScans.remove(.projects)
        completedSnapshots.removeValue(forKey: .developerProjects)
        scanSessions.invalidateSnapshots(for: [.developerProjects])
    }

    func invalidateLeftovers() {
        selected.subtract(leftovers.map(\.id))
        leftovers = []; didScanLeftovers = false
        completedSnapshots.removeValue(forKey: .leftovers)
        scanSessions.invalidateSnapshots(for: [.leftovers])
    }

    func invalidateApplicationFootprint() {
        selected.subtract(footprint.map(\.id))
        footprint = []; footprintDetails = nil
        completedSnapshots.removeValue(forKey: .footprint)
        scanSessions.invalidateSnapshots(for: [.footprint])
    }

    func moveToTrash() {
        guard !busy, let plan = reviewPlan else { return }
        guard let journal, !recoveryLoading, journalError == nil, recoveryNotices.isEmpty else {
            error = journalError ?? "Review interrupted operations in Activity before cleaning."; return
        }
        busy = true; showingReview = false; status = "Validating selected items…"
        cleanupSession.run { [self] in
            defer { invalidateDownloads(); invalidateProjects(); invalidateGeneratedFindings(); invalidateStorage(); invalidateApplicationFootprint(); invalidateLeftovers() }
            do {
                _ = try await journal.execute(plan, context: { @MainActor [self] in
                    await .current(ignoredPaths: ignored)
                }, onRecord: { @MainActor [self] record in
                    history.insert(record, at: 0)
                    cleanup.removeAll { $0.url == record.original }; storage.removeAll { $0.url == record.original }; footprint.removeAll { $0.url == record.original }
                    duplicates = [] // Content groups must be reverified after a move.
                    applications.removeAll { $0.url == record.original }
                    leftovers.removeAll { $0.url == record.original }
                    if record.original.pathExtension == "app" { didScanLeftovers = false }
                    status = "Moving reviewed items to Trash…"
                }, onProgress: { @MainActor [self] progress in
                    cleanupSession.update(progress)
                })
                selected = []; status = "Moved to Trash · restore from Activity"
            } catch {
                if !(error is CancellationError) { self.error = error.localizedDescription }
                status = "Stopped · review Activity for completed moves"
                do { apply(try await journal.reconcile()) } catch { journalError = error.localizedDescription }
            }
            apply(await journal.snapshot())
            status = "Cleanup finished · review Activity for moved and remaining items"
            reviewPlan = nil
            finish()
        }
    }

    #if DEBUG
    // Opt-in QA swaps only the journal, using a disposable generated home.
    func installFixtureJournal(_ fixture: CleanupJournal) async throws {
        guard !busy else { throw LumaError.rejected("Wait for the current operation.") }
        journal = fixture
        apply(try await fixture.reconcile())
        recoveryLoading = false; journalError = nil
    }
    #endif

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
        cleanupSession.sessions = snapshot.sessions
        cleanupSession.undoAttempts = snapshot.undoAttempts
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

    func reviewUndo(_ session: CleanupSession) {
        guard !busy, let journal else { return }
        busy = true; status = "Checking Undo eligibility…"
        Task {
            do {
                cleanupSession.undoReview = try await journal.reviewUndo(sessionID: session.id)
                apply(await journal.snapshot())
            } catch { self.error = error.localizedDescription }
            finish()
        }
    }

    func undoSession() {
        guard !busy, let review = cleanupSession.undoReview, let journal else { return }
        cleanupSession.undoReview = nil
        busy = true; status = "Restoring reviewed items…"
        cleanupSession.run { [self] in
            defer { invalidateDownloads(); invalidateProjects(); invalidateGeneratedFindings(); invalidateStorage(); invalidateApplicationFootprint(); invalidateLeftovers() }
            do {
                try await journal.undo(review, onProgress: { @MainActor [self] in cleanupSession.update($0) })
            } catch {
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            do { apply(try await journal.reconcile()) }
            catch { journalError = error.localizedDescription; apply(await journal.snapshot()) }
            status = "Undo finished · review Activity for individual outcomes"
            finish()
        }
    }

    func restore(_ record: CleanupRecord) {
        guard !busy, !recoveryLoading, journalError == nil, let journal else { return }
        busy = true; status = "Checking the item in Trash…"
        Task {
            defer { invalidateDownloads(); invalidateProjects(); invalidateGeneratedFindings(); invalidateStorage(); invalidateApplicationFootprint(); invalidateLeftovers() }
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
        clearDownloadPreview()
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
