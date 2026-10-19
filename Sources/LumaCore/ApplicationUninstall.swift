import Foundation
import CoreServices

/// A negative/incomplete inventory never establishes exclusive data ownership.
public enum ApplicationUninstall {
    @TaskLocal static var fixtureInstallationRoots: [URL]?
    @TaskLocal static var fixtureRegisteredURLs: [URL]?

    public enum Multiplicity: Sendable { case exclusive, shared, unknown }

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
            guard ApplicationRelationships.supports(app.bundleID) else { throw LumaError.rejected("This application is protected or has an unsupported identifier.") }
            guard try Filesystem.applicationIdentifier(at: app.url) == app.bundleID else { throw LumaError.rejected("The application changed. Refresh Applications and try again.") }
            var items: [CleanupItem] = []
            if try multiplicity(app: app, home: home) == .exclusive {
                let candidates = ApplicationRelationships.candidates(owner: app.bundleID, home: home).filter { [.generated, .settings].contains($0.category) }
                let roots = candidates.filter { candidate in !candidates.contains { $0.id != candidate.id && Filesystem.isWithin(candidate.url, root: $0.url) } }
                for relationship in roots {
                    do {
                        _ = try ApplicationRelationships.resolve(url: relationship.url, owner: app.bundleID, home: home)
                        items.append(try Filesystem.item(relationship.url, category: .related, safety: .review,
                            explanation: relationship.evidence, consequence: relationship.consequence,
                            rule: "application.exact-related", owner: app.bundleID))
                    } catch is CancellationError { throw CancellationError() }
                    catch { if GeneratedDataScanner.failureState(error) != .missing { throw error } }
                }
            }
            // Bundle last: all related-data checks can still verify its installation and helpers.
            items.append(try Filesystem.item(app.url, category: .applications, safety: .review,
                explanation: "Chosen installation with exact bundle identifier: \(app.bundleID).",
                consequence: "Uninstalls this application bundle.", rule: "application.exact-bundle", owner: app.bundleID))
            return try CleanupPlan(items: items, ignoredPaths: ignoredPaths, source: .applications, uninstallApplication: app)
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
