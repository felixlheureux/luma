import Foundation
import Darwin

public protocol Scanner: Sendable {
    var id: String { get }
    func scan() async throws -> ScanReport
}

public struct GeneratedDataScanner: Scanner {
    public let id = "generated-data"
    public let home: URL
    private let progress: @Sendable (ScanProgress) -> Void
    private let emit: ScanEmitter
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }, emit: @escaping ScanEmitter = { _ in }) {
        self.home = home; self.progress = progress; self.emit = emit
    }

    public func scan() async throws -> ScanReport {
        try NonMaterializingIO.perform { try scanLocal() }
    }

    private func scanLocal() throws -> ScanReport {
        let rules = try Rules.catalog().generated
        let started = Date()
        var report = ScanReport()
        for (index, rule) in rules.enumerated() {
            try Task.checkCancellation()
            let root = home.appendingPathComponent(rule.relativePath)
            progress(.init(completedRules: index, totalRules: rules.count, current: rule.title, entries: 0, bytes: report.items.reduce(0) { $0 + $1.bytes }))
            do {
                _ = try Filesystem.attributes(root)
                try Filesystem.validatePath(root)
                try VerifiedGeneratedOwner.validate(rule, home: home)
                let candidates: [URL]
                if rule.profileLeaves.isEmpty { candidates = [root] }
                else {
                    // Mozilla marks active local cache profiles hidden on macOS.
                    // Exact profile-name and cache-leaf checks still bound discovery.
                    let profiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                    guard profiles.count <= 500 else { throw LumaError.rejected("More than 500 local profiles; this location was excluded from the scan.") }
                    var leaves: [URL] = []
                    for profile in profiles.sorted(by: { $0.path < $1.path }) where rule.acceptsProfile(profile.lastPathComponent) {
                        try Task.checkCancellation()
                        do {
                            try Filesystem.validatePath(profile)
                            guard try profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                            leaves += rule.profileLeaves.map { profile.appendingPathComponent($0) }
                        } catch { appendFailure(error, rule: rule, url: profile, report: &report) }
                    }
                    candidates = leaves
                    if candidates.isEmpty { report.coverage.append(coverage(rule, url: root, state: .empty, detail: "No supported local cache profiles are present.")) }
                }
                for url in candidates {
                    try Task.checkCancellation()
                    let previousBytes = report.items.reduce(0) { $0 + $1.bytes }
                    do {
                        _ = try Filesystem.attributes(url)
                        let item = try report.generatedAccounting.inspect(url, rule: rule,
                            progress: { entries, bytes in
                                progress(.init(completedRules: index, totalRules: rules.count, current: rule.title, entries: entries, bytes: previousBytes + bytes))
                            })
                        if item.bytes > 0 { report.items.append(item); emit(.item(item)) }
                        let row = coverage(rule, url: url, state: item.bytes > 0 ? .found : .empty, bytes: item.bytes, detail: rule.consequence)
                        report.coverage.append(row); emit(.coverage(row))
                        report.visited += 1
                    } catch is CancellationError { throw CancellationError() }
                    catch { appendFailure(error, rule: rule, url: url, report: &report) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { appendFailure(error, rule: rule, url: root, report: &report) }
            progress(.init(completedRules: index + 1, totalRules: rules.count, current: rule.title, entries: 0, bytes: report.items.reduce(0) { $0 + $1.bytes }))
        }
        report.duration = Date().timeIntervalSince(started)
        report.items.sort { $0.bytes > $1.bytes }
        return report
    }

    private func coverage(_ rule: CleanupRule, url: URL, state: CoverageState, bytes: Int64 = 0, detail: String) -> ScanCoverage {
        ScanCoverage(ruleID: rule.id, title: rule.appName.map { "\($0) · \(rule.title)" } ?? rule.title, path: url.path.replacingOccurrences(of: home.path, with: "~", options: .anchored), category: rule.category, state: state, bytes: bytes, detail: detail)
    }

    private func appendFailure(_ error: Error, rule: CleanupRule, url: URL, report: inout ScanReport) {
        let failure = Self.failureState(error)
        let changedDuringInspection = failure == .missing && (try? Filesystem.attributes(url)) != nil
        let state: CoverageState = changedDuringInspection ? .skipped : failure
        let detail = state == .missing ? "This supported location is not present on this Mac." : changedDuringInspection ? "This location changed during inspection. Close its owning app and scan again." : error.localizedDescription
        var row = coverage(rule, url: url, state: state, detail: detail)
        row.accessCapability = (error as? FilesystemAccessError)?.capability
        report.coverage.append(row); emit(.coverage(row))
        if state != .missing {
            report.isComplete = false
            let message = "\(url.path.replacingOccurrences(of: home.path, with: "~", options: .anchored)): \(error.localizedDescription)"
            report.notices.append(message); emit(.notice(message))
        }
    }

    public static func failureState(_ error: Error) -> CoverageState {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            if [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return .missing }
            if error.code == NSFileReadNoPermissionError { return .blocked }
        }
        if error.domain == NSPOSIXErrorDomain {
            if error.code == 2 { return .missing }
            if error.code == 1 || error.code == 13 { return .blocked }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return failureState(underlying) }
        return .skipped
    }
}

public struct FolderScanner: Scanner {
    public let id = "folder"
    public let root: URL
    public let category: ItemCategory
    private let emit: ScanEmitter
    public init(root: URL, category: ItemCategory = .storage, emit: @escaping ScanEmitter = { _ in }) {
        self.root = root; self.category = category; self.emit = emit
    }
    public func scan() async throws -> ScanReport {
        try NonMaterializingIO.perform { try scanLocal() }
    }

    private func scanLocal() throws -> ScanReport {
        let started = Date()
        try Task.checkCancellation()
        try Filesystem.validatePath(root)
        var report = ScanReport()
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        guard children.count <= 100_000 else { throw LumaError.rejected("More than 100,000 immediate children. Choose a smaller folder.") }
        for (index, url) in children.enumerated() {
            try Task.checkCancellation()
            emit(.progress(.init("Sizing folder contents", current: url.lastPathComponent, completed: index, total: children.count)))
            do {
                let item = try Filesystem.item(url, category: category, safety: .userData,
                    explanation: "A file or folder in the location you chose. Its age or size does not make it unnecessary.",
                    consequence: "This is your data. Moving it to Trash may affect projects or applications that use it.", rule: "manual.folder-review",
                    progress: { entries, bytes in emit(.progress(.init("Sizing folder contents", current: url.lastPathComponent, completed: index, total: children.count, entries: entries, bytes: bytes))) })
                report.recordItem(item, emit: emit)
            } catch is CancellationError { throw CancellationError() }
            catch { report.recordFailure(error, at: url, category: category, rule: id, emit: emit) }
            report.visited += 1
        }
        report.duration = Date().timeIntervalSince(started)
        report.items.sort { $0.bytes > $1.bytes }
        return report
    }
}

public enum ApplicationScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [ApplicationRecord] {
        try inventory(home: home).applications
    }

    public static func inventory(home: URL = FileManager.default.homeDirectoryForCurrentUser, roots: [URL]? = nil,
                                 emit: @escaping ScanEmitter = { _ in }) throws -> ScanResult {
        return try NonMaterializingIO.perform {
            let started = Date()
            var apps: [ApplicationRecord] = []
            var report = ScanReport()
            for root in roots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
                try Task.checkCancellation()
                emit(.progress(.init("Discovering application metadata", current: root.lastPathComponent)))
                do {
                    try Filesystem.validatePath(root)
                    let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    guard children.count <= 10_000 else { throw LumaError.rejected("This Applications folder exceeds the inventory limit.") }
                    for url in children where url.pathExtension == "app" {
                        try Task.checkCancellation()
                        do {
                            try Filesystem.validatePath(url)
                            let identifier = try Filesystem.applicationIdentifier(at: url)
                            let metadata = try Filesystem.applicationMetadata(at: url)
                            let app = ApplicationRecord(url: url,
                                name: metadata["CFBundleDisplayName"] as? String ?? url.deletingPathExtension().lastPathComponent,
                                bundleID: identifier, version: metadata["CFBundleShortVersionString"] as? String ?? "Unknown", bytes: 0, sizeState: .pending, iconPNG: try ApplicationIcon.png(bundle: url, metadata: metadata))
                            apps.append(app); emit(.application(app))
                        } catch is CancellationError { throw CancellationError() }
                        catch { report.recordFailure(error, at: url, category: .applications, rule: "inventory", emit: emit) }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { report.recordFailure(error, at: root, category: .applications, rule: "inventory", emit: emit, missingIsExpected: true) }
            }
            // All metadata rows are visible before the first recursive size operation.
            let appCount = apps.count
            for index in apps.indices {
                try Task.checkCancellation()
                let app = apps[index]
                emit(.progress(.init("Measuring application bundles", current: app.name, completed: index, total: apps.count)))
                do {
                    let bytes = try Filesystem.inspect(app.url, progress: { entries, bytes in
                        emit(.progress(.init("Measuring application bundles", current: app.name, completed: index, total: appCount, entries: entries, bytes: bytes)))
                    }).0
                    apps[index] = ApplicationRecord(url: app.url, name: app.name, bundleID: app.bundleID, version: app.version, bytes: bytes, iconPNG: app.iconPNG)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    apps[index] = ApplicationRecord(url: app.url, name: app.name, bundleID: app.bundleID, version: app.version, bytes: 0, sizeState: .unavailable, iconPNG: app.iconPNG)
                    report.recordFailure(error, at: app.url, category: .applications, rule: "inventory.size", emit: emit)
                }
                emit(.application(apps[index])); report.visited += 1
            }
            report.duration = Date().timeIntervalSince(started)
            return ScanResult(report: report, applications: apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    public static func footprint(_ app: ApplicationRecord, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [CleanupItem] {
        try footprintReport(app, home: home).items
    }

    public static func footprintReport(_ app: ApplicationRecord, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                       emit: @escaping ScanEmitter = { _ in }) throws -> ScanReport {
        try ApplicationFootprintScanner.inspect(app, home: home, emit: emit).report
    }
}

public struct DuplicateScanner: Sendable {
    public let root: URL
    private let emit: ScanEmitter
    public init(root: URL, emit: @escaping ScanEmitter = { _ in }) { self.root = root; self.emit = emit }
    public func scan() throws -> ([DuplicateGroup], [String]) {
        let result = try scanResult()
        return (result.duplicates, result.report.notices)
    }
    public func scanResult() throws -> ScanResult { try scanResult(cache: nil) }

    func scanResult(cache: AnalysisIndexSession?) throws -> ScanResult {
        return try NonMaterializingIO.perform {
            let started = Date()
            try Task.checkCancellation()
            try Filesystem.validatePath(root)
            var report = ScanReport()
            var files: [Int64: [URL]] = [:]
            var identities: Set<String> = []
            let rootDevice = (try Filesystem.attributes(root)[.systemNumber] as? NSNumber)?.uint64Value
            var walkErrors: [(URL, Error)] = []
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in walkErrors.append((url, error)); return true }) else {
                throw LumaError.rejected("The selected folder could not be opened.")
            }
            var visited = 0
            emit(.progress(.init("Discovering candidate files", current: root.lastPathComponent)))
            for case let url as URL in walker {
                try Task.checkCancellation()
                visited += 1
                if visited % 128 == 0 { emit(.progress(.init("Discovering candidate files", current: url.lastPathComponent, entries: visited))) }
                guard visited <= 100_000 else { throw LumaError.rejected("More than 100,000 entries. Choose a smaller folder.") }
                do {
                    try FilesystemAccess.requireLocal(url)
                    let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey])
                    if v.isSymbolicLink == true || v.isUbiquitousItem == true || v.isPackage == true {
                        walker.skipDescendants()
                        report.recordFailure(LumaError.rejected("Packages, links and cloud-managed items are excluded from duplicate analysis."), at: url, category: .storage, rule: "duplicates.scope", emit: emit)
                        continue
                    }
                    let a = try Filesystem.attributes(url)
                    guard (a[.systemNumber] as? NSNumber)?.uint64Value == rootDevice else {
                        walker.skipDescendants()
                        report.recordFailure(LumaError.rejected("A different volume was excluded."), at: url, category: .storage, rule: "duplicates.volume", emit: emit)
                        continue
                    }
                    guard v.isRegularFile == true else {
                        if v.isDirectory != true {
                            report.recordFailure(LumaError.rejected("Unsupported filesystem object excluded."), at: url, category: .storage, rule: "duplicates.type", emit: emit)
                        }
                        continue
                    }
                    let size = (a[.size] as? NSNumber)?.int64Value ?? 0
                    let identity = "\(a[.systemNumber] ?? ""):\(a[.systemFileNumber] ?? "")"
                    guard size > 0, identities.insert(identity).inserted else { continue }
                    files[size, default: []].append(url)
                } catch is CancellationError { throw CancellationError() }
                catch { walker.skipDescendants(); report.recordFailure(error, at: url, category: .storage, rule: "duplicates.scan", emit: emit) }
            }
            for (url, error) in walkErrors { report.recordFailure(error, at: url, category: .storage, rule: "duplicates.walk", emit: emit) }
            var candidates: [CleanupItem] = []
            for urls in files.values where urls.count > 1 {
                for url in urls {
                    try Task.checkCancellation()
                    do {
                        candidates.append(try Filesystem.item(url, category: .storage, safety: .userData,
                            explanation: "A file in your chosen folder.", consequence: "This is your data.", rule: "manual.folder-review"))
                    } catch is CancellationError { throw CancellationError() }
                    catch { report.recordFailure(error, at: url, category: .storage, rule: "duplicates.scan", emit: emit) }
                }
            }
            let verified = try Self.verify(candidates, cache: cache, emit: emit)
            report.notices += verified.report.notices; report.coverage += verified.report.coverage
            report.isComplete = report.isComplete && verified.report.isComplete
            report.visited = visited; report.duration = Date().timeIntervalSince(started)
            return ScanResult(report: report, duplicates: verified.duplicates)
        }
    }


    /// Shared size/partial/full-SHA256 pipeline for an already bounded inventory.
    /// Hashes are tied to the original scan's identities, never filenames.
    public static func verify(_ candidates: [CleanupItem], emit: @escaping ScanEmitter = { _ in }) throws -> ScanResult {
        try verify(candidates, cache: nil, emit: emit)
    }

    static func verify(_ candidates: [CleanupItem], cache: AnalysisIndexSession?, emit: @escaping ScanEmitter = { _ in }) throws -> ScanResult {
        try NonMaterializingIO.perform {
            var report = ScanReport()
            var seen: Set<FileObjectID> = []
            let unique = candidates.sorted { Data($0.url.path.utf8).lexicographicallyPrecedes(Data($1.url.path.utf8)) }
                .filter { $0.bytes > 0 && seen.insert(FileObjectID($0.identity)).inserted }
            let sizes = Dictionary(grouping: unique, by: \.bytes)
            var groups: [DuplicateGroup] = []
            func current(_ item: CleanupItem) throws -> Data {
                let pin = try PinnedPath(item.url)
                guard pin.value.st_mode & S_IFMT == S_IFREG, item.safety == .userData,
                      try Filesystem.inspect(item.url).1 == item.identity else { throw LumaError.rejected("File changed while verifying duplicate content.") }
                try pin.revalidate(expected: item.identity.location)
                var after = stat()
                let fingerprint = AnalysisIndexSession.fingerprint(pin.value)
                guard fstat(pin.descriptor, &after) == 0, AnalysisIndexSession.fingerprint(after) == fingerprint else {
                    throw LumaError.rejected("File changed while verifying duplicate content.")
                }
                return fingerprint
            }
            for files in sizes.values where files.count > 1 {
                var partials: [String: [CleanupItem]] = [:]
                for item in files {
                    try Task.checkCancellation()
                    do {
                        let hash: String
                        if let saved = try cache?.cachedHash(item, partial: true) {
                            hash = saved
                            emit(.progress(.init("Revalidating saved content evidence", current: item.name)))
                        }
                        else {
                            let before = try current(item)
                            hash = try Filesystem.hash(item.url, partial: true, progress: { bytes in
                                emit(.progress(.init("Checking partial content", current: item.name, bytes: bytes)))
                            })
                            if let cache {
                                let after = AnalysisIndexSession.fingerprint(try PinnedPath(item.url).value)
                                cache.recordHash(hash, item: item, partial: true, before: before, after: after)
                            }
                        }
                        partials[hash, default: []].append(item)
                    } catch is CancellationError { throw CancellationError() }
                    catch { report.recordFailure(error, at: item.url, category: item.category, rule: "duplicates.hash", emit: emit) }
                }
                for matches in partials.values where matches.count > 1 {
                    var hashes: [String: [CleanupItem]] = [:]
                    for original in matches {
                        try Task.checkCancellation()
                        do {
                            let hash: String
                            if let saved = try cache?.cachedHash(original, partial: false) {
                                hash = saved
                                emit(.progress(.init("Revalidating saved content evidence", current: original.name)))
                            }
                            else {
                                let before = try current(original)
                                hash = try Filesystem.hash(original.url, progress: { bytes in
                                    emit(.progress(.init("Verifying full content", current: original.name, bytes: bytes)))
                                })
                                let after = try current(original)
                                cache?.recordHash(hash, item: original, partial: false, before: before, after: after)
                            }
                            let item = CleanupItem(url: original.url, bytes: original.bytes, category: original.category, safety: .userData,
                                explanation: cache == nil
                                    ? "Identical SHA-256 content verified against another independent file. Names, extensions and source URLs do not establish duplicates."
                                    : "Matching SHA-256 evidence with current file metadata and access checks. Saved hashes may be reused; content is checked again before cleanup.",
                                consequence: "Keep at least one independent copy. Each location may still be needed. Restore from Activity never overwrites a recreated file.",
                                ruleID: "duplicates.sha256", ownerBundleID: nil, identity: original.identity, scannedAt: original.scannedAt)
                            hashes[hash, default: []].append(item)
                        } catch is CancellationError { throw CancellationError() }
                        catch { report.recordFailure(error, at: original.url, category: original.category, rule: "duplicates.hash", emit: emit) }
                    }
                    for (hash, items) in hashes where items.count > 1 {
                        let group = DuplicateGroup(id: hash, items: items.sorted { Data($0.id.utf8).lexicographicallyPrecedes(Data($1.id.utf8)) })
                        groups.append(group); emit(.duplicate(group))
                    }
                }
            }
            return ScanResult(report: report, duplicates: groups.sorted { $0.recoverable == $1.recoverable ? $0.id < $1.id : $0.recoverable > $1.recoverable })
        }
    }
}
