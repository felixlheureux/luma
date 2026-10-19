import AppKit
import Foundation

public enum CleanupSource: String, Codable, Sendable {
    case generatedData, applications, applicationReset, leftovers, storage, duplicates, developerProjects, downloads
}

public struct CleanupExecutionContext: Sendable {
    public let ignoredPaths: Set<String>
    public let runningBundleIDs: Set<String>
    public let activity: CleanupActivity?
    public let processPaths: [String]?
    public init(ignoredPaths: Set<String> = [], runningBundleIDs: Set<String> = [], processPaths: [String]? = nil, activity: CleanupActivity? = nil) {
        self.ignoredPaths = ignoredPaths; self.runningBundleIDs = runningBundleIDs; self.processPaths = processPaths; self.activity = activity
    }

    @MainActor public static func current(ignoredPaths: Set<String> = [], checkingProcesses: Bool = true, checkingTools: Bool = true, checkingSimulators: Bool = false) async -> Self {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let paths = checkingProcesses ? await Task.detached(priority: .utility) { CleanupActivity.processPaths() }.value : nil
        let activity = checkingTools ? await Task.detached(priority: .utility) { CleanupActivity.collect(checkSimulators: checkingSimulators) }.value : nil
        return Self(ignoredPaths: ignoredPaths, runningBundleIDs: running, processPaths: paths, activity: activity)
    }
}

/// A reviewed, immutable selection. Creating a plan reads metadata but cannot
/// authorize a move: the journal preflights it and checks each mutation again.
public struct CleanupPlan: Identifiable, Sendable {
    public let id: UUID
    public let source: CleanupSource
    public let retainedApplicationData: [String]
    public let uninstallApplication: ApplicationRecord?
    public let resetApplication: ApplicationRecord?
    public let createdAt: Date
    public let items: [CleanupItem]
    public let authorizedRoots: [URL]
    public let ignoredPaths: Set<String>
    public let logicalBytes: Int64
    private let contributions: [Data: Int64]
    private let duplicateProofs: [Data: DuplicateProof]

    private struct DuplicateProof: Sendable {
        let digest: String
        let keeper: CleanupItem
    }

    public init(items: [CleanupItem], authorizedRoots: [URL] = [], ignoredPaths: Set<String> = [],
                duplicateGroups: [DuplicateGroup] = [], source: CleanupSource = .storage, resetApplication: ApplicationRecord? = nil, uninstallApplication: ApplicationRecord? = nil, retainedApplicationData: [String] = []) throws {
        if let app = uninstallApplication {
            guard source == .applications, items.last?.url == app.url, items.last?.ruleID == "application.exact-bundle",
                  items.dropLast().allSatisfy({ $0.ruleID == "application.exact-related" }),
                  items.allSatisfy({ $0.ownerBundleID == app.bundleID && ["application.exact-bundle", "application.exact-related"].contains($0.ruleID) }) else {
                throw LumaError.rejected("Uninstall requires the captured application and its exact related data.")
            }
        }
        self.retainedApplicationData = retainedApplicationData
        self.uninstallApplication = uninstallApplication
        if source == .developerProjects {
            guard items.allSatisfy({ ProjectRule(rawValue: $0.ruleID) != nil && $0.projectEvidence != nil }) else { throw LumaError.rejected("Project review requires manifest-backed project findings.") }
        }
        if source == .applicationReset {
            guard let app = resetApplication else { throw LumaError.rejected("Reset requires a verified application.") }
            try ApplicationReset.validateSelection(items, app: app)
        } else if resetApplication != nil { throw LumaError.rejected("Application reset requires a reset plan.") }
        self.resetApplication = resetApplication
        guard !items.isEmpty else { throw LumaError.rejected("Choose at least one item to review.") }
        guard items.allSatisfy({ $0.url.isFileURL && $0.bytes >= 0 }), authorizedRoots.allSatisfy(\.isFileURL) else {
            throw LumaError.rejected("The selection contains an invalid path or size.")
        }
        let paths = items.map { Data($0.url.exactStandardizedFileURL.path.utf8) }
        let selectedPaths = Set(paths)
        guard selectedPaths.count == items.count else { throw LumaError.rejected("The same path appears more than once. Review the selection again.") }
        for item in items {
            try Task.checkCancellation()
            var parent = item.url.exactStandardizedFileURL.exactDeletingLastPathComponent()
            while parent.path != "/" {
                guard !selectedPaths.contains(Data(parent.path.utf8)) else {
                    throw LumaError.rejected("A folder and one of its contents are both selected. Choose one level before reviewing.")
                }
                parent = parent.exactDeletingLastPathComponent()
            }
        }
        let objects = Set(items.map { FileObjectID($0.identity) })
        guard objects.count == items.count else {
            throw LumaError.rejected("Two selected paths refer to the same filesystem object. Review one at a time.")
        }

        var seenContents: Set<FileObjectID> = []
        var total: Int64 = 0
        var perItem: [Data: Int64] = [:]
        for item in items {
            try SafetyEngine.validateIgnores(item.url, ignoredPaths: ignoredPaths)
            var contribution: Int64 = 0
            let (bytes, identity) = try Filesystem.inspect(item.url, onFile: { object, bytes in
                guard seenContents.insert(object).inserted else { return }
                let (next, overflow) = contribution.addingReportingOverflow(bytes)
                guard bytes >= 0, !overflow else { throw LumaError.rejected("The selection size could not be verified.") }
                contribution = next
            }, applicationBundle: item.ruleID == "application.exact-bundle")
            guard identity == item.identity, identity.location == item.identity.location, bytes == item.bytes else {
                throw LumaError.rejected("Files changed since scanning. Scan again before reviewing their contents.")
            }
            let (next, overflow) = total.addingReportingOverflow(contribution)
            guard !overflow else { throw LumaError.rejected("The selection is too large to total safely.") }
            total = next; perItem[Data(item.id.utf8)] = contribution
        }

        var evidence: [Data: (member: CleanupItem, proof: DuplicateProof?)] = [:]
        var groupIDs: Set<String> = []
        for group in duplicateGroups where group.items.contains(where: { selectedPaths.contains(Data($0.url.exactStandardizedFileURL.path.utf8)) }) {
            guard group.items.count >= 2, group.id.utf8.count == 64,
                  group.id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  groupIDs.insert(group.id).inserted,
                  Set(group.items.map { Data($0.url.exactStandardizedFileURL.path.utf8) }).count == group.items.count,
                  Set(group.items.map { FileObjectID($0.identity) }).count == group.items.count,
                  group.items.allSatisfy({ $0.ruleID == "duplicates.sha256" && $0.safety == .userData }) else {
                throw LumaError.rejected("Duplicate evidence is incomplete or ambiguous. Run a new duplicate scan.")
            }
            let keeper = group.items.lazy.filter { member in
                !Self.isCovered(member.url, by: selectedPaths) && !seenContents.contains(FileObjectID(member.identity))
            }.min(by: { $0.url.path < $1.url.path })
            let proof = keeper.map { DuplicateProof(digest: group.id, keeper: $0) }
            for member in group.items {
                let path = Data(member.url.exactStandardizedFileURL.path.utf8)
                guard evidence[path] == nil else { throw LumaError.rejected("A file belongs to more than one duplicate group. Scan again.") }
                evidence[path] = (member, proof)
            }
        }
        var proofs: [Data: DuplicateProof] = [:]
        for item in items where item.ruleID == "duplicates.sha256" {
            guard let entry = evidence[Data(item.url.exactStandardizedFileURL.path.utf8)], entry.member == item else {
                throw LumaError.rejected("Duplicate removal requires its complete scanned group, not only a file or rule label.")
            }
            guard let proof = entry.proof else {
                throw LumaError.rejected("Keep at least one independent file outside the entire selection in each duplicate group.")
            }
            proofs[Data(item.id.utf8)] = proof
        }

        id = UUID(); createdAt = Date(); self.source = source; self.items = items
        self.authorizedRoots = authorizedRoots.map(\.exactStandardizedFileURL); self.ignoredPaths = ignoredPaths
        logicalBytes = total; contributions = perItem; duplicateProofs = proofs
    }

    /// Collect only observations used by this captured plan, once per validation boundary.
    @MainActor public func executionContext(ignoredPaths: Set<String> = []) async -> CleanupExecutionContext {
        let toolRules = Rules.generated.filter { rule in items.contains { $0.ruleID == rule.id } }
        return await .current(ignoredPaths: ignoredPaths,
            checkingProcesses: resetApplication != nil || uninstallApplication != nil,
            checkingTools: items.contains { ProjectRule(rawValue: $0.ruleID) != nil } || toolRules.contains { !$0.tools.isEmpty },
            checkingSimulators: toolRules.contains { $0.tools.contains(.simulator) })
    }

    private static func isCovered(_ url: URL, by selectedPaths: Set<Data>) -> Bool {
        var ancestor = url.exactStandardizedFileURL
        while true {
            if selectedPaths.contains(Data(ancestor.path.utf8)) { return true }
            if ancestor.path == "/" { return false }
            ancestor = ancestor.exactDeletingLastPathComponent()
        }
    }

    func accountedBytes(for item: CleanupItem) -> Int64 { contributions[Data(item.id.utf8)] ?? 0 }

    func preflight(home: URL, context: CleanupExecutionContext, onItem: (CleanupItem) -> Void = { _ in }) throws {
        let owners = try preflightOwners(home: home)
        for item in items {
            onItem(item)
            try validate(item, home: home, context: context, preflightOwners: owners)
        }
    }

    func preflightOwners(home: URL, progress: @escaping @Sendable (ScanPulse) -> Void = { _ in }) throws -> Set<String>? {
        let needsLeftovers = items.contains { $0.ruleID == "application.leftover.exact-identifier" }
        guard needsLeftovers || uninstallApplication != nil else { return nil }
        if !needsLeftovers, let app = uninstallApplication {
            return try ApplicationPresence.selectedInstallation(app.url, emit: { event in
                if case .progress(let pulse) = event { progress(pulse) }
            })
        }
        return try ApplicationPresence.bundleIdentifiers(home: home, emit: { event in
            if case .progress(let pulse) = event { progress(pulse) }
        })
    }

    func validate(_ item: CleanupItem, home: URL, context: CleanupExecutionContext, checkDuplicateContent: Bool = true,
                  preflightOwners: Set<String>? = nil, progress: @escaping @Sendable (ScanPulse) -> Void = { _ in }) throws {
        try Task.checkCancellation()
        if let app = resetApplication {
            try ApplicationReset.validateSelection(items, app: app)
            try ApplicationReset.validateActivity(app: app, home: home, context: context)
        }
        if let app = uninstallApplication { try ApplicationUninstall.validate(item, app: app, home: home, context: context) }
        let engine = SafetyEngine(home: home, ignoredPaths: ignoredPaths.union(context.ignoredPaths))
        try engine.validate(item, authorizedRoots: authorizedRoots, runningBundleIDs: context.runningBundleIDs, activity: context.activity,
            preflightOwners: uninstallApplication == nil ? preflightOwners : nil,
            preflightHelpers: try uninstallApplication.map { app in try preflightOwners ?? ApplicationPresence.selectedInstallation(app.url) }, progress: progress)
        guard item.ruleID == "duplicates.sha256", checkDuplicateContent else { return }
        guard let proof = duplicateProofs[Data(item.id.utf8)] else { throw LumaError.rejected("The duplicate group is missing. Scan again.") }
        try engine.validate(proof.keeper, authorizedRoots: authorizedRoots, runningBundleIDs: context.runningBundleIDs)
        for member in [proof.keeper, item] {
            let before = try Filesystem.attributes(member.url)
            guard before[.type] as? FileAttributeType == .typeRegular,
                  try Filesystem.hash(member.url) == proof.digest,
                  try Filesystem.inspect(member.url).1 == member.identity else {
                throw LumaError.rejected("A duplicate or its kept copy changed. Run a new duplicate scan before removing anything else.")
            }
        }
    }
}
