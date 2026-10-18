import Foundation

public struct CleanupRule: Sendable {
    public let id: String
    public let relativePath: String
    public let category: ItemCategory
    public let explanation: String
    public let consequence: String
    public let owner: String?
    public var title: String { name ?? URL(fileURLWithPath: relativePath).lastPathComponent }
    public var name: String? = nil
    public var profileLeaves: [String] = []
    public var chromiumProfiles = false
    public var safety: SafetyLevel = .safe
    public var tools: Set<CleanupTool> = []
    public var appName: String? = nil
    public var requiredApplication: GeneratedOwnerRequirement? = nil

    public var regeneration: String = ""
    public var provenance: [String] = []
    public var reviewedOn: String = ""

    public func matches(_ url: URL, home: URL) -> Bool {
        let root = home.appendingPathComponent(relativePath).exactStandardizedFileURL
        let candidate = url.exactStandardizedFileURL
        if profileLeaves.isEmpty { return Filesystem.samePath(candidate, root) }
        guard Filesystem.samePath(candidate.exactDeletingLastPathComponent().exactDeletingLastPathComponent(), root),
              profileLeaves.contains(candidate.lastPathComponent) else { return false }
        return acceptsProfile(candidate.exactDeletingLastPathComponent().lastPathComponent)
    }

    public func acceptsProfile(_ name: String) -> Bool {
        if chromiumProfiles { return name == "Default" || name.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil }
        return name.count <= 255 && name.range(of: "^[A-Za-z0-9]{8,}\\..+$", options: .regularExpression) != nil && !name.contains("/")
    }
}

public enum Rules {
    private static let bundled: Result<RuleCatalog, RuleCatalogError> = {
        do { return .success(try RuleLoader.bundled()) }
        catch let error as RuleCatalogError { return .failure(error) }
        catch { return .failure(RuleCatalogError(error.localizedDescription)) }
    }()
    // Tests can exercise alternate validated catalogs without a production override.
    @TaskLocal static var catalogOverride: Result<RuleCatalog, RuleCatalogError>?
    public static func catalog() throws -> RuleCatalog { try (catalogOverride ?? bundled).get() }
    /// Read-only display compatibility. Scanners and mutation entry points require catalog().
    public static var generated: [CleanupRule] { (try? catalog().generated) ?? [] }
}
