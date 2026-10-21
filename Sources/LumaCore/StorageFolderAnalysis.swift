import Foundation
import Darwin

extension StorageIndex {
    /// Only the observed, exact filesystem parent. Discovery roots and cloud
    /// hierarchy placeholders never become invented filesystem ancestors.
    public func containingFolder(of id: String) -> StorageNode? {
        guard let node = nodes[id], node.url.isFileURL, node.cloud == nil,
              let parentID = node.parentID, let parent = nodes[parentID], parent.canNavigate,
              parent.cloud == nil, parent.url.isFileURL,
              Filesystem.samePath(node.url.exactDeletingLastPathComponent(), parent.url),
              node.device != nil, node.device == parent.device else { return nil }
        return parent
    }

    /// Metadata-only availability shared by the UI and plan preparation. The
    /// journal still verifies current ownership, capabilities and the full tree.
    public func selectionIssue(for node: StorageNode, home: URL, ignoredPaths: Set<String>, duplicateGroups: [DuplicateGroup] = []) -> String? {
        let policy = SafetyEngine(home: home, ignoredPaths: ignoredPaths)
        guard node.url.isFileURL, node.cloud == nil,
              policy.permitsManualSelection(at: node.url, authorizedRoots: [home]) else {
            return "Protected, ignored or cloud-managed location. Inspect it without selecting it for removal."
        }
        guard scopes.contains(where: { Filesystem.isWithin(node.url, root: $0.root) && !$0.volume.isReadOnly && node.device == $0.volume.identity.device }) else {
            return "This location is read-only or on a different volume."
        }
        guard !node.isPackage else { return "Packages cannot be removed through generic Storage selection." }
        guard node.requiresVerification != true, Date().timeIntervalSince(node.observedAt) < 1800 else {
            return "Saved or stale observation. Analyze this folder before selecting its contents."
        }
        guard node.isComplete else { return "Incomplete coverage. Analyze this folder; unknown contents cannot be removed." }
        if node.isDirectory {
            guard node.ownerID == getuid() else { return "Current-user ownership has not been verified for this folder." }
            if duplicateGroups.flatMap(\.items).contains(where: { Filesystem.isWithin($0.url, root: node.url) }) {
                return "This folder contains known duplicates. Select individual files so a verified copy can be kept."
            }
            var pending = node.children
            var visited: Set<String> = [node.id]
            while let id = pending.popLast() {
                guard visited.insert(id).inserted, let child = nodes[id], child.isComplete,
                      child.requiresVerification != true, !child.isPackage, child.cloud == nil,
                      child.ownerID == getuid(), child.device == node.device,
                      Date().timeIntervalSince(child.observedAt) < 1800,
                      policy.permitsManualSelection(at: child.url, authorizedRoots: [home]) else {
                    return "This folder contains incomplete, protected, ignored or unsupported contents. Choose a supported child instead."
                }
                pending.append(contentsOf: child.children)
            }
        }
        return nil
    }

    /// Explicit, bounded verification of one already observed directory. No
    /// sibling traversal, cloud discovery, guessed project root or scope widening.
    public func analyzingFolder(_ id: String, home: URL, ignoredPaths: Set<String>, limit: Int = 40_000,
                                emit: @escaping ScanEmitter = { _ in }) throws -> Self {
        try NonMaterializingIO.perform {
            guard let node = nodes[id], node.canNavigate, node.cloud == nil, node.url.isFileURL,
                  let containingScope = scopes.first(where: { Filesystem.isWithin(node.url, root: $0.root) }),
                  node.device == containingScope.volume.identity.device else {
                throw LumaError.rejected("Choose an observed local folder. Cloud locations and packages remain read-only.")
            }
            try containingScope.validate()
            let pin = try PinnedPath(node.url, allowInspectionRoot: true)
            guard pin.value.st_ino == node.inode, UInt64(UInt32(bitPattern: pin.value.st_dev)) == node.device else {
                throw LumaError.rejected("This folder was replaced. Scan its location again before inspecting it.")
            }
            let fresh = try Self.scan(root: node.url, limit: max(1, min(40_000, limit)), ignoredPaths: ignoredPaths,
                home: home, expectedVolume: containingScope.volume.identity, cache: nil, discovery: true, emit: emit)
            try pin.revalidate()
            return try replacingFolderNodes(id, freshNodes: fresh.nodes, addedDuration: fresh.duration)
        }
    }

    /// Publish only the analyzed subtree into the latest observations. An
    /// unrelated mutation/refresh must never be undone by a late scan callback.
    public func mergingAnalyzedFolder(_ id: String, from analysis: Self, baseline: Self) throws -> Self {
        guard rootID == baseline.rootID, rootID == analysis.rootID,
              scopes.map(\.rootLocation) == baseline.scopes.map(\.rootLocation),
              scopes.map(\.volume.identity) == baseline.scopes.map(\.volume.identity),
              let root = nodes[id], let analyzed = analysis.nodes[id],
              root.device == analyzed.device, root.inode == analyzed.inode else {
            throw LumaError.rejected("The analysis location changed. Analyze the current folder again.")
        }
        let before = baseline.nodes.filter { $0.value.url.isFileURL && Filesystem.isWithin($0.value.url, root: root.url) }
        let current = nodes.filter { $0.value.url.isFileURL && Filesystem.isWithin($0.value.url, root: root.url) }
        guard before.count == current.count, before.allSatisfy({ id, node in
            guard let latest = current[id] else { return false }
            return latest.sameObservation(as: node) && latest.children == node.children && latest.issue == node.issue
                && latest.observedAt == node.observedAt && latest.ownerID == node.ownerID
                && latest.requiresVerification == node.requiresVerification
        }) else {
            throw LumaError.rejected("This folder changed while analysis was running. Analyze it again; newer observations were retained.")
        }
        let refreshed = analysis.nodes.filter { $0.value.url.isFileURL && Filesystem.isWithin($0.value.url, root: root.url) }
        return try replacingFolderNodes(id, freshNodes: refreshed, addedDuration: 0)
    }

    private func replacingFolderNodes(_ id: String, freshNodes: [String: StorageNode], addedDuration: TimeInterval) throws -> Self {
        guard let node = nodes[id] else { throw LumaError.rejected("This folder is no longer available. Scan its location again.") }
        var combined = nodes.filter { !$0.value.url.isFileURL || !Filesystem.isWithin($0.value.url, root: node.url) }
        combined.merge(freshNodes, uniquingKeysWith: { _, new in new })
        if let root = combined[id], let parent = node.parentID { combined[id] = root.replacing(parent: parent) }
        // Reconcile hard links across refreshed and retained branches. Dated
        // sibling observations keep their own freshness and coverage state.
        var seen: Set<FileObjectID> = []
        for key in combined.keys.sorted() {
            guard let value = combined[key], value.cloud == nil, !value.isDirectory,
                  let device = value.device, let inode = value.inode else { continue }
            combined[key] = value.replacing(aggregate: seen.insert(.init(device: device, inode: inode)).inserted ? value.bytes : 0)
        }
        for key in combined.keys.sorted(by: { $0.utf8.count > $1.utf8.count }) {
            guard let value = combined[key], value.cloud == nil, value.isDirectory, !value.isPackage,
                  value.url.isFileURL else { continue }
            combined[key] = value.replacing(aggregate: value.children.compactMap { combined[$0]?.aggregateBytes }.reduce(0, +), folderBytes: true)
            if value.isComplete, value.children.contains(where: { combined[$0]?.isComplete != true }) {
                combined[key] = combined[key]?.replacing(issue: "Partial coverage after folder analysis; skipped contents remain unknown.")
            }
        }
        if isDiscovery, let root = combined[rootID] {
            combined[rootID] = root.replacing(aggregate: scopes.compactMap { combined[$0.root.path]?.aggregateBytes }.reduce(0, +), folderBytes: true)
        }
        let result = Self(rootID: rootID, scope: scope, nodes: combined, scannedAt: scannedAt,
            duration: duration + addedDuration, discoveryScopes: discoveryScopes, discoveryBounds: discoveryBounds,
            discoveryEntryLimit: discoveryEntryLimit, discoveryRootCount: discoveryRootCount)
        guard result.validHierarchy else { throw LumaError.rejected("Folder hierarchy changed. Scan its location again.") }
        return result
    }
}
