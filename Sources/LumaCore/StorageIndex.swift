import Foundation
import Darwin

/// Read-only observations. A node is never itself permission to remove data.
public struct StorageNode: Identifiable, Codable, Sendable {
    public var id: String { url.isFileURL ? url.path : url.absoluteString }
    public let url: URL
    public let parentID: String?
    public let isDirectory: Bool
    public let isPackage: Bool
    public let hidden: Bool
    public let observedAt: Date
    public let modified: Date?
    public let created: Date?
    public let bytes: Int64
    /// Unique contribution to tree totals; bytes remains the per-path logical size.
    public let aggregateBytes: Int64
    public let issue: String?
    public let accessCapability: FilesystemCapability?
    public let coverageState: CoverageState?
    public let children: [String]
    let device: UInt64?
    let inode: UInt64?
    public var cloud: CloudStorageMetadata? = nil
    public var canNavigate: Bool { isDirectory && !isPackage && (device != nil || cloud != nil || id == "luma://icloud-metadata") }
    public var isComplete: Bool { issue == nil && cloud == nil }
}

public enum StorageDiscoveryBound: String, Codable, Sendable { case entries, time, depth }

public struct StorageIndex: Codable, Sendable {
    @TaskLocal static var discoveryClock: (@Sendable () -> Date)?
    public let rootID: String
    public let scope: StorageScope
    public let nodes: [String: StorageNode]
    public let scannedAt: Date
    public let duration: TimeInterval
    public var discoveryScopes: [StorageScope] = []
    // Optional for compatibility with saved observations from earlier versions.
    public var discoveryBounds: Set<StorageDiscoveryBound>? = nil
    public var discoveryEntryLimit: Int? = nil
    public var discoveryRootCount: Int? = nil

    public func largerScanLimit(current: Int) -> Int? {
        guard current == discoveryEntryLimit, isDiscovery, let bounds = discoveryBounds, bounds == [.entries], current > 0, current < 200_000 else { return nil }
        let next = min(200_000, current * 2)
        guard let roots = discoveryRootCount, roots > 0,
              max(128, next / roots) > max(128, current / roots) else { return nil }
        return next
    }

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
        guard !scope.inspectionOnly else { throw LumaError.rejected("This analysis is inspection-only. External and broader system targets cannot enter cleanup.") }
        try scope.validate()
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

    public static func scan(root: URL, limit: Int = 100_000, ignoredPaths: Set<String> = [], home: URL = FileManager.default.homeDirectoryForCurrentUser, expectedVolume: StorageVolumeIdentity? = nil, emit: @escaping ScanEmitter = { _ in }) throws -> Self {
        try scan(root: root, limit: limit, ignoredPaths: ignoredPaths, home: home, expectedVolume: expectedVolume, cache: nil, emit: emit)
    }

    static func scan(root: URL, limit: Int = 100_000, ignoredPaths: Set<String> = [], home: URL = FileManager.default.homeDirectoryForCurrentUser, expectedVolume: StorageVolumeIdentity? = nil, cache: AnalysisIndexSession?, discovery: Bool = false, retained: [String: StorageNode] = [:], publish: @escaping @Sendable (StorageIndex) -> Void = { _ in }, emit: @escaping ScanEmitter = { _ in }) throws -> Self {
        try NonMaterializingIO.perform {
            let started = Date()
            let root = root.exactStandardizedFileURL
            let scope = try StorageScope.capture(root: root, home: home)
            guard expectedVolume == nil || expectedVolume == scope.volume.identity else {
                throw LumaError.rejected("The selected volume changed. Refresh the volume list and choose it again.")
            }
            let rootPin = try PinnedPath(root, allowInspectionRoot: true)
            guard rootPin.value.st_mode & S_IFMT == S_IFDIR else { throw LumaError.rejected("Choose a directory.") }
            let device = UInt64(UInt32(bitPattern: rootPin.value.st_dev))
            var nodes: [String: StorageNode] = [:]
            var activeDirectories: [String: StorageNode] = [:]
            var count = 0
            var bounds: Set<StorageDiscoveryBound> = []
            var lastPublication = Date()
            let clock = discoveryClock ?? { Date() }
            let deadline = clock().addingTimeInterval(15)
            // Keep per-path logical size while assigning each inode's aggregate
            // contribution once. Folder totals add those unique contributions.
            var seen: Set<FileObjectID> = []
            func visit(_ url: URL, parent: String?, depth: Int, stopAt: Int, until: Date) throws -> StorageNode {
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
                var aggregate: Int64 = 0
                var childIDs: [String] = []
                var issue: String?
                var accessCapability: FilesystemCapability?
                var coverageState: CoverageState?
                do {
                    guard !ignoredPaths.contains(where: { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }) else {
                        throw LumaError.rejected("Ignored location; contents were not inspected.")
                    }
                    if count > min(limit, stopAt) { bounds.insert(.entries) }
                    if depth > 128 { bounds.insert(.depth) }
                    if discovery && clock() >= until { bounds.insert(.time) }
                    guard count <= min(limit, stopAt), depth <= 128, !discovery || clock() < until else {
                        throw LumaError.rejected("Discovery bound reached; remaining contents have unknown size.")
                    }
                    if discovery && (url.path == home.appendingPathComponent(".Trash").path || url.path == home.appendingPathComponent("Library/Application Support/Luma").path) {
                        throw LumaError.rejected("Luma persistence and Trash contents are excluded from automatic discovery.")
                    }
                    let pin = try PinnedPath(url, allowInspectionRoot: true)
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
                        if discovery, depth > 0, let previous = retained[url.path],
                           previous.device == nodeDevice, previous.inode == inode, previous.modified == modified {
                            // A targeted refresh keeps unrelated, unchanged branches
                            // as dated observations instead of walking them again.
                            try pin.revalidate()
                            var pending = [previous.id]
                            while let id = pending.popLast(), let saved = retained[id] {
                                try Task.checkCancellation()
                                nodes[id] = saved; pending.append(contentsOf: saved.children)
                            }
                            return previous
                        }
                        activeDirectories[url.path] = StorageNode(url: url, parentID: parent, isDirectory: true,
                            isPackage: false, hidden: hidden, observedAt: started, modified: modified, created: created,
                            bytes: 0, aggregateBytes: 0, issue: "Discovery in progress; remaining size is unknown.",
                            accessCapability: nil, coverageState: .skipped, children: [], device: nodeDevice, inode: inode)
                        let priority = ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music", "Applications"]
                        let names = try PinnedPath.names(in: pin.descriptor)
                        var entries: [(name: String, directory: Bool)] = []
                        for name in names {
                            try Task.checkCancellation()
                            var child = stat()
                            // Classify without following links or opening content.
                            let directory = discovery && fstatat(pin.descriptor, name, &child, AT_SYMLINK_NOFOLLOW) == 0
                                && child.st_mode & S_IFMT == S_IFDIR
                            entries.append((name, directory))
                        }
                        entries.sort { a, b in
                            if discovery && depth == 0 {
                                let x = priority.firstIndex(of: a.name) ?? 99, y = priority.firstIndex(of: b.name) ?? 99
                                if x != y { return x < y }
                            }
                            // Show this folder's files before descending into a huge subtree.
                            if discovery && a.directory != b.directory { return !a.directory }
                            return Data(a.name.utf8).lexicographicallyPrecedes(Data(b.name.utf8))
                        }
                        var remainingDirectories = entries.filter(\.directory).count
                        for entry in entries {
                            let entryBound = count >= min(limit, stopAt), timeBound = discovery && clock() >= until
                            if entryBound { bounds.insert(.entries) }
                            if timeBound { bounds.insert(.time) }
                            if entryBound || timeBound { issue = "Bounded discovery: remaining children have unknown size."; break }
                            // Divide both time and entries among sibling branches.
                            // Cheap branches return their unused time to the next one.
                            let now = clock()
                            let childDeadline = discovery && entry.directory
                                ? now.addingTimeInterval(max(0, until.timeIntervalSince(now)) / Double(max(1, remainingDirectories))) : until
                            let childStop = discovery && depth == 0 && entry.directory
                                ? min(stopAt, count + max(128, (stopAt - count) / max(1, remainingDirectories))) : stopAt
                            if entry.directory { remainingDirectories -= 1 }
                            let child = try visit(url.exactAppendingPathComponent(entry.name), parent: url.path, depth: depth + 1, stopAt: childStop, until: childDeadline)
                            childIDs.append(child.id)
                            bytes += child.aggregateBytes
                            aggregate += child.aggregateBytes
                            if !child.isComplete { issue = "Partial size: one or more children could not be fully inspected. Skipped bytes are unknown." }
                        }
                    } else if package {
                        if discovery { throw LumaError.rejected("Package contents are not inspected during automatic discovery.") }
                        guard !ignoredPaths.contains(where: { Filesystem.isWithin(URL(fileURLWithPath: $0), root: url) }) else {
                            throw LumaError.rejected("Package contains an ignored location; its size was not inspected.")
                        }
                        // Packages stay opaque navigation leaves, but share the
                        // same inode accounting as ordinary files in the index.
                        _ = try Filesystem.inspect(url, onFile: { object, size in
                            if seen.insert(object).inserted { bytes += size; aggregate += size }
                        })
                    } else {
                        bytes = info.st_size
                        if seen.insert(FileObjectID(device: device, inode: info.st_ino)).inserted { aggregate = bytes }
                    }
                    try pin.revalidate()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    issue = error.localizedDescription
                    accessCapability = (error as? FilesystemAccessError)?.capability
                    coverageState = GeneratedDataScanner.failureState(error)
                }
                let node = StorageNode(url: url, parentID: parent, isDirectory: directory, isPackage: package,
                    hidden: hidden, observedAt: started, modified: modified, created: created, bytes: bytes, aggregateBytes: aggregate, issue: issue,
                    accessCapability: accessCapability, coverageState: coverageState, children: childIDs, device: nodeDevice, inode: inode)
                nodes[node.id] = node
                activeDirectories.removeValue(forKey: node.id)
                if discovery && ((parent == root.path && nodes.count <= 16) || Date().timeIntervalSince(lastPublication) > 0.4) {
                    lastPublication = Date()
                    // A completed child can arrive before its parents finish.
                    // Publish an intact display hierarchy rather than dangling rows.
                    var display = activeDirectories.merging(nodes, uniquingKeysWith: { _, finished in finished })
                    let children = Dictionary(grouping: display.values, by: \.parentID)
                    for (id, value) in display where value.isDirectory && !value.isPackage {
                        display[id] = value.replacing(children: (children[id] ?? []).map(\.id).sorted())
                    }
                    publish(Self(rootID: root.path, scope: scope, nodes: display, scannedAt: started, duration: Date().timeIntervalSince(started), discoveryBounds: bounds))
                }
                if count % 128 == 0 || parent == nil {
                    emit(.progress(.init("Indexing folder hierarchy", current: url.lastPathComponent, entries: count, bytes: bytes)))
                }
                return node
            }
            _ = try visit(root, parent: nil, depth: 0, stopAt: limit, until: deadline)
            try rootPin.revalidate()
            try scope.validate()
            return Self(rootID: root.path, scope: scope, nodes: nodes, scannedAt: started, duration: Date().timeIntervalSince(started), discoveryBounds: bounds)
        }
    }
}

public struct StorageMapEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public let isRemainder: Bool

    /// Follow the list's membership and order; zero/unknown rows stay accessible in the list.
    public static func entries(for nodes: [StorageNode], limit: Int = 12) -> [Self] {
        let partition = StorageExploreListing(nodes: nodes, primaryLimit: limit)
        var entries = partition.primary.filter { $0.bytes > 0 }.map {
            Self(id: $0.id, name: $0.url.lastPathComponent, bytes: $0.bytes, isRemainder: false)
        }
        let bytes = partition.remainder.reduce(Int64(0)) { $0 + $1.bytes }
        if bytes > 0 {
            entries.append(Self(id: "storage-remainder", name: "Other items (\(partition.remainder.count))",
                bytes: bytes, isRemainder: true))
        }
        return entries
    }
}

/// One membership decision for both the Explore list and its map, after filtering/sorting.
public struct StorageExploreListing: Sendable {
    public let primary: [StorageNode]
    public let remainder: [StorageNode]
    public init(nodes: [StorageNode], primaryLimit: Int = 12) {
        let count = max(1, primaryLimit)
        primary = Array(nodes.prefix(count)); remainder = Array(nodes.dropFirst(count))
    }
}

public struct StorageListReveal: Sendable {
    public var displayLimit = 200
    public var showOther = false
    public init() {}
    public mutating func reveal(_ id: String, in rows: [StorageNode]) {
        if id == "storage-remainder" { showOther = true; displayLimit = max(displayLimit, 13); return }
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        if position >= 12 { showOther = true }
        displayLimit = max(displayLimit, position + 1)
    }
}
