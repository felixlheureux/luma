import Foundation

public protocol Scanner: Sendable {
    var id: String { get }
    func scan() async throws -> ScanReport
}

public struct GeneratedDataScanner: Scanner {
    public let id = "generated-data"
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    public func scan() async throws -> ScanReport {
        var report = ScanReport()
        for rule in Rules.generated {
            try Task.checkCancellation()
            let url = home.appendingPathComponent(rule.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let item = try Filesystem.item(url, category: rule.category, safety: .safe, explanation: rule.explanation,
                                               consequence: rule.consequence, rule: rule.id, owner: rule.owner)
                if item.bytes > 0 { report.items.append(item) }
            } catch is CancellationError { throw CancellationError() }
            catch { report.notices.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            report.visited += 1
        }
        return report
    }
}

public struct FolderScanner: Scanner {
    public let id = "folder"
    public let root: URL
    public let category: ItemCategory
    public init(root: URL, category: ItemCategory = .storage) { self.root = root; self.category = category }
    public func scan() async throws -> ScanReport {
        try Filesystem.validatePath(root)
        var report = ScanReport()
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in children {
            try Task.checkCancellation()
            do {
                report.items.append(try Filesystem.item(url, category: category, safety: .userData,
                    explanation: "A file or folder in the location you chose. Its age or size does not make it unnecessary.",
                    consequence: "This is your data. Moving it to Trash may affect projects or applications that use it.", rule: "manual.folder-review"))
            } catch is CancellationError { throw CancellationError() }
            catch { report.notices.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            report.visited += 1
        }
        report.items.sort { $0.bytes > $1.bytes }
        return report
    }
}

public enum ApplicationScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [ApplicationRecord] {
        var apps: [ApplicationRecord] = []
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in children where url.pathExtension == "app" {
                try Task.checkCancellation()
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                // Inventory tolerates unreadable bundle internals, but uninstall never does.
                let bytes = (try? Filesystem.inspect(url).0) ?? 0
                apps.append(ApplicationRecord(url: url,
                    name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent,
                    bundleID: bundleID, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown", bytes: bytes))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func footprint(_ app: ApplicationRecord, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [CleanupItem] {
        var items = [try Filesystem.item(app.url, category: .applications, safety: .review,
            explanation: "Application bundle matched by its exact installation path and bundle identifier: \(app.bundleID).",
            consequence: "The application will be uninstalled. Its documents remain in place.", rule: "application.exact-bundle", owner: app.bundleID)]
        // Only exact identifiers. Shared containers and fuzzy name matches are deliberately excluded.
        for (path, generated) in [("Library/Caches/\(app.bundleID)", true),
                                  ("Library/Preferences/\(app.bundleID).plist", false),
                                  ("Library/Saved Application State/\(app.bundleID).savedState", false),
                                  ("Library/Application Support/\(app.bundleID)", false)] {
            let url = home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            items.append(try Filesystem.item(url, category: .related, safety: generated ? .safe : .review,
                explanation: "Exact bundle identifier match to \(app.bundleID). No fuzzy name matching was used.",
                consequence: generated ? "Generated data can be recreated." : "May contain preferences or app-owned documents. Review before selecting.",
                rule: "application.exact-related", owner: app.bundleID))
        }
        return items
    }
}

public struct DuplicateScanner: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func scan() throws -> ([DuplicateGroup], [String]) {
        try Filesystem.validatePath(root)
        var notices: [String] = []
        var files: [Int64: [URL]] = [:]
        var identities: Set<String> = []
        let rootDevice = (try Filesystem.attributes(root)[.systemNumber] as? NSNumber)?.uint64Value
        var walkError: String?
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in walkError = "\(url.lastPathComponent): \(error.localizedDescription)"; return true }) else {
            throw LumaError.rejected("The selected folder could not be opened.")
        }
        var visited = 0
        for case let url as URL in walker {
            try Task.checkCancellation()
            visited += 1
            guard visited <= 100_000 else { throw LumaError.rejected("More than 100,000 entries. Choose a smaller folder.") }
            do {
                let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey])
                if v.isSymbolicLink == true || v.isUbiquitousItem == true || v.isPackage == true { walker.skipDescendants(); continue }
                let a = try Filesystem.attributes(url)
                guard (a[.systemNumber] as? NSNumber)?.uint64Value == rootDevice else { walker.skipDescendants(); continue }
                guard v.isRegularFile == true else { continue }
                let size = (a[.size] as? NSNumber)?.int64Value ?? 0
                let identity = "\(a[.systemNumber] ?? ""):\(a[.systemFileNumber] ?? "")"
                guard size > 0, identities.insert(identity).inserted else { continue }
                files[size, default: []].append(url)
            } catch { notices.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if let walkError { notices.append(walkError) }
        var groups: [DuplicateGroup] = []
        for candidates in files.values where candidates.count > 1 {
            var partials: [String: [URL]] = [:]
            for url in candidates {
                try Task.checkCancellation()
                do { partials[try Filesystem.hash(url, partial: true), default: []].append(url) }
                catch is CancellationError { throw CancellationError() }
                catch { notices.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            for partial in partials.values where partial.count > 1 {
                var hashes: [String: [CleanupItem]] = [:]
                for url in partial {
                    try Task.checkCancellation()
                    do {
                        let item = try Filesystem.item(url, category: .storage, safety: .userData,
                            explanation: "Identical SHA-256 content verified against another file. Hard links are counted once.",
                            consequence: "Keep at least one copy. Each location may be referenced by a different project.", rule: "duplicates.sha256")
                        let hash = try Filesystem.hash(url)
                        guard try Filesystem.inspect(url).1 == item.identity else { throw LumaError.rejected("File changed while hashing.") }
                        hashes[hash, default: []].append(item)
                    } catch is CancellationError { throw CancellationError() }
                    catch { notices.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                for (hash, items) in hashes where items.count > 1 {
                    groups.append(DuplicateGroup(id: hash, items: items.sorted { $0.url.path < $1.url.path }))
                }
            }
        }
        return (groups.sorted { $0.recoverable > $1.recoverable }, notices)
    }
}
