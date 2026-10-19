import Foundation
import Testing
@testable import LumaCore

private final class DiscoveryBatches: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [StorageIndex] = []
    func receive(_ event: ScanEvent) { if case .storage(let index) = event { lock.withLock { values.append(index) } } }
    var snapshots: [StorageIndex] { lock.withLock { values } }
}

private final class DiscoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: elapsed) } }
    func advance() { lock.withLock { elapsed += 1 } }
}

@Suite("Automatic local storage discovery") struct StorageDiscoveryTests {
    @Test func normalizedRootsAvoidFirmlinksAndOverlaps() {
        let roots = StorageDiscovery.normalizedRoots([URL(fileURLWithPath: "/Users/example"), URL(fileURLWithPath: "/System/Volumes/Data/Users/example/Downloads"), URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Volumes/Data/Applications")])
        #expect(roots.map(\.path) == ["/Users/example", "/Applications"])
    }

    @Test func slowNestedBranchCannotStarveSiblingFilesOrFolders() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for i in 0..<32 { _ = try f.file("a-huge/slow-\(i)", content: "nested") }
        let sibling = try f.file("z-folder/important", content: "sibling")
        let direct = try f.file("z-direct", content: "direct")
        let clock = DiscoveryClock()
        let index = try StorageIndex.$discoveryClock.withValue(clock.now) {
            try FilesystemAccess.$restriction.withValue({ url in
                if url.lastPathComponent.hasPrefix("slow-") { clock.advance() }
                return .local
            }) {
                try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
            }
        }
        #expect(index.validHierarchy)
        #expect(index.nodes[direct.path]?.bytes == 6)
        #expect(index.nodes[sibling.path]?.bytes == 7)
        #expect(index.nodes[f.downloads.appendingPathComponent("a-huge").path]?.isComplete == false)
        #expect(index.nodes.values.filter { $0.url.lastPathComponent.hasPrefix("slow-") }.count < 32)
    }

    @Test func progressiveMultiRootInventoryAndPerPathHardLinkSizes() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let first = try f.file(".hidden-first", content: "large linked content")
        let linked = f.home.appendingPathComponent("Shared/visible")
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: first, to: linked)
        let batches = DiscoveryBatches()
        let result = try StorageDiscovery.scan(home: f.home, roots: [f.downloads, linked.deletingLastPathComponent(), f.downloads], emit: batches.receive)
        #expect(result.isDiscovery && result.scopes.count == 2)
        #expect(batches.snapshots.count >= 2)
        #expect(batches.snapshots.allSatisfy { $0.validHierarchy })
        #expect(result.nodes[first.path]?.bytes == 20)
        #expect(result.nodes[linked.path]?.bytes == 20)
        #expect(result.nodes[result.rootID]?.bytes == 20)
        #expect(result.selectedBytes([first.path, linked.path]) == 20)
        #expect(result.children(of: linked.deletingLastPathComponent().path).first?.bytes == 20)
        #expect(result.breadcrumbs(to: linked.path).first?.id == result.rootID)
    }

    @Test func listingsPreserveFilteringSelectionAndStableInteractionOrder() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let large = try f.file("large.dmg", content: "larger fixture")
        let small = try f.file("small.txt", content: "x")
        let hidden = try f.file(".hidden", content: "hidden")
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        var query = StorageListingQuery(largestFiles: true, directory: nil, filter: "All items", showHidden: false,
            search: "", location: "All locations", sort: "Size", selection: [])
        #expect(try index.listing(query).map(\.id) == [large.path, small.path])
        query.pinnedOrder = [small.path, large.path]
        #expect(try index.listing(query).map(\.id) == [small.path, large.path])
        query.filter = "Selected"; query.selection = [hidden.path, f.downloads.path]
        #expect(Set(try index.listing(query).map(\.id)) == [hidden.path, f.downloads.path])
        query.filter = "Installers"; query.pinnedOrder = []; query.search = "large"
        #expect(try index.listing(query).map(\.id) == [large.path])
        query.location = f.home.appendingPathComponent("Documents").path
        #expect(try index.listing(query).isEmpty)
    }

    @Test func selectedBypassesAllBrowsingFiltersAndCapturesExactTargets() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let hidden = try f.file(".hidden", content: "hidden")
        let file = try f.file("folder/file", content: "nested")
        let folder = file.deletingLastPathComponent()
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        let ids: Set<String> = [hidden.path, folder.path]
        for largest in [true, false] {
            let query = StorageListingQuery(largestFiles: largest, directory: f.home.appendingPathComponent("Documents").path,
                filter: "Selected", showHidden: false, search: "no matching paths", location: "/unrelated", sort: "Name", selection: ids)
            let visible = Set(try index.listing(query).map(\.id))
            #expect(visible == ids)
            #expect(Set(try index.prepare(ids: visible, home: f.home, ignoredPaths: []).items.map(\.id)) == ids)
            // Ineligible selections remain visible, and cannot gain authority from visibility.
            #expect(throws: (any Error).self) { try index.prepare(ids: visible, home: f.home, ignoredPaths: [hidden.path]) }
            if !largest {
                try Data("changed".utf8).write(to: hidden)
                #expect(Set(try index.listing(query).map(\.id)) == ids)
                #expect(throws: (any Error).self) { try index.prepare(ids: visible, home: f.home, ignoredPaths: []) }
            }
        }
    }

    @Test func largerFreshScanOnlyIncreasesAnEntryBound() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for i in 0..<180 { _ = try f.file("entry-\(i)", content: "x") }
        let bounded = try StorageDiscovery.scan(home: f.home, roots: [f.downloads], limit: 128)
        #expect(bounded.discoveryBounds == [.entries])
        #expect(bounded.largerScanLimit(current: 128) == 256)
        #expect(bounded.largerScanLimit(current: 200_000) == nil)
        #expect(bounded.largerScanLimit(current: 64) == nil)
        let larger = try StorageDiscovery.scan(home: f.home, roots: [f.downloads], limit: 256)
        #expect(Set(larger.nodes.keys).subtracting(bounded.nodes.keys).count > 0)
        #expect(larger.largerScanLimit(current: 256) == nil)
        let clock = DiscoveryClock()
        let timed = try StorageIndex.$discoveryClock.withValue(clock.now) {
            try FilesystemAccess.$restriction.withValue({ url in
                if url.lastPathComponent.hasPrefix("entry-") { clock.advance() }
                return .local
            }) { try StorageDiscovery.scan(home: f.home, roots: [f.downloads], limit: 256) }
        }
        #expect(timed.discoveryBounds?.contains(.time) == true)
        #expect(timed.largerScanLimit(current: 256) == nil)
        #expect(timed.nodes.count > 2 && timed.nodes.count < larger.nodes.count)
        #expect(timed.validHierarchy)
        var divided = bounded; divided.discoveryRootCount = 6
        #expect(divided.largerScanLimit(current: 128) == nil)
        var capped = bounded; capped.discoveryEntryLimit = 200_000
        #expect(capped.largerScanLimit(current: 200_000) == nil)
        let decoded = try JSONDecoder().decode(StorageIndex.self, from: JSONEncoder().encode(bounded))
        #expect(decoded.largerScanLimit(current: 128) == 256)
        let cloud = bounded.includingCloud(.init(observations: [], notice: "Fixture"))
        #expect(cloud.largerScanLimit(current: 128) == 256)
        var legacy = bounded; legacy.discoveryBounds = nil; legacy.discoveryEntryLimit = nil
        #expect(legacy.largerScanLimit(current: 128) == nil)
    }

    @Test func freshAutomaticHomeSelectionNeedsNoPickerAndRoundTrips() async throws {
        let container = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/broad-\(UUID())")
        let f = try FilesystemEdgeFixture(root: container)
        defer { try? FileManager.default.removeItem(at: container) }
        let file = try f.file("personal/report", content: "your document")
        let index = try StorageDiscovery.scan(home: f.home, roots: [container])
        #expect(index.scope.inspectionOnly)
        let plan = try index.prepare(ids: [file.path], home: f.home, ignoredPaths: [])
        #expect(plan.authorizedRoots.map(\.path) == [file.deletingLastPathComponent().path])
        #expect(plan.items[0].safety == .userData)
        let journal = try f.journal()
        let records = try await journal.execute(plan, context: { .init() })
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try await journal.restore(try #require(records.first))
        #expect(try String(contentsOf: file, encoding: .utf8) == "your document")
    }

    @Test func protectedAndIgnoredParentsNeverGainAuthority() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let child = try f.file("folder/keep", content: "keep")
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        let folder = child.deletingLastPathComponent()
        #expect(!SafetyEngine(home: f.home, ignoredPaths: [child.path]).permitsManualSelection(at: folder, authorizedRoots: [f.home]))
        #expect(throws: (any Error).self) { try index.prepare(ids: [folder.path], home: f.home, ignoredPaths: [child.path]) }
        #expect(throws: (any Error).self) { try index.prepare(ids: [f.downloads.path], home: f.home, ignoredPaths: []) }
        #expect(throws: (any Error).self) { try index.prepare(ids: [index.rootID], home: f.home, ignoredPaths: []) }
    }

    @Test func knownDuplicateKeepOneProtectionCrossesStorageAndParentSelection() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let a = try f.file("a/one", content: "same content")
        let b = try f.file("b/two", content: "same content")
        let groups = try DuplicateScanner(root: f.downloads).scan().0
        #expect(groups.count == 1)
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home])
        #expect(throws: (any Error).self) { try index.prepare(ids: [a.path, b.path], home: f.home, ignoredPaths: [], duplicateGroups: groups) }
        #expect(throws: (any Error).self) { try index.prepare(ids: [a.deletingLastPathComponent().path], home: f.home, ignoredPaths: [], duplicateGroups: groups) }
        let valid = try index.prepare(ids: [a.path], home: f.home, ignoredPaths: [], duplicateGroups: groups)
        #expect(valid.items.first?.ruleID == "duplicates.sha256")
    }

    @Test func relaunchCorruptionAndChangedRootFallback() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file()
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        let store = StorageObservationStore(home: f.home)
        try await store.save(index)
        let saved = try #require(try await StorageObservationStore(home: f.home).load())
        #expect(saved.scannedAt == index.scannedAt && saved.nodes[file.path]?.bytes == 7)
        #expect(saved.nodes[saved.rootID]?.children == index.nodes[index.rootID]?.children)
        try await store.clear()
        #expect(try await store.load() == nil)
        try await store.save(index)
        let url = f.home.appendingPathComponent("Library/Application Support/Luma/storage-observations.json")
        try Data("corrupt".utf8).write(to: url)
        #expect(try await store.load() == nil)
        try await store.save(index)
        try FileManager.default.moveItem(at: f.downloads, to: f.home.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: f.downloads, withIntermediateDirectories: true)
        #expect(try await store.load() == nil)
    }

    @Test func dirtySubtreeRefreshRetainsOtherBranchesAndRejectsStaleSelection() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let changed = try f.file("a/file", content: "old")
        let retained = try f.file("b/retained", content: "keep")
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        try Data("new and larger".utf8).write(to: changed)
        #expect(throws: (any Error).self) { try index.prepare(ids: [changed.path], home: f.home, ignoredPaths: []) }
        let refreshed = try StorageDiscovery.refresh(index, paths: [changed], home: f.home, ignoredPaths: [])
        #expect(refreshed.nodes[retained.path]?.sameObservation(as: index.nodes[retained.path]!) == true)
        #expect(refreshed.nodes[changed.path]?.bytes == 14)
        #expect(refreshed.nodes[refreshed.rootID]?.bytes == 18)
        let remaining = refreshed.removing([changed])
        #expect(remaining.nodes[retained.path] != nil && remaining.nodes[changed.path] == nil)
        #expect(remaining.nodes[changed.deletingLastPathComponent().path]?.isComplete == false)
    }

    @Test func directFileRefreshDoesNotWalkAnUnchangedSiblingSubtree() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let changed = try f.file("direct", content: "old")
        let retained = try f.file("nested/deeper/retained", content: "keep")
        let original = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        try Data("new value".utf8).write(to: changed)
        let refreshed = try FilesystemAccess.$restriction.withValue({ url in
            url.path == retained.path ? .unknown : .local
        }) {
            try StorageDiscovery.refresh(original, paths: [changed], home: f.home, ignoredPaths: [])
        }
        #expect(refreshed.validHierarchy)
        #expect(refreshed.nodes[changed.path]?.bytes == 9)
        #expect(refreshed.nodes[retained.path]?.isComplete == true)
        #expect(refreshed.nodes[retained.path]?.observedAt == original.nodes[retained.path]?.observedAt)
        #expect(refreshed.nodes[refreshed.rootID]?.bytes == 13)
    }

    @Test func providerBoundAndOpaquePackagesRemainCoverage() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file("a/local", content: "local")
        let provider = try f.file("b-provider/content").deletingLastPathComponent()
        let package = try f.file("Sample.bundle/internal", content: "private internals").deletingLastPathComponent()
        let index = try FilesystemAccess.$restriction.withValue({ $0.path == provider.path ? .dataless : .local }) {
            try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        }
        #expect(index.nodes[provider.path]?.isComplete == false)
        #expect(index.nodes[package.path]?.bytes == 0 && index.nodes[package.path]?.isComplete == false)
        #expect(index.nodes[package.appendingPathComponent("internal").path] == nil)
        for i in 0..<150 { _ = try f.file("bounded-\(i)", content: "x") }
        let bounded = try StorageDiscovery.scan(home: f.home, roots: [f.downloads], limit: 128)
        #expect(bounded.nodes.count <= 130)
        #expect(bounded.nodes[f.downloads.path]?.isComplete == false)
    }

    @Test func partialRefreshRetainsSavedBranchesAndOriginalObservationTime() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let a = try f.file("a/one", content: "one")
        let b = try f.file("b/two", content: "two")
        let original = try StorageDiscovery.scan(home: f.home, roots: [a.deletingLastPathComponent(), b.deletingLastPathComponent()])
        let partial = try StorageDiscovery.scan(home: f.home, roots: [a.deletingLastPathComponent()])
        let retained = partial.retainingPrevious(original)
        #expect(retained.nodes[b.path]?.sameObservation(as: original.nodes[b.path]!) == true)
        #expect(retained.nodes[b.path]?.observedAt == original.nodes[b.path]?.observedAt)
        #expect(retained.children(of: retained.rootID).contains { $0.id == b.deletingLastPathComponent().path })
    }

    @Test func changedNestedContentsCannotHideBehindUnchangedFolderMetadata() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file("folder/deeper/child", content: "old")
        let folder = f.downloads.appendingPathComponent("folder")
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        try Data("new".utf8).write(to: file)
        #expect(throws: (any Error).self) { try index.prepare(ids: [folder.path], home: f.home, ignoredPaths: []) }
    }

    @Test func corruptHierarchyAndExpiredLeafAreNotExecutableEvidence() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file()
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        let store = StorageObservationStore(home: f.home)
        try await store.save(index)
        let url = f.home.appendingPathComponent("Library/Application Support/Luma/storage-observations.json")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(index)) as? [String: Any])
        var nodes = try #require(json["nodes"] as? [String: [String: Any]])
        nodes[file.path]?["observedAt"] = -1_000
        json["nodes"] = nodes
        let stale = try JSONDecoder().decode(StorageIndex.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: (any Error).self) { try stale.prepare(ids: [file.path], home: f.home, ignoredPaths: []) }
        nodes[index.rootID]?["children"] = [index.rootID]
        json["nodes"] = nodes
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(try await store.load() == nil)
    }

    @Test func commonLocationsShareBoundedDiscoveryRatherThanStarvingLaterRoots() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for i in 0..<200 { _ = try f.file("many/entry-\(i)", content: "x") }
        let document = f.home.appendingPathComponent("Documents/important")
        try FileManager.default.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("document".utf8).write(to: document)
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.home], limit: 256)
        #expect(index.nodes[document.path]?.bytes == 8)
        #expect(index.nodes[f.downloads.path]?.isComplete == false)
        #expect(index.nodes.count <= 257)
    }

    @Test func savedInventoryRetainsPrioritizedFilesAndAncestorsAtItsBound() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for i in 0..<150 { _ = try f.file("branch/entry-\(i)", content: String(repeating: "x", count: i + 1)) }
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        let store = StorageObservationStore(home: f.home, nodeLimit: 128)
        try await store.save(index)
        let saved = try #require(try await store.load())
        #expect(saved.nodes.count <= 128 && saved.validHierarchy)
        let largest = f.downloads.appendingPathComponent("branch/entry-149").path
        #expect(saved.nodes[largest]?.bytes == 150)
        #expect(saved.breadcrumbs(to: largest).count == 4)
        #expect(saved.nodes[f.downloads.appendingPathComponent("branch").path]?.isComplete == false)
        #expect(saved.nodes[largest]?.observedAt == index.nodes[largest]?.observedAt)
    }

    @Test func ownedPersistenceDoesNotCreateRefreshLoop() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let external = try f.file("real-change", content: "first")
        // Create the owned directory before the stream, as a normal existing installation does.
        let store = StorageObservationStore(home: f.home)
        let index = try StorageDiscovery.scan(home: f.home, roots: [f.downloads])
        try await store.save(index)
        let changes = StorageChanges(roots: [f.home], home: f.home)
        try await Task.sleep(for: .milliseconds(1200))
        _ = changes.take()
        try await store.save(index)
        try await Task.sleep(for: .milliseconds(1600))
        #expect(changes.take().isEmpty)
        try Data("external modification".utf8).write(to: external)
        try await Task.sleep(for: .milliseconds(1600))
        #expect(changes.take().contains { $0.path == external.path })
    }
}
