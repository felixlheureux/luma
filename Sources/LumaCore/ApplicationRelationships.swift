import Foundation

public enum FootprintCategory: String, Sendable, CaseIterable {
    case bundle = "Application bundle"
    case generated = "Generated data"
    case settings = "Settings and state"
    case userData = "Potential app and user data"
}

public struct ApplicationRelationship: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let owner: String
    public let category: FootprintCategory
    public let evidence: String
    public var consequence: String {
        switch category {
        case .bundle: "Uninstalls this application bundle. Related data is a separate choice."
        case .generated: "Caches may need to be rebuilt or downloaded. Logs may contain diagnostics worth keeping."
        case .settings: "Removes preferences or saved state. Custom settings and session recovery may be lost."
        case .userData: "May contain documents, offline content, extensions or sessions. Ownership does not make this data disposable."
        }
    }
}

/// The same exact-path policy is used for discovery and final mutation checks.
/// No folder-name similarity or shared group entitlement grants removal authority.
public enum ApplicationRelationships {
    public static let knownPaths: [KnownLeftoverPath] = [
        .init(relativePath: "Library/Application Support/Spotify", owner: "com.spotify.client"),
        .init(relativePath: "Library/Application Support/Slack", owner: "com.tinyspeck.slackmacgap"),
        .init(relativePath: "Library/Application Support/discord", owner: "com.hnc.Discord"),
        .init(relativePath: "Library/Application Support/obsidian", owner: "md.obsidian"),
        .init(relativePath: "Library/Application Support/Code", owner: "com.microsoft.VSCode")
    ]
    public static let locations: [LeftoverLocation] = [
        .init(directory: "Library/Caches", suffix: ""),
        .init(directory: "Library/Application Support", suffix: ""),
        .init(directory: "Library/Preferences", suffix: ".plist"),
        .init(directory: "Library/Saved Application State", suffix: ".savedState"),
        .init(directory: "Library/Logs", suffix: ""),
        .init(directory: "Library/Containers", suffix: "")
    ]
    public static var namedPaths: [KnownLeftoverPath] {
        knownPaths + Rules.generated.compactMap { rule in
            rule.profileLeaves.isEmpty && rule.requiredApplication == nil
                ? rule.owner.map { KnownLeftoverPath(relativePath: rule.relativePath, owner: $0) } : nil
        }
    }
    public static func supports(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard !lower.hasPrefix("com.apple."), lower != "app.luma.mac", !lower.hasPrefix("app.luma.mac."), !lower.hasPrefix("group.") else { return false }
        return knownPaths.contains { $0.owner == id }
            || id.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$", options: .regularExpression) != nil
    }
    public static func candidates(owner: String, home: URL) -> [ApplicationRelationship] {
        guard supports(owner) else { return [] }
        let exact = locations.map { location in
            ApplicationRelationship(url: home.appendingPathComponent(location.directory).appendingPathComponent(owner + location.suffix),
                owner: owner, category: category(location.directory), evidence: "Exact bundle identifier: \(owner).")
        }
        let named = namedPaths.filter { $0.owner == owner }.map { path in
            ApplicationRelationship(url: home.appendingPathComponent(path.relativePath), owner: owner,
                category: category(path.relativePath), evidence: "Explicit ownership mapping: \(path.relativePath) → \(owner).")
        }
        var seen: Set<Data> = []
        return (named + exact).filter { relationship in
            // Conflicting explicit mappings, including overlapping roots, are excluded.
            isUnambiguous(url: relationship.url, owner: owner, home: home, mappings: namedPaths) && seen.insert(Data(relationship.url.path.utf8)).inserted
        }.sorted { $0.url.path.utf8.lexicographicallyPrecedes($1.url.path.utf8) }
    }
    static func isUnambiguous(url: URL, owner: String, home: URL, mappings: [KnownLeftoverPath]) -> Bool {
        !mappings.contains { mapping in
            mapping.owner.lowercased() != owner.lowercased()
                && (Filesystem.isWithin(url, root: home.appendingPathComponent(mapping.relativePath))
                    || Filesystem.isWithin(home.appendingPathComponent(mapping.relativePath), root: url))
        }
    }
    private static func category(_ path: String) -> FootprintCategory {
        if path.hasPrefix("Library/Caches") || path.hasPrefix("Library/Logs") { return .generated }
        if path.hasPrefix("Library/Preferences") || path.hasPrefix("Library/Saved Application State") { return .settings }
        return .userData
    }
    public static func resolve(url: URL, owner: String, home: URL) throws -> ApplicationRelationship {
        guard let relationship = candidates(owner: owner, home: home).first(where: { Filesystem.samePath($0.url, url) }) else {
            throw LumaError.rejected("No unambiguous exact ownership relationship matches this path.")
        }
        if Filesystem.samePath(url.exactDeletingLastPathComponent(), home.appendingPathComponent("Library/Containers")) {
            _ = try Filesystem.attributes(url)
            let data: Data
            do { data = try Filesystem.readMetadata(url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")) }
            catch is CancellationError { throw CancellationError() }
            catch { throw LumaError.rejected("Container ownership metadata is unavailable: " + error.localizedDescription) }
            let metadata = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard metadata?["MCMMetadataIdentifier"] as? String == owner else {
                throw LumaError.rejected("Container ownership metadata is unavailable or has changed.")
            }
        }
        return relationship
    }
}

public struct FootprintEntry: Identifiable, Sendable {
    public var id: String { relationship.id }
    public let relationship: ApplicationRelationship
    public let state: CoverageState
    public let item: CleanupItem?
    public let detail: String
    /// Unknown/denied sizes remain nil; absent paths also have no measured item.
    public var bytes: Int64? { item?.bytes }
}

public struct ApplicationFootprint: Sendable {
    public var entries: [FootprintEntry] = []
    public var accounting = GeneratedDataAccounting()
    public var items: [CleanupItem] { entries.compactMap(\.item) }
    public var inspectedBytes: Int64 { accounting.bytes(for: items) }
    public var isComplete: Bool { entries.allSatisfy { [.found, .empty].contains($0.state) || ($0.state == .missing && $0.relationship.category != .bundle) } }
    /// Stable category order allocates cross-category hard links exactly once.
    public func bytes(in category: FootprintCategory) -> Int64 {
        var preceding: [CleanupItem] = []
        for current in FootprintCategory.allCases {
            let next = entries.filter { $0.relationship.category == current }.compactMap(\.item)
            if current == category { return accounting.bytes(for: preceding + next) - accounting.bytes(for: preceding) }
            preceding += next
        }
        return 0
    }
}

public enum ApplicationFootprintScanner {
    public static func inspect(_ app: ApplicationRecord, home: URL, emit: @escaping ScanEmitter = { _ in },
                               checkAccess: @Sendable (URL) throws -> Void = { _ in }) throws -> ScanResult {
        try NonMaterializingIO.perform {
            let started = Date()
            var footprint = ApplicationFootprint()
            var report = ScanReport()
            let bundle = ApplicationRelationship(url: app.url, owner: app.bundleID, category: .bundle,
                evidence: "Installation path and exact bundle identifier: \(app.bundleID).")
            let candidates = [bundle] + ApplicationRelationships.candidates(owner: app.bundleID, home: home)
            // Present only disjoint roots. Nested mappings are covered by the parent.
            let roots = candidates.filter { candidate in
                !candidates.contains { $0.id != candidate.id && Filesystem.isWithin(candidate.url, root: $0.url) }
            }
            for (index, relationship) in roots.enumerated() {
                try Task.checkCancellation()
                let url = relationship.url
                let ruleID = relationship.category == .bundle ? "application.exact-bundle" : "application.exact-related"
                emit(.progress(.init("Inspecting app relationships", current: url.lastPathComponent, completed: index, total: roots.count)))
                do {
                    try checkAccess(url)
                    if relationship.category == .bundle {
                        guard try Filesystem.applicationIdentifier(at: url) == app.bundleID else { throw LumaError.rejected("Application identity changed. Scan again.") }
                    } else {
                        _ = try ApplicationRelationships.resolve(url: url, owner: app.bundleID, home: home)
                    }
                    let rule = CleanupRule(id: ruleID, relativePath: "", category: relationship.category == .bundle ? .applications : .related,
                        explanation: relationship.evidence, consequence: relationship.consequence, owner: app.bundleID, safety: .review)
                    let item = try footprint.accounting.inspect(url, rule: rule, progress: { entries, bytes in
                        emit(.progress(.init("Measuring app data", current: url.lastPathComponent, entries: entries, bytes: bytes)))
                    })
                    footprint.entries.append(.init(relationship: relationship, state: item.bytes > 0 ? .found : .empty, item: item, detail: relationship.evidence))
                    report.recordItem(item, emit: emit)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    let state = GeneratedDataScanner.failureState(error)
                    footprint.entries.append(.init(relationship: relationship, state: state, item: nil, detail: error.localizedDescription))
                    report.recordFailure(error, at: url, category: .related, rule: ruleID, emit: emit, missingIsExpected: relationship.category != .bundle)
                }
                report.visited += 1
            }
            report.duration = Date().timeIntervalSince(started)
            report.generatedAccounting = footprint.accounting
            return ScanResult(report: report, applicationFootprint: footprint)
        }
    }
}
