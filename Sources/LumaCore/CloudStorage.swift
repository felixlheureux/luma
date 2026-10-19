import Foundation
import Darwin

/// Display evidence only. Even a downloaded cloud file never grants local cleanup authority.
public struct CloudStorageMetadata: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case local, onlineOnly, unknown }
    public enum Source: String, Codable, Sendable { case filesystem, index }
    public let state: State
    public let source: Source
    public let observedAt: Date
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?

    public init(state: State, source: Source, observedAt: Date, logicalBytes: Int64?, allocatedBytes: Int64?) {
        self.state = state; self.source = source; self.observedAt = observedAt
        self.logicalBytes = logicalBytes.flatMap { $0 >= 0 ? $0 : nil }
        self.allocatedBytes = allocatedBytes.flatMap { $0 >= 0 ? $0 : nil }
    }
}

public struct CloudStorageObservation: Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let metadata: CloudStorageMetadata
    public init(url: URL, isDirectory: Bool, metadata: CloudStorageMetadata) {
        self.url = url; self.isDirectory = isDirectory; self.metadata = metadata
    }
}

public struct CloudStorageInventory: Sendable {
    public let observations: [CloudStorageObservation]
    public let notice: String
    public init(observations: [CloudStorageObservation], notice: String) {
        self.observations = observations; self.notice = notice
    }
}

/// No descriptors for content, hashing, thumbnails, downloads or mutation are exposed here.
public enum CloudStorageDiscovery {
    @TaskLocal static var readObserver: (@Sendable (URL) -> Void)?
    // Injected exclusions may only reduce traversal; they never grant content access.
    @TaskLocal static var onlineOnlyPaths: Set<String> = []
    static let coverage = "iCloud metadata is partial; unavailable, offline and unindexed items may be absent. Indexed observations are provisional. Cloud logical bytes are excluded from local totals. Manage cloud files in Finder."

    public static func scan(home: URL, limit: Int = 4_000) throws -> CloudStorageInventory {
        try Task.checkCancellation()
        guard limit > 0 else { return CloudStorageInventory(observations: [], notice: coverage) }
        return try NonMaterializingIO.perform {
            let manager = FileManager.default
            let realHome = home.standardizedFileURL == manager.homeDirectoryForCurrentUser.standardizedFileURL
            var candidates = [home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")]
            if realHome {
                candidates += manager.urls(for: .desktopDirectory, in: .userDomainMask)
                candidates += manager.urls(for: .documentDirectory, in: .userDomainMask)
            }
            var roots: [URL] = []
            var identities: Set<FileObjectID> = []
            for candidate in candidates {
                try Task.checkCancellation()
                readObserver?(candidate)
                let resolved = candidate.resolvingSymlinksInPath()
                var info = stat()
                guard lstat(resolved.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { continue }
                let compatibility = candidate == candidates.first
                let values = try? resolved.resourceValues(forKeys: [.isUbiquitousItemKey])
                guard compatibility || values?.isUbiquitousItem == true else { continue }
                let identity = FileObjectID(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: info.st_ino)
                if identities.insert(identity).inserted { roots.append(resolved) }
            }
            roots = StorageDiscovery.normalizedRoots(roots)
            var observations: [String: CloudStorageObservation] = [:]
            let deadline = Date().addingTimeInterval(3)
            func visit(_ input: URL, depth: Int) throws {
                try Task.checkCancellation()
                guard observations.count < limit, depth < 64, Date() < deadline else { return }
                readObserver?(input)
                var info = stat()
                guard lstat(input.path, &info) == 0,
                      info.st_mode & S_IFMT != S_IFLNK else { return }
                var url = input
                url.removeAllCachedResourceValues()
                let directory = info.st_mode & S_IFMT == S_IFDIR
                let dataless = info.st_flags & UInt32(SF_DATALESS) != 0
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey,
                    .ubiquitousItemDownloadingStatusKey, .isPackageKey])
                let state: CloudStorageMetadata.State
                if dataless || onlineOnlyPaths.contains(input.path) || values?.ubiquitousItemDownloadingStatus == .notDownloaded { state = .onlineOnly }
                else if values?.ubiquitousItemDownloadingStatus == .current || values?.ubiquitousItemDownloadingStatus == .downloaded { state = .local }
                else { state = .unknown }
                // Directory st_size is not the logical size of its descendants.
                let metadata = CloudStorageMetadata(state: state, source: .filesystem, observedAt: Date(),
                    logicalBytes: directory ? nil : values?.fileSize.map(Int64.init),
                    allocatedBytes: directory ? nil : values?.fileAllocatedSize.map(Int64.init))
                observations[url.path] = CloudStorageObservation(url: url, isDirectory: directory, metadata: metadata)
                guard directory, state != .onlineOnly, values?.isPackage != true else { return }
                // EDEADLK and permission errors end this branch; never retry by materializing it.
                guard let directoryHandle = opendir(url.path) else { return }
                defer { closedir(directoryHandle) }
                while observations.count < limit, Date() < deadline, let entry = readdir(directoryHandle) {
                    let name = withUnsafePointer(to: entry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
                    }
                    if name == "." || name == ".." { continue }
                    try visit(url.appendingPathComponent(name), depth: depth + 1)
                }
            }
            for root in roots { try visit(root, depth: 0) }
            // Search the desktop index by actual roots, not app-entitled ubiquity containers.
            // Synthetic homes never query personal metadata.
            if realHome {
                for item in try indexed(roots: StorageDiscovery.normalizedRoots(roots + candidates), limit: limit) where observations[item.url.path] == nil {
                    if observations.count >= limit { break }
                    observations[item.url.path] = item
                }
            }
            return CloudStorageInventory(observations: observations.values.sorted { $0.url.path < $1.url.path }, notice: coverage)
        }
    }

    private static func indexed(roots: [URL], limit: Int) throws -> [CloudStorageObservation] {
        let query = NSMetadataQuery()
        query.searchScopes = roots.map(\.path)
        query.predicate = NSPredicate(format: "%K == YES", NSMetadataItemIsUbiquitousKey)
        guard query.start() else { return [] }
        defer { query.stop() }
        let deadline = Date().addingTimeInterval(0.5)
        while query.isGathering && Date() < deadline {
            try Task.checkCancellation()
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        query.disableUpdates()
        return (0..<min(limit, query.resultCount)).compactMap { position in
            guard let item = query.result(at: position) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard roots.contains(where: { Filesystem.isWithin(url, root: $0) }) else { return nil }
            let types = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            let directory = types.contains("public.folder")
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
            // An index cannot establish current local allocation or download state.
            return CloudStorageObservation(url: url, isDirectory: directory,
                metadata: CloudStorageMetadata(state: .unknown, source: .index, observedAt: Date(),
                    logicalBytes: directory ? nil : size.flatMap { $0 >= 0 ? $0 : nil }, allocatedBytes: nil))
        }
    }
}

extension StorageIndex {
    /// Cloud nodes have zero contribution to local totals and are always incomplete for mutation.
    public func includingCloud(_ inventory: CloudStorageInventory) -> Self {
        let branch = "luma://icloud-metadata"
        let observations = Dictionary(inventory.observations.filter { $0.url.isFileURL && $0.url.path != "/" }
            .map { ($0.url.path, $0) }, uniquingKeysWith: { _, new in new }).values.sorted { $0.url.path < $1.url.path }
        var updated = nodes.filter { $0.value.cloud == nil && $0.key != branch }
        let cloudRoots = StorageDiscovery.normalizedRoots(observations.map(\.url))
        updated = updated.filter { _, node in !cloudRoots.contains { Filesystem.isWithin(node.url, root: $0) } }
        let cloudDirectories = Set(observations.filter(\.isDirectory).map { $0.url.path })
        for (id, node) in updated {
            updated[id] = node.replacing(children: node.children.filter { $0 != branch && updated[$0] != nil })
        }
        for id in updated.keys.sorted(by: { $0.count > $1.count }) {
            guard let node = updated[id], node.isDirectory, !node.isPackage else { continue }
            let total = node.children.compactMap { updated[$0]?.aggregateBytes }.reduce(0, +)
            updated[id] = node.replacing(aggregate: total, folderBytes: true)
        }
        var branchChildren: [String] = []
        for item in observations {
            let parent = item.url.deletingLastPathComponent().path
            let parentID = cloudDirectories.contains(parent) ? parent : branch
            if parentID == branch { branchChildren.append(item.url.path) }
            updated[item.url.path] = StorageNode(url: item.url, parentID: parentID, isDirectory: item.isDirectory,
                isPackage: false, hidden: item.url.lastPathComponent.hasPrefix("."), observedAt: item.metadata.observedAt,
                modified: nil, created: nil, bytes: item.metadata.logicalBytes ?? 0, aggregateBytes: 0,
                issue: "Cloud metadata only · manage in Finder", accessCapability: .providerManaged,
                coverageState: .skipped, children: [], device: nil, inode: nil, cloud: item.metadata)
        }
        let childGroups = Dictionary(grouping: observations, by: { $0.url.deletingLastPathComponent().path })
        for item in observations where item.isDirectory {
            let children = (childGroups[item.url.path] ?? []).map { $0.url.path }
            updated[item.url.path] = updated[item.url.path]?.replacing(children: children)
        }
        updated[branch] = StorageNode(url: URL(string: branch)!, parentID: rootID, isDirectory: true,
            isPackage: false, hidden: false, observedAt: scannedAt, modified: nil, created: nil, bytes: 0,
            aggregateBytes: 0, issue: inventory.notice, accessCapability: .providerManaged,
            coverageState: .skipped, children: branchChildren, device: nil, inode: nil)
        if let root = updated[rootID] {
            let total = root.children.compactMap { updated[$0]?.aggregateBytes }.reduce(0, +)
            updated[rootID] = root.replacing(aggregate: total, folderBytes: true, children: root.children.filter { $0 != branch } + [branch])
        }
        return Self(rootID: rootID, scope: scope, nodes: updated, scannedAt: scannedAt, duration: duration, discoveryScopes: discoveryScopes, discoveryBounds: discoveryBounds, discoveryEntryLimit: discoveryEntryLimit, discoveryRootCount: discoveryRootCount)
    }
}
