import Foundation

public enum SafetyLevel: String, Codable, Sendable, CaseIterable {
    case safe = "Generated data"
    case review = "Review first"
    case userData = "Your files"
}

public enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case caches = "App caches"
    case logs = "Application logs"
    case developer = "Developer files"
    case downloads = "Downloads"
    case applications = "Applications"
    case related = "Related app data"
    case storage = "Files & folders"
    public var symbol: String {
        switch self {
        case .caches: "externaldrive.badge.timemachine"
        case .logs: "doc.text"
        case .developer: "curlybraces"
        case .downloads: "arrow.down.circle"
        case .applications: "square.stack.3d.up"
        case .related: "link"
        case .storage: "folder"
        }
    }
}

public struct FileIdentity: Codable, Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modified: Date
    public let treeDigest: String
    public var location: FileLocation? = nil

    // Movement changes location, but not the recoverable object identity.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.size == rhs.size
            && lhs.modified == rhs.modified && lhs.treeDigest == rhs.treeDigest
    }
}

public struct CleanupItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let category: ItemCategory
    public let safety: SafetyLevel
    public let explanation: String
    public let consequence: String
    public let ruleID: String
    public let ownerBundleID: String?
    public let identity: FileIdentity
    public let scannedAt: Date
    public var observedContents: [String: Int64]? = nil
    public var projectEvidence: ProjectEvidence? = nil
    public var name: String {
        guard let rule = Rules.generated.first(where: { $0.id == ruleID }) else { return url.lastPathComponent }
        if url.lastPathComponent == "startupCache" { return rule.title.replacingOccurrences(of: "web caches", with: "startup cache") }
        return rule.title
    }
    public var displayPath: String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~", options: .anchored)
    }
}

public struct ScanReport: Sendable {
    public var items: [CleanupItem] = []
    public var notices: [String] = []
    public var visited = 0
    public var isComplete = true
    public var coverage: [ScanCoverage] = []
    public var duration: TimeInterval = 0
    public var generatedAccounting = GeneratedDataAccounting()
    public init() {}
}

public enum CoverageState: String, Codable, Sendable, CaseIterable {
    case found = "Found data", empty = "No data", missing = "Not present"
    case blocked = "Access needed", skipped = "Skipped"
}

public struct ScanCoverage: Identifiable, Sendable {
    public var id: String { ruleID + ":" + path }
    public let ruleID: String
    public let title: String
    public let path: String
    public let category: ItemCategory
    public let state: CoverageState
    public let bytes: Int64
    public let detail: String
    public var accessCapability: FilesystemCapability? = nil
    public init(ruleID: String, title: String, path: String, category: ItemCategory, state: CoverageState,
                bytes: Int64, detail: String, accessCapability: FilesystemCapability? = nil) {
        self.ruleID = ruleID; self.title = title; self.path = path; self.category = category
        self.state = state; self.bytes = bytes; self.detail = detail; self.accessCapability = accessCapability
    }
}

public struct ScanProgress: Sendable {
    public let completedRules: Int
    public let totalRules: Int
    public let current: String
    public let entries: Int
    public let bytes: Int64
}

public enum ApplicationSizeState: String, Sendable { case pending, available, unavailable }

public struct ApplicationRecord: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let bytes: Int64
    public var sizeState: ApplicationSizeState = .available
    public let iconPNG: Data?
    public init(url: URL, name: String, bundleID: String, version: String, bytes: Int64, sizeState: ApplicationSizeState = .available, iconPNG: Data? = nil) {
        self.url = url; self.name = name; self.bundleID = bundleID; self.version = version
        self.bytes = bytes; self.sizeState = sizeState; self.iconPNG = iconPNG
    }
}

extension ApplicationRecord {
    public func preservingIcon(from previous: ApplicationRecord?) -> ApplicationRecord {
        ApplicationRecord(url: url, name: name, bundleID: bundleID, version: version, bytes: bytes,
            sizeState: sizeState, iconPNG: iconPNG ?? (previous?.id == id && previous?.bundleID == bundleID ? previous?.iconPNG : nil))
    }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let items: [CleanupItem]
    public var recoverable: Int64 { Int64(max(0, items.count - 1)) * (items.first?.bytes ?? 0) }
}

public struct CleanupRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let original: URL
    public let trashed: URL
    public let bytes: Int64
    public var restored: Bool
    public var permanentlyRemoved: Bool? = nil
    public let identity: FileIdentity?
    public let planID: UUID?
    public let planSource: CleanupSource?
    /// Content counted once across the plan, while bytes remains this item's size.
    public let accountedBytes: Int64?
    public init(id: UUID = UUID(), date: Date = Date(), original: URL, trashed: URL, bytes: Int64, identity: FileIdentity? = nil,
                planID: UUID? = nil, planSource: CleanupSource? = nil, accountedBytes: Int64? = nil) {
        self.id = id; self.date = date; self.original = original
        self.trashed = trashed; self.bytes = bytes; self.identity = identity; restored = false
        self.planID = planID; self.planSource = planSource; self.accountedBytes = accountedBytes
    }
}

public enum LumaError: LocalizedError {
    case rejected(String)
    public var errorDescription: String? {
        switch self { case .rejected(let reason): reason }
    }
}

public func formatBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
}

public func formatMemory(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .memory)
}
