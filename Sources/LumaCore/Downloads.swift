import Foundation
import Darwin

public enum DownloadKind: String, Sendable, CaseIterable {
    case diskImage = "Disk images", package = "Installer packages", archive = "Archives", other = "Other files", incomplete = "Possible incomplete downloads"
    public static func classify(_ url: URL) -> Self {
        let ext = url.pathExtension.lowercased()
        if ["download", "crdownload", "part", "partial", "filepart"].contains(ext) { return .incomplete }
        if ["dmg", "iso", "img", "sparseimage", "sparsebundle"].contains(ext) { return .diskImage }
        if ["pkg", "mpkg"].contains(ext) { return .package }
        if ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "tgz", "tbz", "zst"].contains(ext) { return .archive }
        return .other
    }
}

public enum DownloadAge: String, CaseIterable, Sendable {
    case any = "Any age", month = "Older than 30 days", year = "Older than a year"
    var days: Int? { switch self { case .any: nil; case .month: 30; case .year: 365 } }
}

public struct DownloadFilter: Sendable {
    public var kind: DownloadKind?
    public var minimumBytes: Int64
    public var age: DownloadAge
    public init(kind: DownloadKind? = nil, minimumBytes: Int64 = 0, age: DownloadAge = .any) {
        self.kind = kind; self.minimumBytes = minimumBytes; self.age = age
    }
    public func matches(_ file: DownloadFile, now: Date = Date()) -> Bool {
        (kind == nil || kind == file.kind)
            && (minimumBytes == 0 || (file.bytes.map { $0 >= minimumBytes } ?? false))
            && (age.days.map { days in file.modified.map { $0 < now.addingTimeInterval(-Double(days) * 86_400) } ?? false } ?? true)
    }
}

public struct DownloadFile: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let kind: DownloadKind
    public let bytes: Int64?
    public let modified: Date?
    public let created: Date?
    /// Optional recorded file metadata, not a trusted URL or browser-history row.
    public let sources: [String]
    public var item: CleanupItem?
    public let issue: String?
}

public struct DownloadsInventory: Sendable {
    public let root: URL
    public var files: [DownloadFile]
    public var duplicates: [DuplicateGroup]
    public var report: ScanReport
    public func files(matching filter: DownloadFilter, now: Date = Date()) -> [DownloadFile] {
        files.filter { filter.matches($0, now: now) }
    }
    /// Types partition the inventory; large/old/duplicate views overlap and must
    /// not be added to these totals. Unknown/excluded sizes contribute no bytes.
    public func bytes(kind: DownloadKind? = nil) -> Int64 {
        files.filter { kind == nil || kind == $0.kind }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
    public func reviewPlan(ids: Set<String>, authorizedRoots: [URL], ignoredPaths: Set<String> = [], home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> CleanupPlan {
        let items = report.items.filter { ids.contains($0.id) }
        let scope = SafetyEngine(home: home, ignoredPaths: ignoredPaths)
        guard !ids.isEmpty, items.count == ids.count,
              items.allSatisfy({ Date().timeIntervalSince($0.scannedAt) < 1_800 && scope.permitsManualSelection(at: $0.url, authorizedRoots: authorizedRoots) }) else {
            throw LumaError.rejected("Choose current local files inside your authorized home-folder scope. Scan again after changing ignore rules.")
        }
        return try CleanupPlan(items: items, authorizedRoots: authorizedRoots, ignoredPaths: ignoredPaths, duplicateGroups: duplicates, source: .downloads)
    }
    public func keeperSelection(groupID: String, keeperID: String, ignoredPaths: Set<String> = []) throws -> Set<String> {
        guard let group = duplicates.first(where: { $0.id == groupID }), group.items.contains(where: { $0.id == keeperID }),
              group.items.allSatisfy({ member in !ignoredPaths.contains { Filesystem.isWithin(member.url, root: URL(fileURLWithPath: $0)) } }) else {
            throw LumaError.rejected("Choose a visible copy in the completed duplicate group. Scan again after changing ignore rules.")
        }
        return Set(group.items.filter { $0.id != keeperID }.map(\.id))
    }
}

public enum DownloadsScanner {
    public static func scan(root: URL, ignoredPaths: Set<String> = [], limit: Int = 50_000, emit: @escaping ScanEmitter = { _ in }) throws -> DownloadsInventory {
        try NonMaterializingIO.perform {
            let start = Date()
            let rootPin = try PinnedPath(root)
            guard rootPin.value.st_mode & S_IFMT == S_IFDIR else { throw LumaError.rejected("Choose a Downloads folder to inspect.") }
            guard DownloadKind.classify(root) != .incomplete,
                  try root.resourceValues(forKeys: [.isPackageKey]).isPackage != true else {
                throw LumaError.rejected("Choose the containing Downloads folder, not a package or incomplete download.")
            }
            var files: [DownloadFile] = []
            var report = ScanReport()
            var visited = 0
            func ignored(_ url: URL) -> Bool { ignoredPaths.contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) } }
            func excluded(_ url: URL, _ error: Error, kind: DownloadKind, bytes: Int64? = nil, modified: Date? = nil, created: Date? = nil) {
                files.removeAll { Data($0.url.path.utf8) == Data(url.path.utf8) }
                files.append(.init(url: url, kind: kind, bytes: bytes, modified: modified, created: created, sources: [], item: nil, issue: error.localizedDescription))
                report.recordFailure(error, at: url, category: .downloads, rule: "downloads.local-files", emit: emit)
            }
            func visit(_ url: URL, depth: Int) throws {
                try Task.checkCancellation()
                guard !ignored(url) else {
                    report.recordFailure(LumaError.rejected("Ignored location; not inspected."), at: url, category: .downloads, rule: "downloads.ignored", emit: emit); return
                }
                visited += 1
                guard visited <= limit, depth <= 32 else { throw LumaError.rejected("Downloads inspection limit reached. Choose a narrower folder.") }
                let kind = DownloadKind.classify(url)
                do {
                    let pin = try PinnedPath(url)
                    guard pin.value.st_dev == rootPin.value.st_dev, pin.value.st_uid == getuid() else { throw LumaError.rejected("Another owner or volume is excluded.") }
                    let values = try url.resourceValues(forKeys: [.isPackageKey, .creationDateKey, .isHiddenKey])
                    let modified = Date(timeIntervalSince1970: Double(pin.value.st_mtimespec.tv_sec) + Double(pin.value.st_mtimespec.tv_nsec) / 1e9)
                    let directory = pin.value.st_mode & S_IFMT == S_IFDIR
                    if kind == .incomplete {
                        excluded(url, LumaError.rejected("Name suggests an incomplete download. Completion and app activity are unknown; kept out of preview, duplicates and cleanup."), kind: kind, bytes: directory ? nil : pin.value.st_size, modified: modified, created: values.creationDate)
                    } else if values.isHidden == true || url.lastPathComponent.hasPrefix(".") {
                        throw LumaError.rejected("Hidden content is excluded from Downloads review.")
                    } else if directory {
                        guard values.isPackage != true else { throw LumaError.rejected("Application and package directories are kept opaque. Review them in Storage or Finder.") }
                        let names = try PinnedPath.names(in: pin.descriptor, limit: max(0, limit - visited))
                        for name in names { try visit(url.exactAppendingPathComponent(name), depth: depth + 1) }
                    } else {
                        guard pin.value.st_mode & S_IFMT == S_IFREG, pin.value.st_nlink == 1 else { throw LumaError.rejected("Linked/shared files and unsupported objects are excluded.") }
                        let item = try Filesystem.item(url, category: .downloads, safety: .userData,
                            explanation: "An actual local file in the Downloads folder you chose. Type, age, source metadata and installed apps do not establish that it is disposable.",
                            consequence: "This is your downloaded data. You may need this exact version or an offline copy. Move only files you no longer need; Restore through Activity never overwrites recreated files.", rule: "manual.folder-review")
                        let sources = DownloadMetadata.sources(from: pin)
                        try pin.revalidate(expected: item.identity.location)
                        files.append(.init(url: url, kind: kind, bytes: item.bytes, modified: modified, created: values.creationDate, sources: sources, item: item, issue: nil))
                        emit(.item(item))
                    }
                    try pin.revalidate()
                } catch is CancellationError { throw CancellationError() }
                catch { excluded(url, error, kind: kind) }
                if visited % 64 == 0 { emit(.progress(.init("Inspecting local downloads", current: url.lastPathComponent, entries: visited))) }
            }
            if ignored(root) {
                report.recordFailure(LumaError.rejected("The chosen folder is ignored."), at: root, category: .downloads, rule: "downloads.ignored", emit: emit)
            } else {
                for name in try PinnedPath.names(in: rootPin.descriptor, limit: limit) { try visit(root.exactAppendingPathComponent(name), depth: 0) }
            }
            let verified = try DuplicateScanner.verify(files.compactMap(\.item), emit: emit)
            let grouped = Dictionary(uniqueKeysWithValues: verified.duplicates.flatMap(\.items).map { (Data($0.url.path.utf8), $0) })
            for index in files.indices {
                if let item = grouped[Data(files[index].url.path.utf8)] { files[index].item = item }
            }
            report.items = files.compactMap(\.item)
            report.notices += verified.report.notices; report.coverage += verified.report.coverage
            report.isComplete = report.isComplete && verified.report.isComplete
            report.visited = visited; report.duration = Date().timeIntervalSince(start)
            try rootPin.revalidate()
            return DownloadsInventory(root: root, files: files.sorted { $0.id < $1.id }, duplicates: verified.duplicates, report: report)
        }
    }
}

/// Where-from metadata is optional, unverified and display-only. No URL opening,
/// browser database access, Spotlight query or network operation occurs here.
enum DownloadMetadata {
    static func sources(from pin: PinnedPath) -> [String] {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let size = fgetxattr(pin.descriptor, name, nil, 0, 0, 0)
        guard size > 0, size <= 16_384 else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        guard fgetxattr(pin.descriptor, name, &bytes, size, 0, 0) == size,
              let value = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil),
              let strings = value as? [String], strings.count <= 8,
              strings.allSatisfy({ $0.utf8.count <= 2_048 }) else { return [] }
        return strings.map { String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }) }.filter { !$0.isEmpty }
    }
}
