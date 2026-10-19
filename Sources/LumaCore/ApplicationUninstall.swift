import Foundation
import CoreServices
import Darwin

/// A negative/incomplete inventory never establishes exclusive data ownership.
public enum ApplicationUninstall {
    @TaskLocal static var fixtureInstallationRoots: [URL]?
    @TaskLocal static var fixtureRegisteredURLs: [URL]?

    public enum Multiplicity: Sendable { case exclusive, shared, unknown }

    public static func supportsBundle(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower != "com.apple" && !lower.hasPrefix("com.apple.") && lower != "app.luma.mac" && !lower.hasPrefix("app.luma.mac.")
            && !lower.hasPrefix("group.")
            && id.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$", options: .regularExpression) != nil
    }

    /// Ordinary native deletion rights only. No authorization helper or chmod.
    static func validateTrashRights(_ url: URL) throws {
        let pinned = try PinnedPath(url)
        guard pinned.value.st_uid == getuid() || pinned.value.st_uid == 0 else {
            throw LumaError.rejected("This application belongs to another user; ordinary Trash is unsupported.")
        }
        guard pinned.value.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0,
              FileManager.default.isDeletableFile(atPath: url.path) else {
            throw LumaError.rejected("macOS does not grant ordinary Trash rights for this application. Luma cannot request administrator privileges.")
        }
        try pinned.revalidate()
    }

    public static let scopeDescription = "Moves this bundle and verified exclusive caches, logs, preferences and saved state to Trash. Documents, support data and containers stay. Shared or unverified ownership keeps all related data."

    public static func multiplicity(app: ApplicationRecord, home: URL) throws -> Multiplicity {
        try NonMaterializingIO.perform {
            var matches: Set<Data> = []
            for root in fixtureInstallationRoots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
                do { _ = try Filesystem.attributes(root) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    if GeneratedDataScanner.failureState(error) == .missing { continue }
                    return .unknown
                }
                do {
                    try Filesystem.validatePath(root)
                    var failure: Error?
                    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                        options: [.skipsPackageDescendants], errorHandler: { _, error in failure = error; return false }) else { return .unknown }
                    var count = 0
                    for case let url as URL in walker {
                        try Task.checkCancellation()
                        count += 1
                        guard count <= 100_000 else { return .unknown }
                        let attributes = try Filesystem.attributes(url)
                        if attributes[.type] as? FileAttributeType == .typeSymbolicLink { return .unknown }
                        if url.pathExtension == "app", try Filesystem.applicationIdentifier(at: url).lowercased() == app.bundleID.lowercased() {
                            matches.insert(Data(url.exactStandardizedFileURL.path.utf8))
                        }
                    }
                    if failure != nil { return .unknown }
                } catch is CancellationError { throw CancellationError() }
                catch { return .unknown }
            }
            let registered: [URL]
            if let fixtureRegisteredURLs { registered = fixtureRegisteredURLs }
            else {
                var lookupError: Unmanaged<CFError>?
                let result = LSCopyApplicationURLsForBundleIdentifier(app.bundleID as CFString, &lookupError)?.takeRetainedValue()
                if let lookupError {
                    let error = lookupError.takeRetainedValue()
                    guard CFErrorGetDomain(error) == kCFErrorDomainOSStatus,
                          CFErrorGetCode(error) == Int(kLSApplicationNotFoundErr) else { return .unknown }
                    registered = []
                } else if let urls = result as? [URL] { registered = urls }
                else { return .unknown }
            }
            for url in registered {
                do {
                    try Filesystem.validatePath(url)
                    if try Filesystem.applicationIdentifier(at: url).lowercased() == app.bundleID.lowercased() {
                        matches.insert(Data(url.exactStandardizedFileURL.path.utf8))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { if GeneratedDataScanner.failureState(error) != .missing { return .unknown } }
            }
            let chosen = Data(app.url.exactStandardizedFileURL.path.utf8)
            if matches.contains(where: { $0 != chosen }) { return .shared }
            return matches == [chosen] ? .exclusive : .unknown
        }
    }

    public static func prepare(_ app: ApplicationRecord, home: URL, ignoredPaths: Set<String> = []) throws -> CleanupPlan {
        try NonMaterializingIO.perform {
            guard supportsBundle(app.bundleID) else { throw LumaError.rejected("This application is protected or has an unsupported identifier.") }
            guard try Filesystem.applicationIdentifier(at: app.url) == app.bundleID else { throw LumaError.rejected("The application changed. Refresh Applications and try again.") }
            guard ApplicationInventory.contains(app.url, home: home) else { throw LumaError.rejected("This application is outside the supported Applications inventory.") }
            try validateTrashRights(app.url)
            var items: [CleanupItem] = []
            var retained: [String] = []
            if ApplicationRelationships.supports(app.bundleID), try multiplicity(app: app, home: home) == .exclusive {
                let candidates = ApplicationRelationships.candidates(owner: app.bundleID, home: home).filter { [.generated, .settings].contains($0.category) }
                let roots = candidates.filter { candidate in !candidates.contains { $0.id != candidate.id && Filesystem.isWithin(candidate.url, root: $0.url) } }
                for relationship in roots {
                    do {
                        _ = try ApplicationRelationships.resolve(url: relationship.url, owner: app.bundleID, home: home)
                        try SafetyEngine.validateIgnores(relationship.url, ignoredPaths: ignoredPaths)
                        let item = try Filesystem.item(relationship.url, category: .related, safety: .review,
                            explanation: relationship.evidence, consequence: relationship.consequence,
                            rule: "application.exact-related", owner: app.bundleID)
                        // Optional roots are included whole, or retained whole. Never split around unsafe descendants.
                        try SafetyEngine(home: home, ignoredPaths: ignoredPaths).validate(item)
                        items.append(item)
                    } catch is CancellationError { throw CancellationError() }
                    catch { if GeneratedDataScanner.failureState(error) != .missing { retained.append("\(relationship.url.path): \(error.localizedDescription)") } }
                }
            } else {
                retained.append("Related data retained: exclusive ownership or exact data matching is unavailable.")
            }
            // Bundle last: all related-data checks can still verify its installation and helpers.
            items.append(try Filesystem.item(app.url, category: .applications, safety: .review,
                explanation: "Chosen installation with exact bundle identifier: \(app.bundleID).",
                consequence: "Uninstalls this application bundle.", rule: "application.exact-bundle", owner: app.bundleID))
            return try CleanupPlan(items: items, ignoredPaths: ignoredPaths, source: .applications, uninstallApplication: app, retainedApplicationData: retained)
        }
    }

    static func validate(_ item: CleanupItem, app: ApplicationRecord, home: URL, context: CleanupExecutionContext) throws {
        guard let paths = context.processPaths else { throw LumaError.rejected("Running processes could not be checked. Try again.") }
        guard !paths.contains(where: { Filesystem.isWithin(URL(fileURLWithPath: $0), root: app.url) }) else {
            throw LumaError.rejected("Quit the application and its helpers, then retry Uninstall.")
        }
        if item.ruleID == "application.exact-related" {
            guard try multiplicity(app: app, home: home) == .exclusive else {
                throw LumaError.rejected("Another installation exists or exclusive ownership is unavailable. Retry to remove only the chosen bundle.")
            }
            let relationship = try ApplicationRelationships.resolve(url: item.url, owner: app.bundleID, home: home)
            guard [.generated, .settings].contains(relationship.category) else { throw LumaError.rejected("Uninstall retains support data and containers.") }
        }
    }
}
