import Foundation
import Darwin
import Testing
@testable import LumaCore

private final class CloudReads: @unchecked Sendable {
    let lock = NSLock()
    var paths: [String] = []
    var guarded = true
    func observe(_ url: URL) {
        lock.withLock {
            paths.append(url.path)
            guarded = guarded && getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == IOPOL_MATERIALIZE_DATALESS_FILES_OFF
        }
    }
}

@Suite("Read-only iCloud metadata") struct CloudStorageTests {
    /// Opt-in integration reads only a disposable fixture prepared by the caller.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMA_ICLOUD_FIXTURE_HOME"] != nil))
    func disposableRealICloudMetadata() throws {
        let path = try #require(ProcessInfo.processInfo.environment["LUMA_ICLOUD_FIXTURE_HOME"])
        let home = URL(fileURLWithPath: path)
        let file = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/created-locally.txt")
        let inventory = try CloudStorageDiscovery.scan(home: home)
        let observation = try #require(inventory.observations.first { $0.url.path == file.path })
        #expect(observation.metadata.source == .filesystem)
        #expect(observation.metadata.logicalBytes == 25)
        #expect(observation.metadata.allocatedBytes != nil)
        #expect(try FilesystemAccess.capability(at: file) != .local)
        print("Disposable real iCloud: state=\(observation.metadata.state.rawValue), logical=\(String(describing: observation.metadata.logicalBytes)), allocated=\(String(describing: observation.metadata.allocatedBytes))")
    }

    @Test func guardedEnumerationStopsAtOnlineOnlyFoldersAndDoesNotFollowLinks() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let root = f.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let remote = root.appendingPathComponent("Optimized")
        // The injected provider state deliberately leaves SF_DATALESS unset:
        // download status alone must stop traversal, even before flags catch up.
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Data("never read".utf8).write(to: remote.appendingPathComponent("hidden-content"))
        let downloaded = root.appendingPathComponent("downloaded")
        try Data("local fixture".utf8).write(to: downloaded)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: f.downloads)
        let reads = CloudReads()
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        let inventory = try CloudStorageDiscovery.$readObserver.withValue(reads.observe) {
            try CloudStorageDiscovery.$onlineOnlyPaths.withValue([remote.path]) {
                try CloudStorageDiscovery.scan(home: f.home)
            }
        }
        #expect(reads.guarded)
        #expect(!reads.paths.contains(remote.appendingPathComponent("hidden-content").path))
        #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == previous)
        #expect(inventory.observations.first { $0.url.path == remote.path }?.metadata.state == .onlineOnly)
        #expect(!inventory.observations.contains { $0.url.lastPathComponent == "escape" })
        #expect(inventory.observations.first { $0.url.path == downloaded.path }?.metadata.logicalBytes == 13)
        #expect(try FilesystemAccess.capability(at: downloaded) == .providerManaged)
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home]).includingCloud(inventory)
        #expect(index.validHierarchy)
        #expect(index.nodes[downloaded.path]?.cloud != nil)
        #expect(index.nodes[index.rootID]?.bytes == 0)
        #expect(throws: (any Error).self) { try index.prepare(ids: [downloaded.path], home: f.home, ignoredPaths: []) }
        #expect(throws: (any Error).self) { try index.prepare(ids: [root.path], home: f.home, ignoredPaths: []) }
    }

    @Test func exhaustedObservationBudgetsPerformNoFilesystemReads() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let reads = CloudReads()
        for limit in [0, -1, Int.min] {
            let inventory = try CloudStorageDiscovery.$readObserver.withValue(reads.observe) {
                try CloudStorageDiscovery.scan(home: f.home, limit: limit)
            }
            #expect(inventory.observations.isEmpty)
            #expect(inventory.notice.contains("partial"))
        }
        #expect(reads.paths.isEmpty)
    }

    @Test func provisionalMissingPathsUnknownAllocationAndCachedEvidenceNeverAuthorizeCleanup() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let local = try f.file("ordinary", content: "local")
        let base = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        let remote = f.downloads.appendingPathComponent("not-present")
        let metadata = CloudStorageMetadata(state: .unknown, source: .index,
            observedAt: Date().addingTimeInterval(-3600), logicalBytes: 8_000_000_000, allocatedBytes: nil)
        let inventory = CloudStorageInventory(observations: [.init(url: remote, isDirectory: false, metadata: metadata)], notice: CloudStorageDiscovery.coverage)
        let index = base.includingCloud(inventory)
        #expect(index.validHierarchy)
        #expect(index.nodes[index.rootID]?.bytes == 5)
        #expect(index.selectedBytes([remote.path]) == 0)
        #expect(index.nodes[remote.path]?.cloud?.allocatedBytes == nil)
        #expect(index.nodes[remote.path]?.cloud?.source == .index)
        #expect(try index.prepare(ids: [local.path], home: f.home, ignoredPaths: []).items.count == 1)
        #expect(throws: (any Error).self) { try index.prepare(ids: [remote.path], home: f.home, ignoredPaths: []) }
        let store = StorageObservationStore(home: f.home)
        try await store.save(index)
        let saved = try #require(try await store.load())
        #expect(saved.nodes[remote.path]?.cloud == metadata)
        #expect(throws: (any Error).self) { try saved.reviewItems(ids: [remote.path], directory: "luma://icloud-metadata") }
        let refreshed = try StorageDiscovery.refresh(index, paths: [local], home: f.home, ignoredPaths: [])
        #expect(refreshed.nodes[remote.path] == nil)
        #expect(refreshed.validHierarchy)
    }

    @Test func cloudReplacementRemovesLocalAuthorityAndOverlappingDescendants() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file("relocated/child", content: "now managed")
        let base = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        let parent = file.deletingLastPathComponent()
        let meta = CloudStorageMetadata(state: .local, source: .filesystem, observedAt: Date(), logicalBytes: nil, allocatedBytes: nil)
        let index = base.includingCloud(.init(observations: [.init(url: parent, isDirectory: true, metadata: meta)], notice: "Partial"))
        #expect(index.validHierarchy)
        #expect(index.nodes[file.path] == nil)
        #expect(index.nodes[index.rootID]?.bytes == 0)
        #expect(throws: (any Error).self) { try index.prepare(ids: [parent.path], home: f.home, ignoredPaths: []) }
    }

    @Test func absentCloudRootsDoNotBlockLocalDiscoveryAndBoundsRemainExplicit() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file()
        let empty = try CloudStorageDiscovery.scan(home: f.home)
        #expect(empty.observations.isEmpty)
        #expect(empty.notice.contains("partial"))
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        #expect(index.validHierarchy)
        #expect(index.nodes[index.rootID]?.bytes == 7)
        #expect(index.nodes["luma://icloud-metadata"]?.issue?.contains("unavailable") == true)
    }
}
