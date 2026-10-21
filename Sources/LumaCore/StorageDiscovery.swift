import Foundation
import Darwin

/// A bounded local inventory supplemented by read-only cloud metadata.
/// Discovery roots never grant cleanup authority.
public enum StorageDiscovery {
    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        normalizedRoots([home, URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Library"), URL(fileURLWithPath: "/Users/Shared"), URL(fileURLWithPath: "/opt"), URL(fileURLWithPath: "/usr/local")])
    }

    public static func normalizedRoots(_ roots: [URL]) -> [URL] {
        var result: [URL] = []
        for input in roots {
            var path = input.standardizedFileURL.path
            let data = "/System/Volumes/Data"
            if path == data { path = "/" }
            else if path.hasPrefix(data + "/") { path = String(path.dropFirst(data.count)) }
            let url = URL(fileURLWithPath: path)
            if result.contains(where: { Filesystem.isWithin(url, root: $0) }) { continue }
            result.removeAll { Filesystem.isWithin($0, root: url) }
            result.append(url)
        }
        return result
    }

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, roots: [URL]? = nil,
                            limit: Int = 40_000, ignoredPaths: Set<String> = [],
                            emit: @escaping ScanEmitter = { _ in }) throws -> StorageIndex {
        let started = Date()
        var indexes: [StorageIndex] = []
        let roots = normalizedRoots(roots ?? self.roots(home: home))
        var notices: [String] = []
        for root in roots {
            try Task.checkCancellation()
            let previous = indexes
            let previousNotices = notices
            do {
                let index = try StorageIndex.scan(root: root, limit: max(128, limit / max(1, roots.count)),
                    ignoredPaths: ignoredPaths, home: home, cache: nil, discovery: true,
                    publish: { partial in
                        if let merged = try? merge(previous + [partial], started: started, notices: previousNotices, entryLimit: limit, rootCount: roots.count) {
                            emit(.storage(merged))
                        }
                    }, emit: emit)
                indexes.append(index)
            } catch is CancellationError { throw CancellationError() }
            catch { notices.append("\(root.path): \(error.localizedDescription)"); emit(.notice(notices.last!)) }
            if !indexes.isEmpty { emit(.storage(try merge(indexes, started: started, notices: notices, entryLimit: limit, rootCount: roots.count))) }
        }
        guard !indexes.isEmpty else { throw LumaError.rejected("No local discovery roots could be read. Check Full Disk Access in System Settings.") }
        return try merge(indexes, started: started, notices: notices, entryLimit: limit, rootCount: roots.count).includingCloud(CloudStorageDiscovery.scan(home: home))
    }

    public static func refresh(_ current: StorageIndex, paths: [URL], home: URL,
                               ignoredPaths: Set<String>, limit: Int = 40_000,
                               emit: @escaping ScanEmitter = { _ in }) throws -> StorageIndex {
        var indexes: [StorageIndex] = []
        for scope in current.scopes {
            try scope.validate()
            var nodes = current.nodes.filter { $0.value.cloud == nil && $0.value.url.isFileURL && Filesystem.isWithin($0.value.url, root: scope.root) }
            let affected = paths.filter { Filesystem.isWithin($0, root: scope.root) || Filesystem.isWithin(scope.root, root: $0) }
            var targets: [URL] = []
            for path in affected {
                var target = Filesystem.isWithin(scope.root, root: path) ? scope.root : path.deletingLastPathComponent()
                while target.path != scope.root.path && nodes[target.path]?.canNavigate != true { target.deleteLastPathComponent() }
                targets.append(target)
            }
            for target in normalizedRoots(targets) {
                let retained = nodes.filter { _, node in
                    !affected.contains { Filesystem.isWithin(node.url, root: $0) || Filesystem.isWithin($0, root: node.url) }
                        && !ignoredPaths.contains { Filesystem.isWithin(node.url, root: URL(fileURLWithPath: $0)) || Filesystem.isWithin(URL(fileURLWithPath: $0), root: node.url) }
                }
                let fresh = try StorageIndex.scan(root: target, limit: max(128, limit / max(1, current.scopes.count)),
                    ignoredPaths: ignoredPaths, home: home, cache: nil, discovery: true, retained: retained, emit: emit)
                let parent = nodes[target.path]?.parentID
                nodes = nodes.filter { !Filesystem.isWithin($0.value.url, root: target) }
                nodes.merge(fresh.nodes, uniquingKeysWith: { _, new in new })
                if let node = nodes[target.path], let parent { nodes[target.path] = node.replacing(parent: parent) }
            }
            indexes.append(StorageIndex(rootID: scope.root.path, scope: scope, nodes: nodes,
                                        scannedAt: Date(), duration: 0, discoveryBounds: current.discoveryBounds))
        }
        return try merge(indexes, started: Date(), notices: []).includingCloud(CloudStorageDiscovery.scan(home: home))
    }

    private static func merge(_ indexes: [StorageIndex], started: Date, notices: [String], entryLimit: Int? = nil, rootCount: Int? = nil) throws -> StorageIndex {
        let first = indexes[0]
        var nodes: [String: StorageNode] = [:]
        for index in indexes { nodes.merge(index.nodes, uniquingKeysWith: { old, _ in old }) }
        // Recompute contributions across roots; every hard-link name retains bytes.
        var seen: Set<FileObjectID> = []
        for id in nodes.keys.sorted() {
            guard let node = nodes[id], !node.isDirectory, let device = node.device, let inode = node.inode else { continue }
            nodes[id] = node.replacing(aggregate: seen.insert(FileObjectID(device: device, inode: inode)).inserted ? node.bytes : 0)
        }
        for id in nodes.keys.sorted(by: { $0.count > $1.count }) {
            guard let node = nodes[id], node.isDirectory, !node.isPackage else { continue }
            nodes[id] = node.replacing(aggregate: node.children.compactMap { nodes[$0]?.aggregateBytes }.reduce(0, +), folderBytes: true)
        }
        let rootID = "luma://local-storage"
        let children = indexes.map(\.rootID)
        for id in children { if let node = nodes[id] { nodes[id] = node.replacing(parent: rootID) } }
        let issues = notices + indexes.compactMap { $0.nodes[$0.rootID]?.issue }
        let total = children.compactMap { nodes[$0]?.aggregateBytes }.reduce(0, +)
        nodes[rootID] = StorageNode(url: URL(string: rootID)!, parentID: nil, isDirectory: true,
            isPackage: false, hidden: false, observedAt: started, modified: nil, created: nil, bytes: total, aggregateBytes: total,
            issue: (["Accessible local roots only; system-managed space and other users are outside this inventory."] + issues).joined(separator: " "),
            accessCapability: nil, coverageState: .skipped, children: children, device: first.scope.volume.identity.device, inode: nil)
        var result = StorageIndex(rootID: rootID, scope: first.scope, nodes: nodes, scannedAt: started, duration: Date().timeIntervalSince(started))
        result.discoveryEntryLimit = entryLimit
        result.discoveryRootCount = rootCount
        result.discoveryScopes = indexes.map(\.scope)
        result.discoveryBounds = indexes.reduce(into: Set<StorageDiscoveryBound>()) { $0.formUnion($1.discoveryBounds ?? []) }
        return result
    }
}

extension StorageNode {
    public func sameObservation(as other: Self) -> Bool {
        device == other.device && inode == other.inode && modified == other.modified && created == other.created && bytes == other.bytes
    }
    func replacing(aggregate: Int64? = nil, folderBytes: Bool = false, parent: String? = nil, issue replacementIssue: String? = nil, children replacementChildren: [String]? = nil) -> Self {
        Self(url: url, parentID: parent ?? parentID, isDirectory: isDirectory, isPackage: isPackage, hidden: hidden,
             observedAt: observedAt, modified: modified, created: created, bytes: folderBytes ? aggregate ?? bytes : bytes,
             aggregateBytes: aggregate ?? aggregateBytes, issue: replacementIssue ?? issue,
             accessCapability: accessCapability, coverageState: coverageState,
             children: replacementChildren ?? children, device: device, inode: inode, cloud: cloud,
             requiresVerification: requiresVerification, ownerID: ownerID)
    }
}

extension StorageIndex {
    public var scopes: [StorageScope] { discoveryScopes.isEmpty ? [scope] : discoveryScopes }
    public var isDiscovery: Bool { !discoveryScopes.isEmpty }
    /// Keep a navigable, prioritized display subset with every ancestor intact.
    /// Omitted children remain explicit coverage, never a complete executable folder.
    public func boundedObservations(limit: Int = 10_000) -> Self {
        guard nodes.count > limit, limit >= scopes.count + 1 else { return self }
        var retained: Set<String> = [rootID]
        for scope in scopes { if nodes[scope.root.path] != nil { retained.insert(scope.root.path) } }
        for node in nodes.values.sorted(by: { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }) {
            let ancestors = Set(breadcrumbs(to: node.id).map(\.id))
            let missing = ancestors.subtracting(retained)
            if retained.count + missing.count <= limit { retained.formUnion(missing) }
            if retained.count == limit { break }
        }
        var bounded: [String: StorageNode] = [:]
        for id in retained {
            guard let node = nodes[id] else { continue }
            let children = node.children.filter { retained.contains($0) }
            let truncated = id == rootID || children.count != node.children.count
            bounded[id] = node.replacing(issue: truncated
                ? [node.issue, "Saved display is bounded; refresh for remaining observations."].compactMap { $0 }.joined(separator: " ") : nil,
                children: children)
        }
        return Self(rootID: rootID, scope: scope, nodes: bounded, scannedAt: scannedAt, duration: duration, discoveryScopes: discoveryScopes, discoveryBounds: discoveryBounds, discoveryEntryLimit: discoveryEntryLimit, discoveryRootCount: discoveryRootCount)
    }

    var validHierarchy: Bool {
        guard nodes[rootID]?.parentID == nil, nodes.values.allSatisfy({ $0.bytes >= 0 && $0.aggregateBytes >= 0 }) else { return false }
        var visited: Set<String> = []
        var pending = [rootID]
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = nodes[id] else { return false }
            for child in node.children {
                guard nodes[child]?.parentID == id else { return false }
                pending.append(child)
            }
        }
        return visited.count == nodes.count
    }

    public func retainingPrevious(_ previous: Self) -> Self {
        guard rootID == previous.rootID else { return self }
        var combined = previous.nodes.merging(nodes, uniquingKeysWith: { _, new in new })
        if let before = previous.nodes[rootID], let after = nodes[rootID] {
            let children = Array(Set(before.children + after.children)).sorted()
            combined[rootID] = after.replacing(children: children)
        }
        var result = Self(rootID: rootID, scope: scope, nodes: combined, scannedAt: scannedAt,
                          duration: duration, discoveryScopes: previous.discoveryScopes, discoveryBounds: discoveryBounds, discoveryEntryLimit: discoveryEntryLimit, discoveryRootCount: discoveryRootCount)
        for scope in discoveryScopes where !result.discoveryScopes.contains(where: { $0.root == scope.root }) { result.discoveryScopes.append(scope) }
        return result
    }

    public func selectedBytes(_ ids: Set<String>) -> Int64 {
        var seen: Set<FileObjectID> = []
        var visited: Set<String> = []
        func count(_ id: String) -> Int64 {
            guard visited.insert(id).inserted, let node = nodes[id] else { return 0 }
            if node.isDirectory && !node.isPackage { return node.children.reduce(0) { $0 + count($1) } }
            guard let device = node.device, let inode = node.inode else { return 0 }
            return seen.insert(FileObjectID(device: device, inode: inode)).inserted ? node.bytes : 0
        }
        return ids.reduce(0) { $0 + count($1) }
    }

    public func prepare(ids: Set<String>, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        ignoredPaths: Set<String>, duplicateGroups: [DuplicateGroup] = []) throws -> CleanupPlan {
        try NonMaterializingIO.perform {
            guard !ids.isEmpty else {
                throw LumaError.rejected("Refresh Storage before moving these observations.")
            }
            let selected = try ids.sorted().map { id -> StorageNode in
                guard let node = nodes[id] else { throw LumaError.rejected("This observation is no longer available. Scan again.") }
                if let issue = selectionIssue(for: node, home: home, ignoredPaths: ignoredPaths, duplicateGroups: duplicateGroups) { throw LumaError.rejected(issue) }
                return node
            }
            for scope in scopes where selected.contains(where: { Filesystem.isWithin($0.url, root: scope.root) }) { try scope.validate() }
            let known = Dictionary(duplicateGroups.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
            let items = try selected.map { node in
                func verifyObservedContents() throws {
                    guard node.isDirectory else { return }
                    for descendant in nodes.values where Filesystem.isWithin(descendant.url, root: node.url) {
                        try Task.checkCancellation()
                        let observed = try PinnedPath(descendant.url)
                        let modified = Date(timeIntervalSince1970: Double(observed.value.st_mtimespec.tv_sec) + Double(observed.value.st_mtimespec.tv_nsec) / 1_000_000_000)
                        guard descendant.isComplete, UInt64(UInt32(bitPattern: observed.value.st_dev)) == descendant.device,
                              observed.value.st_ino == descendant.inode, modified == descendant.modified,
                              descendant.isDirectory || observed.value.st_size == descendant.bytes else {
                            throw LumaError.rejected("Folder contents changed since discovery. Refresh before moving it.")
                        }
                        if descendant.isDirectory {
                            let actual = Set(try PinnedPath.names(in: observed.descriptor).map { Data($0.utf8) })
                            let expected = Set(descendant.children.compactMap { nodes[$0] }.map { Data($0.url.lastPathComponent.utf8) })
                            guard actual == expected else { throw LumaError.rejected("Folder contents changed since discovery. Analyze this folder again.") }
                        }
                        try observed.revalidate()
                    }
                }
                try verifyObservedContents()
                let pin = try PinnedPath(node.url)
                guard UInt64(UInt32(bitPattern: pin.value.st_dev)) == node.device, pin.value.st_ino == node.inode,
                      Date(timeIntervalSince1970: Double(pin.value.st_mtimespec.tv_sec) + Double(pin.value.st_mtimespec.tv_nsec) / 1_000_000_000) == node.modified else {
                    throw LumaError.rejected("This item changed since discovery. Refresh before moving it.")
                }
                if let duplicate = known[node.id] {
                    let fresh = try Filesystem.inspect(node.url).1
                    guard fresh == duplicate.identity, fresh.location == duplicate.identity.location else { throw LumaError.rejected("Duplicate evidence changed. Compare the files again.") }
                    return duplicate
                }
                let item = try Filesystem.item(node.url, category: .storage, safety: .userData,
                    explanation: "Explicitly selected local personal data. Size and age do not make it unnecessary.",
                    consequence: "Moving this item to Trash can affect your documents or projects.", rule: "manual.folder-review")
                guard item.bytes == selectedBytes([node.id]) else { throw LumaError.rejected("The selected item's contents changed. Refresh before moving it.") }
                try verifyObservedContents()
                try pin.revalidate()
                return item
            }
            // Authority is narrow and captured only after explicit selection; no root-wide grant is persisted.
            return try CleanupPlan(items: items, authorizedRoots: selected.map { $0.url.deletingLastPathComponent() },
                                   ignoredPaths: ignoredPaths, duplicateGroups: duplicateGroups, source: .storage)
        }
    }

    public func removing(_ paths: [URL]) -> Self {
        var result = self
        let affected = Set(nodes.values.filter { node in paths.contains { Filesystem.isWithin(node.url, root: $0) } }.map(\.id))
        var updated = nodes.filter { !affected.contains($0.key) }
        for (id, node) in updated {
            if paths.contains(where: { Filesystem.isWithin($0, root: node.url) }) {
                updated[id] = node.replacing(issue: "Changed contents · refresh for a current total", children: node.children.filter { !affected.contains($0) })
            }
        }
        result = Self(rootID: rootID, scope: scope, nodes: updated, scannedAt: scannedAt, duration: duration, discoveryScopes: discoveryScopes, discoveryBounds: discoveryBounds, discoveryEntryLimit: discoveryEntryLimit, discoveryRootCount: discoveryRootCount)
        return result
    }
}

/// Bounded display cache, never executable evidence. No watcher is attached to this file.
public actor StorageObservationStore {
    private let url: URL
    private let nodeLimit: Int
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, nodeLimit: Int = 10_000) {
        self.nodeLimit = max(128, min(10_000, nodeLimit))
        url = home.appendingPathComponent("Library/Application Support/Luma/storage-observations.json")
    }
    public func load() throws -> StorageIndex? {
        do {
            let data = try Filesystem.readMetadata(url, limit: 33_554_432)
            let saved = try JSONDecoder().decode(StorageIndex.self, from: data)
            guard saved.nodes.count <= 10_000, saved.nodes[saved.rootID] != nil,
                  saved.nodes.allSatisfy({ $0.key == $0.value.id && $0.value.children.allSatisfy { saved.nodes[$0] != nil } }),
                  saved.validHierarchy,
                  saved.scopes.allSatisfy({ (try? $0.validate()) != nil }) else { return nil }
            var nodes = saved.nodes
            for (id, var node) in nodes { node.requiresVerification = true; nodes[id] = node }
            return StorageIndex(rootID: saved.rootID, scope: saved.scope, nodes: nodes, scannedAt: saved.scannedAt,
                duration: saved.duration, discoveryScopes: saved.discoveryScopes, discoveryBounds: saved.discoveryBounds,
                discoveryEntryLimit: saved.discoveryEntryLimit, discoveryRootCount: saved.discoveryRootCount)
        } catch { return nil }
    }
    public func clear() throws {
        do {
            try Filesystem.validatePath(url)
            try FileManager.default.removeItem(at: url)
        } catch {
            if GeneratedDataScanner.failureState(error) != .missing { throw error }
        }
    }
    public func save(_ index: StorageIndex) throws {
        guard index.nodes.count <= 200_010 else { return }
        let data = try JSONEncoder().encode(index.boundedObservations(limit: nodeLimit))
        guard data.count <= 33_554_432 else { throw LumaError.rejected("The saved hierarchy exceeds the display byte bound; current observations remain available.") }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Filesystem.validatePath(parent)
        try data.write(to: url, options: .atomic)
    }
}
