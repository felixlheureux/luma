import Foundation
import CoreServices

/// Ownership discovery is metadata-only: no bundle sizing or file hashing.
public enum ApplicationPresence {
    public static func bundleIdentifiers(home: URL, roots: [URL]? = nil, matchingOwner: String? = nil, emit: ScanEmitter = { _ in }) throws -> Set<String> {
        return try NonMaterializingIO.perform {
            let roots = roots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
            var identifiers: Set<String> = []
            var visited = 0
            let embeddedLocations = ["Contents/PlugIns", "Contents/Extensions", "Contents/XPCServices", "Contents/Library/LoginItems", "Contents/Frameworks", "Contents/MacOS"]
            func register(_ bundleURL: URL, depth: Int = 0, belongsToOwner: Bool = false) throws {
                try Task.checkCancellation()
                let properties = try bundleURL.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
                guard properties.isAliasFile != true, properties.isSymbolicLink != true else { return }
                guard try Filesystem.attributes(bundleURL)[.type] as? FileAttributeType == .typeDirectory else { return }
                emit(.progress(.init("Checking installed owners and helpers", current: bundleURL.lastPathComponent)))
                let identifier = Bundle(url: bundleURL)?.bundleIdentifier ?? ""
                let matchesOwner = belongsToOwner || identifier.lowercased() == matchingOwner?.lowercased()
                if !identifier.isEmpty && (matchingOwner == nil || matchesOwner) { identifiers.insert(identifier.lowercased()) }
                guard depth < 3 else { return }
                for path in embeddedLocations {
                    try Task.checkCancellation()
                    let directory = bundleURL.appendingPathComponent(path)
                    let children: [URL]
                    do { try FilesystemAccess.requireLocal(directory); children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) }
                    catch {
                        if GeneratedDataScanner.failureState(error) == .missing { continue }
                        throw error
                    }
                    for child in children where ["app", "appex", "xpc", "framework", "bundle"].contains(child.pathExtension) {
                        guard (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                        try register(child, depth: depth + 1, belongsToOwner: matchesOwner)
                    }
                }
            }
            for root in roots {
                try Task.checkCancellation()
                emit(.progress(.init("Checking installed owners", current: root.lastPathComponent)))
                do { _ = try Filesystem.attributes(root) }
                catch {
                    if GeneratedDataScanner.failureState(error) == .missing { continue }
                    throw error
                }
                try Filesystem.validatePath(root)
                var readError: Error?
                guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in readError = error; return false }) else {
                    throw LumaError.rejected("The installed-app inventory could not be read. Leftover detection has stopped.")
                }
                for case let url as URL in walker {
                    try Task.checkCancellation()
                    visited += 1
                    guard visited <= 100_000 else { throw LumaError.rejected("Installed ownership inventory exceeded its entry limit. Leftover review is unavailable.") }
                    if visited % 128 == 0 { emit(.progress(.init("Checking installed owners", current: url.lastPathComponent, entries: visited))) }
                    if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                        walker.skipDescendants(); continue
                    }
                    do { try FilesystemAccess.requireLocal(url) }
                    catch { walker.skipDescendants(); throw error }
                    guard url.pathExtension == "app", (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                    try register(url)
                }
                if let readError { throw readError }
            }
            return identifiers
        }
    }

    public static func launchServicesContains(_ identifier: String) -> Bool {
        return (try? NonMaterializingIO.perform {
            guard let urls = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, nil)?.takeRetainedValue() as? [URL] else { return false }
            return urls.contains { url in
                do { try FilesystemAccess.requireLocal(url) }
                catch { return GeneratedDataScanner.failureState(error) != .missing }
                return Bundle(url: url)?.bundleIdentifier?.lowercased() == identifier.lowercased()
            }
        }) ?? true
    }

    public static func hasOwner(_ identifier: String, installed: Set<String>, lookup: @Sendable (String) -> Bool = launchServicesContains) -> Bool {
        let id = identifier.lowercased()
        // An app's helper namespace is grounds for exclusion, not proof of orphanhood.
        return installed.contains(id) || installed.contains(where: { id.hasPrefix($0 + ".") }) || lookup(identifier)
    }
}

public struct LeftoverLocation: Sendable {
    public let directory: String
    public let suffix: String
}

public struct KnownLeftoverPath: Sendable {
    public let relativePath: String
    public let owner: String
    public var explanation: String? = nil
    public var consequence: String? = nil
}

public struct LeftoverScanner: Scanner {
    public let id = "application-leftovers"
    public let home: URL
    private let applicationRoots: [URL]?
    private let lookup: @Sendable (String) -> Bool
    private let emit: ScanEmitter
    public static let knownPaths = ApplicationRelationships.knownPaths
    public static let locations = ApplicationRelationships.locations

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, applicationRoots: [URL]? = nil,
                lookup: @escaping @Sendable (String) -> Bool = ApplicationPresence.launchServicesContains,
                emit: @escaping ScanEmitter = { _ in }) {
        self.home = home; self.applicationRoots = applicationRoots; self.lookup = lookup; self.emit = emit
    }

    public static func isSupportedIdentifier(_ id: String) -> Bool { ApplicationRelationships.supports(id) }

    public static func matches(_ item: CleanupItem, home: URL) -> Bool {
        guard item.ruleID == "application.leftover.exact-identifier", item.safety == .review,
              let owner = item.ownerBundleID else { return false }
        return (try? ApplicationRelationships.resolve(url: item.url, owner: owner, home: home)) != nil
    }

    public func scan() async throws -> ScanReport {
        try NonMaterializingIO.perform { try scanLocal() }
    }

    private func scanLocal() throws -> ScanReport {
        _ = try Rules.catalog()
        let started = Date()
        let installed = try ApplicationPresence.bundleIdentifiers(home: home, roots: applicationRoots, emit: emit)
        var report = ScanReport()
        var ownerCache: [String: Bool] = [:]
        for location in Self.locations {
            try Task.checkCancellation()
            let directory = home.appendingPathComponent(location.directory)
            emit(.progress(.init("Checking potential leftovers", current: location.directory)))
            let children: [URL]
            do {
                try Filesystem.validatePath(directory)
                children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch is CancellationError { throw CancellationError() }
            catch { report.recordFailure(error, at: directory, category: .related, rule: id, emit: emit, missingIsExpected: true); continue }
            guard children.count <= 100_000 else { throw LumaError.rejected("Too many entries in a leftover location. Choose a narrower workflow.") }
            for url in children {
                try Task.checkCancellation()
                let name = url.lastPathComponent
                guard location.suffix.isEmpty || name.hasSuffix(location.suffix) else { continue }
                let owner = location.suffix.isEmpty ? name : String(name.dropLast(location.suffix.count))
                guard Self.isSupportedIdentifier(owner) else { continue }
                let installedOwner = ownerCache[owner] ?? ApplicationPresence.hasOwner(owner, installed: installed, lookup: lookup)
                ownerCache[owner] = installedOwner
                guard !installedOwner else { continue }
                do {
                    let relationship = try ApplicationRelationships.resolve(url: url, owner: owner, home: home)
                    let item = try Filesystem.item(url, category: .related, safety: .review,
                        explanation: relationship.evidence + " No installed owner or helper was found; this is a review candidate.",
                        consequence: relationship.consequence,
                        rule: "application.leftover.exact-identifier", owner: owner,
                        progress: { entries, bytes in emit(.progress(.init("Inspecting potential leftover", current: url.lastPathComponent, entries: entries, bytes: bytes))) })
                    if item.bytes > 0 { report.recordItem(item, emit: emit) }
                } catch is CancellationError { throw CancellationError() }
                catch { report.recordFailure(error, at: url, category: .related, rule: id, emit: emit) }
                report.visited += 1
            }
        }
        let namedPaths = ApplicationRelationships.namedPaths
        for path in namedPaths where Self.isSupportedIdentifier(path.owner) {
            try Task.checkCancellation()
            let url = home.appendingPathComponent(path.relativePath)
            guard !report.items.contains(where: { $0.url == url }),
                  !ApplicationPresence.hasOwner(path.owner, installed: installed, lookup: lookup) else { continue }
            do {
                let relationship = try ApplicationRelationships.resolve(url: url, owner: path.owner, home: home)
                let item = try Filesystem.item(url, category: .related, safety: .review,
                    explanation: relationship.evidence + " No installed owner or helper was found; this is a review candidate.",
                    consequence: relationship.consequence,
                    rule: "application.leftover.exact-identifier", owner: path.owner,
                    progress: { entries, bytes in emit(.progress(.init("Inspecting known app data", current: url.lastPathComponent, entries: entries, bytes: bytes))) })
                if item.bytes > 0 { report.recordItem(item, emit: emit) }
            } catch is CancellationError { throw CancellationError() }
            catch { report.recordFailure(error, at: url, category: .related, rule: id, emit: emit, missingIsExpected: true) }
        }
        report.items = report.items.filter { item in
            !report.items.contains { $0.id != item.id && Filesystem.isWithin(item.url, root: $0.url) }
        }
        report.items.sort { $0.bytes > $1.bytes }
        report.duration = Date().timeIntervalSince(started)
        return report
    }
}
