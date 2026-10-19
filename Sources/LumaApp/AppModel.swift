import SwiftUI
import LumaCore

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", clean = "Clean", optimizer = "Optimizer", applications = "Apps"
    case backups = "Backups", downloads = "Downloads", projects = "Projects", storage = "Storage", duplicates = "Duplicates", privacy = "Privacy", system = "System", history = "Activity"
    case residues = "Residues", maintenance = "Maintenance"
    static let core: [Destination] = [.overview, .storage, .applications, .residues, .maintenance, .system]
    static let allCases: [Destination] = core + [.history]
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .residues: "link"
        case .maintenance: "sparkles"
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .optimizer: "slider.horizontal.3"
        case .applications: "square.stack.3d.up"
        case .backups: "externaldrive.badge.person.crop"
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
        case .residues: "Potentially unclaimed data. Keep what you still need."
        case .maintenance: "Simple maintenance, with explicit choices."
        case .overview: "A clearer picture of your Mac."
        case .clean: "Generated data, with every decision explained."
        case .optimizer: "Understand what’s running. Change what matters."
        case .applications: "See what’s installed and what it leaves behind."
        case .backups: "Local device backups may be your only copy."
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

enum ApplicationTab: String, CaseIterable { case installed = "Installed", leftovers = "Residues" }

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    let computerName = Host.current().localizedName ?? "This Mac"
    @ObservationIgnored weak var mainWindow: NSWindow?
    var processDetailsVisible: Bool {
        mainWindow?.isVisible == true && mainWindow?.isMiniaturized == false && mainWindow?.occlusionState.contains(.visible) == true && (destination == .system || destination == .optimizer)
    }
    func openMain(_ target: Destination? = nil) {
        if let target { openCore(target) }
        showMainWindow?()
    }
    @ObservationIgnored var showMainWindow: (() -> Void)?
    @ObservationIgnored var showSettingsWindow: (() -> Void)?
    var destination: Destination? = .overview
    var system = SystemSample()
    var runningApplicationIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    var runningApplicationURLs = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
    var monitoringFocus: String?
    var networkInterface: String?
    var networkTracker = NetworkActivityTracker()
    @ObservationIgnored var wakeObserver: NSObjectProtocol?
    @ObservationIgnored var monitoringCollector: @Sendable ([UInt64], Bool) -> SystemSample = { previous, includeProcesses in
        SystemSample.collect(previous: previous, includeProcesses: includeProcesses)
    }
    var smartMeasurement: SystemSample?
    var smartStartedAt: Date?
    var smartPhase: ScanPhase?
    var smartSnapshots: [ScanTarget: ScanSnapshot] = [:]
    var smartScopes: [ScanTarget: URL] = [:]
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var cleanup: [CleanupItem] = []
    var storage: [CleanupItem] = []
    let storageVolumes = StorageVolumeModel()
    var storageRevision: UInt64 = 0
    var storageIndex: StorageIndex? { didSet { storageRevision &+= 1 } }
    var storageDirectory: String?
    var storageFocus: String?
    let storageDiscovery = ScanController()
    @ObservationIgnored var storageStore = StorageObservationStore()
    var storageAcceptAutomatic = true
    @ObservationIgnored var storagePreviewSession: UUID?
    @ObservationIgnored var storagePreviewRevision: UInt64 = 0
    @ObservationIgnored var storageRetainsCompletedResults = false
    var storageCacheGeneration = UUID()
    var storageEntered = false
    var storageLoading = false
    var storageSelection: Set<String> = []
    var storageMode = "Largest files"
    var storageSort = "Size"
    var storageFilter = "All items"
    var storageShowHidden = false
    var storageSearch = ""
    var storageLocation = "All locations"
    var storageBack: [String] = []
    var storageForward: [String] = []
    var storageOutcome: String?
    var storageMoving = false
    var storageStatus = "No scan started"
    var lastStorageSessionID: UUID?
    var storageLimit = 40_000
    @ObservationIgnored var storageWatch: Task<Void, Never>?
    @ObservationIgnored var storageChanges: StorageChanges?
    @ObservationIgnored var storageRootsOverride: [URL]?


    func invalidateStorage() {
        storageVolumes.stopObserving()
        storageIndex = nil; storageDirectory = nil; storageFocus = nil
        storage = []; storageSelection = []; clearSelection(for: Destination.storage.rawValue)
        completedScans.remove(.storage); completedSnapshots.removeValue(forKey: .storage)
        scanSessions.invalidateSnapshots(for: [.storage])
    }
    var duplicates: [DuplicateGroup] = []
    var duplicateChoice: DuplicateKeeperChoice?
    var duplicateChoiceSource: CleanupSource?
    var duplicateComparisonGroup: String?
    var duplicateComparisons: [String: DuplicateComparison] = [:]
    var duplicateComparisonErrors: [String: String] = [:]
    @ObservationIgnored var duplicateComparisonTask: Task<Void, Never>?
    @ObservationIgnored var duplicateComparisonGeneration = UUID()
    var applications: [ApplicationRecord] = []
    var applicationTab: ApplicationTab = .installed
    var applicationSearch = ""
    var leftovers: [CleanupItem] = []
    let residueDiscovery = ScanController()
    @ObservationIgnored var residueStore = ResidueObservationStore()
    var residueSelection: [String: CleanupItem] = [:]
    var residueDirtyOwners: Set<String> = []
    var residueEntered = false
    var residueLoaded = false
    var residueLoading = false
    var residueTerminalID: UUID?
    var residueMoving = false
    var residueSavedAt: Date?
    var residueCoverage: [String] = []
    var residueStatus = "Checking ownership…"
    var residueOutcome: String?
    var lastResidueSessionID: UUID?
    var didScanLeftovers = false
    var reviewingApplicationReset = false
    var footprint: [CleanupItem] = []
    var footprintDetails: ApplicationFootprint?
    var inspectedApp: ApplicationRecord?
    var selectionScope: String {
        if let inspectedApp {
            return "footprint:" + inspectedApp.id + ":" + (completedSnapshots[.footprint]?.sessionID.uuidString ?? "pending")
        }
        let feature = (destination ?? .overview).rawValue
            + (destination == .applications ? applicationTab.rawValue : "")
            + (destination == .downloads ? downloadsTab.rawValue : "")
        let root: URL?
        switch destination {
        case .storage: root = storageRoot
        case .downloads: root = downloadsRoot
        case .projects: root = projectRoot
        case .duplicates: root = duplicateRoot
        default: root = nil
        }
        let snapshot = currentScanTarget.flatMap { completedSnapshots[$0]?.sessionID.uuidString } ?? "pending"
        return feature + ":" + (root?.path ?? "") + ":" + snapshot
    }
    private var selections: [String: Set<String>] = [:]
    var selected: Set<String> {
        get { destination == .storage ? storageSelection : selections[selectionScope] ?? [] }
        set { if destination == .storage { storageSelection = newValue } else { selections[selectionScope] = newValue } }
    }
    let applicationInventory = ScanController()
    var uninstallMessages: [String: String] = [:]
    var uninstallingApp: String?
    var uninstallOutcome: String?
    var lastUninstallSessionID: UUID?
    var removedApplicationPaths: Set<String> = []

    var scanTask: Task<Void, Never>?
    let scanSessions = ScanController()
    @ObservationIgnored var analysisIndex = AnalysisIndex()
    var analysisCacheStatus: String?
    @ObservationIgnored var scanRunner: @Sendable (ScanRequest, @escaping ScanEmitter) async throws -> ScanResult = {
        try await ScanEngine.run($0, emit: $1)
    }
    var operationBusy = false
    var busy: Bool {
        get { operationBusy || scanSessions.isBusy }
        set { operationBusy = newValue }
    }
    private var operationStatus = "Ready when you are"
    var status: String {
        get {
            if cleanupSession.isRunning { return operationStatus }
            if destination == .storage { return storageOutcome ?? storageStatus }
            if destination == .residues { return residueOutcome ?? residueStatus }
            if destination == .applications, applicationTab == .installed, let uninstallOutcome { return uninstallOutcome }
            return scanSessions.isBusy ? scanSessions.statusText : operationStatus
        }
        set { operationStatus = newValue }
    }
    var completedSnapshots: [ScanTarget: ScanSnapshot] = [:]
    var scanRequests: [ScanTarget: ScanRequest] = [:]
    var canStartScan: Bool { !operationBusy }
    var currentScanTarget: ScanTarget? {
        switch destination ?? .overview {
        case .residues: .leftovers
        case .maintenance: .generatedData
        case .overview: .overview
        case .clean: .generatedData
        case .applications: applicationTab == .leftovers ? .leftovers : .applications
        case .backups: .deviceBackups
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
    func mergeApplicationInventory(_ result: ScanResult) {
        let previous = Dictionary(applications.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let refreshed = result.applications.map { $0.preservingIcon(from: previous[$0.id]) }
        if result.report.isComplete { applications = refreshed }
        else {
            let unavailable = result.report.coverage.filter { $0.ruleID == "inventory" && $0.state != .missing }
                .map { URL(fileURLWithPath: $0.path) }
            var rows = previous.filter { _, app in unavailable.contains { Filesystem.isWithin(app.url, root: $0) } }
            for app in refreshed { rows[app.id] = app }
            applications = Array(rows.values)
        }
    }

    var visibleApplications: [ApplicationRecord] {
        var rows = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        let previews = applicationInventory.isBusy ? applicationInventory.session?.preview.applications ?? [] : []
        let scanPreviews = scanSessions.isBusy && [.applications, .overview].contains(scanTarget)
            ? scanSessions.session?.preview.applications ?? [] : []
        for app in previews + scanPreviews { rows[app.id] = app.preservingIcon(from: rows[app.id]) }
        return rows.values.filter { !removedApplicationPaths.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var cleanupReport: ScanReport?
    var recoveryNotices: [RecoveryNotice] = []
    var recoveryLoading = true
    var journalError: String?
    @ObservationIgnored var journal: CleanupJournal?
    @ObservationIgnored private var recoveryStarted = false
    var error: String?
    var reviewPlan: CleanupPlan?
    var reviewItems: [CleanupItem] { reviewPlan?.items ?? [] }
    var showingReview = false
    var reviewGeneration = UUID()
    var undoMessages: [UUID: String] = [:]
    var undoEligibility: [UUID: UndoReviewItem] = [:]
    var restoreMessages: [UUID: String] = [:]
    var uninstallHome = FileManager.default.homeDirectoryForCurrentUser
    var search = ""
    var showingSearch = false
    var deviceBackups: DeviceBackupInventory?
    var downloadsTab = DownloadsTab.files
    var downloadsRoot: URL?
    var downloadsInventory: DownloadsInventory?
    var downloadFocus: String?
    var downloadPreview: DownloadPreview?
    @ObservationIgnored var downloadPreviewTask: Task<Void, Never>?
    var projectRoot: URL?
    var projectInventory: ProjectInventory?
    var storageExpectedVolume: StorageVolumeIdentity?
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
        let index = analysisIndex
        scanRunner = { request, emit in try await ScanEngine.run(request, analysisIndex: index, emit: emit) }
        do { journal = try CleanupJournal() }
        catch { journalError = "Activity could not be loaded. Cleanup is paused to preserve its records: \(error.localizedDescription)" }
        ignored = Set(UserDefaults.standard.stringArray(forKey: ignoreKey) ?? [])
        scanSessions.onChange = { [weak self] in
            guard let self else { return }
            if !self.cleanupSession.isRunning { self.operationStatus = self.scanSessions.statusText }
            if let session = self.scanSessions.session, session.request.target == .storage, !self.storageAcceptAutomatic {
                self.storageStatus = self.scanSessions.isBusy
                    ? "Analyzing pending location: \(session.request.scope) · previous observations retained"
                    : (session.detail ?? self.scanSessions.statusText) + " · published observations retained"
            }
            if let session = self.scanSessions.session, session.request.target == .overview {
                self.smartPhase = session.phase
            }
        }
        applicationInventory.onComplete = { [weak self] snapshot in
            guard let self else { return }
            self.removedApplicationPaths.subtract(snapshot.result.applications.map(\.id))
            let oldOwners = Set(self.applications.map(\.bundleID))
            let newOwners = Set(snapshot.result.applications.map(\.bundleID))
            self.dirtyResidueOwners(oldOwners.symmetricDifference(newOwners))
            self.mergeApplicationInventory(snapshot.result)
            self.completedScans.insert(.applications)
        }
        residueDiscovery.onChange = { [weak self] in
            guard let self, let session = self.residueDiscovery.session else { return }
            self.residueStatus = self.residueDiscovery.isBusy ? "Refreshing ownership · previous observations stay visible" : session.detail ?? self.residueStatus
            if session.phase.isTerminal && ![.completed, .completedWithExclusions].contains(session.phase), self.residueTerminalID != session.id {
                self.residueTerminalID = session.id
                var rows = Dictionary(self.leftovers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                for item in session.preview.items { rows[item.id] = item }
                self.leftovers = Array(rows.values)
                self.residueEntered = false
                self.residueStatus = session.detail ?? "Refresh stopped · previous observations retained"
                self.residueCoverage = session.preview.notices + [self.residueStatus]
                self.saveResidues()
            }
        }
        residueDiscovery.onComplete = { [weak self] snapshot in
            guard let self else { return }
            let report = snapshot.result.report
            if let owners = snapshot.request.residueOwners {
                self.leftovers.removeAll { $0.ownerBundleID.map(owners.contains) == true }
                self.leftovers.append(contentsOf: report.items)
            } else { self.leftovers = report.items }
            self.didScanLeftovers = true
            self.residueSavedAt = snapshot.finishedAt
            self.residueCoverage = snapshot.request.residueOwners == nil ? report.notices : Array(Set(self.residueCoverage + report.notices)).sorted()
            self.residueStatus = !report.isComplete ? "Partial coverage · some locations could not be read" : snapshot.request.residueOwners == nil ? "Ownership check complete" : "Changed identifiers checked · other observations retained"
            let current = Dictionary(self.leftovers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            self.residueSelection = self.residueSelection.filter { id, captured in
                current[id]?.identity == captured.identity && current[id]?.identity.location == captured.identity.location
            }
            self.saveResidues()
        }
        configureStorageDiscovery()
        scanSessions.onComplete = { [weak self] snapshot in self?.applyScan(snapshot) }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.networkTracker.resetBaseline() }
        }
        monitorTask = Task {
            var iteration = 0
            while !Task.isCancelled {
                let previous = system.cpuTicks
                let includeProcesses = iteration % 3 == 0 && processDetailsVisible
                let collector = monitoringCollector
                var next = await Task.detached(priority: .utility) { collector(previous, includeProcesses) }.value
                if !includeProcesses { next.processes = system.processes; next.processGroups = system.processGroups }
                if let observation = next.networkObservation {
                    next.network = networkTracker.consume(observation, selectedInterface: networkInterface)
                }
                system = next
                let running = NSWorkspace.shared.runningApplications
                runningApplicationIDs = Set(running.compactMap(\.bundleIdentifier))
                runningApplicationURLs = running.compactMap(\.bundleURL)
                if system.cpuAvailable { cpuHistory = Array((cpuHistory + [system.cpu]).suffix(60)) }
                if system.memoryAvailable { memoryHistory = Array((memoryHistory + [system.memoryUsagePercent]).suffix(60)) }
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
        case .overview: request = .init(.overview, ignoredPaths: ignored, smartScopes: smartScopes)
        case .clean, .maintenance: request = .init(.generatedData)
        case .residues: ensureResidues(refresh: true); return
        case .applications:
            if applicationTab == .leftovers { ensureResidues(refresh: true); return }
            request = .init(.applications)
        case .storage:
            ensureStorage(refresh: true); return
        case .backups: request = .init(.deviceBackups, ignoredPaths: ignored)
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
        let request = [.downloads, .developerProjects, .deviceBackups, .storage].contains(input.target)
            ? ScanRequest(input.target, root: input.root, ignoredPaths: ignored, storageVolumeIdentity: input.storageVolumeIdentity) : input
        if request.target == .storage {
            storageAcceptAutomatic = false
            storageDiscovery.cancel()
        }
        if request.target == .downloads { downloadsRoot = request.root; clearDownloadPreview() }
        if currentScanTarget == request.target && request.target != .storage { selected = [] }
        if currentScanTarget == request.target { cancelPendingReview() }
        if request.target == .developerProjects { projectRoot = request.root }

        if request.target == .duplicates { duplicateRoot = request.root }
        if request.target == .overview { smartMeasurement = system; smartStartedAt = Date() }
        scanRequests[request.target] = request
        let runner = scanRunner
        scanSessions.start(request) { emit in try await runner(request, emit) }
    }

    func clearAnalysisCache() {
        guard !busy else { return }
        let index = analysisIndex, store = storageStore
        storageCacheGeneration = UUID(); storageDiscovery.cancel()
        busy = true
        analysisCacheStatus = "Clearing saved analysis…"
        scanTask = Task {
            do {
                while storageDiscovery.isBusy { try await Task.sleep(for: .milliseconds(20)) }
                try await offMain { try index.clear() }
                try await store.clear()
                storageEntered = false
                analysisCacheStatus = "Saved analysis cleared. Activity and ignored paths are preserved."
            } catch { analysisCacheStatus = "Analysis cache could not be cleared: \(error.localizedDescription)" }
            finish()
        }
    }

    func retryScan(_ target: ScanTarget) {
        guard let request = scanRequests[target] else { return }
        startScan(request)
    }

    private func applyScan(_ snapshot: ScanSnapshot) {
        let result = snapshot.result
        if snapshot.request.target != .overview,
           scanSessions.session?.request.target == .overview,
           scanSessions.session?.id == snapshot.sessionID {
            smartSnapshots[snapshot.request.target] = snapshot
            scanRequests[snapshot.request.target] = snapshot.request
            if snapshot.request.target == .downloads { downloadsRoot = snapshot.request.root }
            if snapshot.request.target == .developerProjects { projectRoot = snapshot.request.root }
        }
        completedSnapshots[snapshot.request.target] = snapshot
        switch snapshot.request.target {
        case .overview: break // Completed subchecks were committed progressively.
        case .generatedData:
            cleanup = result.report.items; cleanupReport = result.report
            completedSnapshots[.generatedData] = snapshot; completedScans.insert(.clean)
        case .applications:
            mergeApplicationInventory(result); completedScans.insert(.applications)
        case .deviceBackups:
            deviceBackups = result.deviceBackups; completedScans.insert(.backups)
        case .downloads:
            clearDuplicateComparison(); duplicateChoice = nil
            clearSelection(for: Destination.downloads.rawValue)
            downloadsInventory = result.downloadsInventory; completedScans.insert(.downloads); clearDownloadPreview()
        case .developerProjects:
            projectInventory = result.projectInventory; completedScans.insert(.projects)
        case .leftovers:
            leftovers = result.report.items; didScanLeftovers = true
        case .storage:
            if !storageAcceptAutomatic, let index = result.storageIndex { publishStorage(index) }
            completedScans.insert(.storage)
        case .duplicates:
            clearDuplicateComparison(); duplicateChoice = nil
            duplicates = result.duplicates; clearSelection(for: Destination.duplicates.rawValue); completedScans.insert(.duplicates)
        case .footprint:
            if inspectedApp?.id == snapshot.request.application?.id {
                footprint = result.report.items
                footprintDetails = result.applicationFootprint
            }
        }
    }

    func snapshot(for target: ScanTarget) -> ScanSnapshot? { completedSnapshots[target] }

    func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let child = Task.detached(priority: .utility, operation: work)
        return try await withTaskCancellationHandler(operation: { try await child.value }, onCancel: { child.cancel() })
    }
    func finish() {
        operationBusy = false; scanTask = nil
        if (destination == .residues || (destination == .applications && applicationTab == .leftovers)) && (!residueEntered || !residueDirtyOwners.isEmpty) {
            ensureResidues()
        }
    }
    func cancel() {
        if scanSessions.isBusy { scanSessions.cancel() } else { scanTask?.cancel() }
    }

    func chooseFolder(for target: Destination) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Analyze folder"; panel.message = "Luma scans this folder locally. Nothing is selected for removal."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if target == .downloads { downloadsRoot = url } else if target == .projects { projectRoot = url } else if target == .storage { storageExpectedVolume = nil } else { duplicateRoot = url }
        authorizedRoots.append(url); destination = target
        if target == .storage { startScan(.init(.storage, root: url)) }
        else { runScan(target) }
    }

    func inspect(_ app: ApplicationRecord) {
        guard !operationBusy else { return }
        reviewingApplicationReset = false
        footprint = []; footprintDetails = nil; selected = []; inspectedApp = app
        startScan(.init(.footprint, application: app))
    }

    func review(_ items: [CleanupItem], source: CleanupSource? = nil, resetApplication: ApplicationRecord? = nil, capturedSelection: Set<String>? = nil) {
        guard !busy else { return }
        let intent = capturedSelection ?? selected
        let items = items.filter { intent.contains($0.id) && !isIgnored($0) }
        guard !items.isEmpty else { return }
        let source = source ?? {
            switch destination {
            case .overview, .clean, .maintenance: CleanupSource.generatedData
            case .residues: .leftovers
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
        let scope = selectionScope, generation = reviewGeneration
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
                guard selectionScope == scope, reviewGeneration == generation else { finish(); return }
                reviewPlan = plan; showingReview = true; status = "Review your selection"
            } catch is CancellationError { status = "Review cancelled · no changes made" }
            catch { self.error = error.localizedDescription; status = "Selection needs a new review" }
            finish()
        }
    }

    /// Mutation outcomes invalidate the completed generated-data snapshot, even
    /// when only part of a plan moved. No stale category totals enter review.
    func invalidateGeneratedFindings() {
        clearSelection(for: Destination.clean.rawValue); clearSelection(for: Destination.overview.rawValue)
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

    func invalidateDownloads() {
        clearDuplicateComparison(); duplicateChoice = nil
        clearSelection(for: Destination.downloads.rawValue)
        downloadsInventory = nil; completedScans.remove(.downloads); clearDownloadPreview()
        completedSnapshots.removeValue(forKey: .downloads)
        scanSessions.invalidateSnapshots(for: [.downloads])
    }

    func invalidateProjects() {
        clearSelection(for: Destination.projects.rawValue)
        projectInventory = nil; completedScans.remove(.projects)
        completedSnapshots.removeValue(forKey: .developerProjects)
        scanSessions.invalidateSnapshots(for: [.developerProjects])
    }

    func invalidateLeftovers() {
        // Saved observations and captured selection survive invalidation. They
        // cannot execute until current identity and ownership have been checked.
        residueEntered = false
        completedSnapshots.removeValue(forKey: .leftovers)
        scanSessions.invalidateSnapshots(for: [.leftovers])
    }

    func invalidateApplicationFootprint() {
        clearSelection(for: "footprint:")
        footprint = []; footprintDetails = nil
        completedSnapshots.removeValue(forKey: .footprint)
        scanSessions.invalidateSnapshots(for: [.footprint])
    }

    func moveToTrash() {
        guard !busy, let plan = reviewPlan else { return }
        guard let journal, !recoveryLoading, journalError == nil, recoveryNotices.isEmpty else {
            error = journalError ?? "Review interrupted operations in Activity before cleaning."; return
        }
        let capturedScope = selectionScope
        busy = true; showingReview = false; status = "Validating selected items…"
        let affectsApplications = [.applications, .applicationReset].contains(plan.source) || plan.items.contains { $0.url.pathExtension == "app" }
        if affectsApplications { pauseApplicationReads() }
        cleanupSession.run { [self] in
            defer {
                let changed = history.filter { $0.planID == plan.id }.map(\.original)
                invalidateObservations(affected: changed)
            }
            let detailEmitter = cleanupSession.detailEmitter
            do {
                if affectsApplications { try await waitForApplicationReads() }
                _ = try await journal.execute(plan, context: { @MainActor [self] in
                    await plan.executionContext(ignoredPaths: ignored)
                }, onRecord: { @MainActor [self] record in
                    history.insert(record, at: 0)
                    invalidateObservations(affected: [record.original])
                    cleanup.removeAll { $0.url == record.original }; storage.removeAll { $0.url == record.original }; footprint.removeAll { $0.url == record.original }
                    applications.removeAll { $0.url == record.original }
                    leftovers.removeAll { $0.url == record.original }
                    if record.original.pathExtension == "app" { didScanLeftovers = false }
                    status = "Moving reviewed items to Trash…"
                }, onProgress: { @MainActor [self] progress in
                    cleanupSession.update(progress)
                    status = progress.phase == .validating ? "Validating selected items…" : "Checking and moving reviewed items to Trash…"
                }, onDetail: detailEmitter)
                selections[capturedScope, default: []].subtract(plan.items.map(\.id)); status = "Moved to Trash · restore from Activity"
            } catch {
                if !(error is CancellationError) { self.error = error.localizedDescription }
                status = "Stopped · review Activity for completed moves"
                do { apply(try await journal.reconcile()) } catch { journalError = error.localizedDescription }
            }
            apply(await journal.snapshot())
            if let session = cleanupSession.sessions.first(where: { $0.id == plan.id }) {
                let moved = history.filter { $0.planID == plan.id }.count
                status = "\(session.phase.label) · \(moved) moved · \(plan.items.count - moved) remaining"
            }
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

    func apply(_ snapshot: JournalSnapshot) {
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

    func undo(_ session: CleanupSession) {
        let sessionID = session.id
        guard mutationUnavailableReason == nil, let journal else { return }
        operationBusy = true; status = "Checking Undo eligibility…"
        cleanupSession.restoring = true
        let affectsApplications = [.applications, .applicationReset].contains(session.source) || history.contains { $0.planID == sessionID && $0.original.pathExtension == "app" }
        if affectsApplications { pauseApplicationReads() }
        cleanupSession.run { [self] in
            defer { cleanupSession.restoring = false; finish() }
            do {
                if affectsApplications { try await waitForApplicationReads() }
                let review = try await journal.reviewUndo(sessionID: sessionID)
                for item in review.items { undoEligibility[item.id] = item }
                let conflicts = review.items.filter { $0.eligibility != .eligible && $0.eligibility != .restored }
                undoMessages[sessionID] = "\(review.eligibleIDs.count) eligible · \(conflicts.count) unavailable" + (conflicts.isEmpty ? "" : " · " + conflicts.map { "\($0.record.original.lastPathComponent): \($0.detail)" }.joined(separator: "; "))
                if !review.eligibleIDs.isEmpty {
                    try await journal.undo(review, onProgress: { @MainActor [self] in cleanupSession.update($0) })
                }
            } catch { undoMessages[sessionID] = error is CancellationError ? "Undo stopped." : error.localizedDescription }
            do { apply(try await journal.reconcile()) }
            catch { journalError = error.localizedDescription; apply(await journal.snapshot()) }
            let restored = history.filter { $0.planID == sessionID && $0.restored }
            if restored.contains(where: { $0.planSource == .leftovers }) { invalidateLeftovers() }
            invalidateObservations(affected: restored.map(\.original))
            await refreshRestoredApplications(restored)
            let attempt = cleanupSession.undoAttempts.last { $0.sessionID == sessionID }
            status = "Undo: \(attempt?.phase.label ?? "Checked") · \(restored.count) restored · \(undoMessages[sessionID] ?? "")"
            uninstallOutcome = status
            if restored.contains(where: { $0.planSource == .leftovers }) { residueOutcome = status }
            if restored.contains(where: { $0.planSource == .storage }) {
                storageOutcome = status
                refreshStorage(paths: restored.filter { $0.planSource == .storage }.map(\.original))
            }
        }
    }

    func restore(_ record: CleanupRecord) {
        guard mutationUnavailableReason == nil, let journal else { return }
        operationBusy = true; status = "Checking the item in Trash…"
        cleanupSession.restoring = true
        let affectsApplications = record.original.pathExtension == "app" || record.planSource == .applications || record.planSource == .applicationReset
        if affectsApplications { pauseApplicationReads() }
        cleanupSession.run { [self] in
            defer { cleanupSession.restoring = false; finish() }
            do {
                if affectsApplications { try await waitForApplicationReads() }
                try await journal.restore(record)
                apply(await journal.snapshot())
                let restored = history.filter { $0.id == record.id && $0.restored }
                if restored.contains(where: { $0.planSource == .leftovers }) { invalidateLeftovers() }
                invalidateObservations(affected: restored.map(\.original))
                await refreshRestoredApplications(restored)
                status = "Restored \(record.original.lastPathComponent)"
                if record.planSource == .storage {
                    storageOutcome = status
                    refreshStorage(paths: restored.map(\.original))
                }
            } catch {
                status = error is CancellationError ? "Restore stopped" : "Restore failed: \(error.localizedDescription)"
                restoreMessages[record.id] = status
                do { apply(try await journal.reconcile()) } catch { journalError = error.localizedDescription }
            }
            uninstallOutcome = status
        }
    }

    func retainSelection(from previous: ScanSnapshot, to remaining: ScanSnapshot, prefix: String) {
        let surviving = Set(remaining.result.report.items.map(\.id))
        for key in Array(selections.keys) where key.hasPrefix(prefix) && key.hasSuffix(previous.sessionID.uuidString) {
            let replacement = String(key.dropLast(previous.sessionID.uuidString.count)) + remaining.sessionID.uuidString
            selections[replacement] = selections[key, default: []].intersection(surviving)
        }
    }

    func removeSelection(ids: Set<String>, prefix: String) {
        for key in Array(selections.keys) where key.hasPrefix(prefix) { selections[key]?.subtract(ids) }
    }

    func clearSelection(for prefix: String) {
        for key in Array(selections.keys) where key.hasPrefix(prefix) { selections[key] = [] }
    }

    func cancelPendingReview() {
        reviewGeneration = UUID()
        if scanTask != nil && !cleanupSession.isRunning { scanTask?.cancel() }
        duplicateChoice = nil; duplicateChoiceSource = nil
        showingReview = false; reviewPlan = nil
    }

    func ignore(_ item: CleanupItem) {
        clearDownloadPreview()
        ignored.insert(item.id); selected.remove(item.id); residueSelection.removeValue(forKey: item.id)
        UserDefaults.standard.set(Array(ignored), forKey: ignoreKey)
    }
    func unignore(_ path: String) {
        ignored.remove(path); UserDefaults.standard.set(Array(ignored), forKey: ignoreKey)
    }
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:\(anchor)") { NSWorkspace.shared.open(url) }
    }
}
