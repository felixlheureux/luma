import Foundation
import Darwin

/// Read-only observations. A node is never itself permission to remove data.
public struct StorageNode: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let parentID: String?
    public let isDirectory: Bool
    public let isPackage: Bool
    public let hidden: Bool
    public let modified: Date?
    public let created: Date?
    public let bytes: Int64
    public let issue: String?
    public let accessCapability: FilesystemCapability?
    public let coverageState: CoverageState?
    public let children: [String]
    let device: UInt64?
    let inode: UInt64?
    public var canNavigate: Bool { isDirectory && !isPackage && device != nil }
    public var isComplete: Bool { issue == nil }
}

public struct StorageIndex: Sendable {
    public let rootID: String
    public let nodes: [String: StorageNode]
    public let scannedAt: Date
    public let duration: TimeInterval

    public func children(of id: String, showHidden: Bool = false) -> [StorageNode] {
        (nodes[id]?.children ?? []).compactMap { nodes[$0] }.filter { showHidden || !$0.hidden }
    }

    public func breadcrumbs(to id: String) -> [StorageNode] {
        var result: [StorageNode] = []
        var cursor = nodes[id]
        while let node = cursor {
            result.append(node)
            cursor = node.parentID.flatMap { nodes[$0] }
        }
        return result.reversed()
    }

    /// Capture fresh, full mutation evidence only for the explicit selection.
    /// A stale/replaced or partial observation cannot silently become a candidate.
    public func reviewItems(ids: Set<String>, directory: String) throws -> [CleanupItem] {
        guard Date().timeIntervalSince(scannedAt) < 1800 else {
            throw LumaError.rejected("This folder analysis is over 30 minutes old. Scan again.")
        }
        return try NonMaterializingIO.perform {
            try ids.sorted().map { id in
                guard let node = nodes[id], node.parentID == directory, node.isComplete else {
                    throw LumaError.rejected("Choose complete items in the current folder and scan again if needed.")
                }
                let pin = try PinnedPath(node.url)
                guard UInt64(UInt32(bitPattern: pin.value.st_dev)) == node.device,
                      pin.value.st_ino == node.inode,
                      Self.modified(pin.value) == node.modified else {
                    throw LumaError.rejected("This item changed since analysis. Scan again before review.")
                }
                let item = try Filesystem.item(node.url, category: .storage, safety: .userData,
                    explanation: "An explicitly selected item in your chosen folder. Size and age do not make it unnecessary.",
                    consequence: "This is your data. Moving it to Trash can affect documents, projects or applications.",
                    rule: "manual.folder-review")
                try pin.revalidate()
                return item
            }
        }
    }

    private static func modified(_ info: stat) -> Date {
        Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    public static func scan(root: URL, limit: Int = 100_000, emit: @escaping ScanEmitter = { _ in }) throws -> Self {
        try scan(root: root, limit: limit, cache: nil, emit: emit)
    }

    static func scan(root: URL, limit: Int = 100_000, cache: AnalysisIndexSession?, emit: @escaping ScanEmitter = { _ in }) throws -> Self {
        try NonMaterializingIO.perform {
            let started = Date()
            let root = root.exactStandardizedFileURL
            let rootPin = try PinnedPath(root)
            guard rootPin.value.st_mode & S_IFMT == S_IFDIR else { throw LumaError.rejected("Choose a directory.") }
            let device = UInt64(UInt32(bitPattern: rootPin.value.st_dev))
            var nodes: [String: StorageNode] = [:]
            var count = 0
            // Assign each inode's logical bytes to its first path in exact UTF-8
            // order. Parent totals add up; aliases in other branches count zero.
            var seen: Set<FileObjectID> = []
            func visit(_ url: URL, parent: String?, depth: Int) throws -> StorageNode {
                try Task.checkCancellation()
                count += 1
                var directory = false
                var package = false
                var hidden = url.lastPathComponent.hasPrefix(".")
                var modified: Date?
                var created: Date?
                var inode: UInt64?
                var nodeDevice: UInt64?
                var bytes: Int64 = 0
                var childIDs: [String] = []
                var issue: String?
                var accessCapability: FilesystemCapability?
                var coverageState: CoverageState?
                do {
                    guard count <= limit, depth <= 128 else { throw LumaError.rejected("Inspection limit reached; choose a smaller folder.") }
                    let pin = try PinnedPath(url)
                    let info = pin.value
                    directory = info.st_mode & S_IFMT == S_IFDIR
                    guard directory || info.st_mode & S_IFMT == S_IFREG else { throw LumaError.rejected("Unsupported filesystem object.") }
                    guard UInt64(UInt32(bitPattern: info.st_dev)) == device else { throw LumaError.rejected("A different volume was excluded.") }
                    let metadata: IndexedStorageMetadata
                    if let saved = cache?.metadata(url: url, info: info) {
                        // Package/visibility policy can change independently of
                        // leaf timestamps (for example, system type registration).
                        // Recheck boundaries even when ordinary metadata matches.
                        let values = try url.resourceValues(forKeys: [.isPackageKey, .isHiddenKey])
                        metadata = IndexedStorageMetadata(package: values.isPackage == true, hidden: values.isHidden == true, created: saved.created)
                        cache?.recordMetadata(metadata, url: url, info: info)
                    } else {
                        let values = try url.resourceValues(forKeys: [.isPackageKey, .isHiddenKey, .creationDateKey, .isAliasFileKey])
                        guard values.isAliasFile != true else { throw LumaError.rejected("Finder aliases are excluded.") }
                        metadata = IndexedStorageMetadata(package: values.isPackage == true, hidden: values.isHidden == true, created: values.creationDate)
                        cache?.recordMetadata(metadata, url: url, info: info)
                    }
                    package = metadata.package
                    hidden = hidden || metadata.hidden
                    modified = Self.modified(info)
                    created = metadata.created
                    nodeDevice = device
                    inode = info.st_ino
                    if directory && !package {
                        let names = try PinnedPath.names(in: pin.descriptor).sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
                        for name in names {
                            guard count < limit else { issue = "Inspection limit reached; some children were not inspected."; break }
                            let child = try visit(url.exactAppendingPathComponent(name), parent: url.path, depth: depth + 1)
                            childIDs.append(child.id)
                            bytes += child.bytes
                            if !child.isComplete { issue = "Partial size: one or more children could not be fully inspected. Skipped bytes are unknown." }
                        }
                    } else if package {
                        // Packages stay opaque navigation leaves, but share the
                        // same inode accounting as ordinary files in the index.
                        _ = try Filesystem.inspect(url, onFile: { object, size in
                            if seen.insert(object).inserted { bytes += size }
                        })
                    } else if seen.insert(FileObjectID(device: device, inode: info.st_ino)).inserted {
                        bytes = info.st_size
                    }
                    try pin.revalidate()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    issue = error.localizedDescription
                    accessCapability = (error as? FilesystemAccessError)?.capability
                    coverageState = GeneratedDataScanner.failureState(error)
                }
                let node = StorageNode(url: url, parentID: parent, isDirectory: directory, isPackage: package,
                    hidden: hidden, modified: modified, created: created, bytes: bytes, issue: issue,
                    accessCapability: accessCapability, coverageState: coverageState, children: childIDs, device: nodeDevice, inode: inode)
                nodes[node.id] = node
                if count % 128 == 0 || parent == nil {
                    emit(.progress(.init("Indexing folder hierarchy", current: url.lastPathComponent, entries: count, bytes: bytes)))
                }
                return node
            }
            _ = try visit(root, parent: nil, depth: 0)
            try rootPin.revalidate()
            return Self(rootID: root.path, nodes: nodes, scannedAt: started, duration: Date().timeIntervalSince(started))
        }
    }
}

public struct StorageMapEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public let isRemainder: Bool

    /// Largest positive observations plus an explicitly synthetic remainder.
    /// Unknown/zero nodes stay in the accessible list, never padded into the map.
    public static func entries(for nodes: [StorageNode], limit: Int = 12) -> [Self] {
        let sized = nodes.filter { $0.bytes > 0 }.sorted {
            $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes
        }
        let count = max(1, limit)
        var entries = sized.prefix(count).map { Self(id: $0.id, name: $0.url.lastPathComponent, bytes: $0.bytes, isRemainder: false) }
        if sized.count > count {
            entries.append(Self(id: "storage-remainder", name: "Other matching items (\(sized.count - count))",
                bytes: sized.dropFirst(count).reduce(0) { $0 + $1.bytes }, isRemainder: true))
        }
        return entries
    }
}
