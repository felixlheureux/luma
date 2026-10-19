import Foundation
import Darwin
import Testing
@testable import LumaCore

@Suite("Hierarchical storage") struct StorageIndexTests {
    @Test func hierarchyAccountingAndOpaquePackages() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let first = try f.file("a/b/c/first", content: "12345")
        try FileManager.default.linkItem(at: first, to: f.downloads.appendingPathComponent("linked"))
        _ = try f.file(".hidden", content: "123")
        _ = try f.file("Sample.bundle/inside", content: "12")
        let index = try StorageIndex.scan(root: f.downloads)
        #expect(index.nodes[index.rootID]?.bytes == 10)
        #expect(index.nodes[f.downloads.appendingPathComponent("linked").path]?.bytes == 5)
        #expect(index.children(of: index.rootID).count == 3)
        #expect(index.children(of: index.rootID, showHidden: true).count == 4)
        #expect(index.breadcrumbs(to: first.deletingLastPathComponent().path).count == 4)
        let package = try #require(index.nodes[f.downloads.appendingPathComponent("Sample.bundle").path])
        #expect(package.isPackage && !package.canNavigate && package.children.isEmpty)
        #expect(index.children(of: index.rootID, showHidden: true).reduce(0) { $0 + $1.aggregateBytes } == 10)
        #expect(index.nodes.values.allSatisfy { $0.isComplete })
    }

    @Test func remainderCoversAllMatchingBytesAndCannotEnterReview() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for i in 0..<20 { _ = try f.file("entry-\(i)", content: String(repeating: "a", count: i)) }
        let index = try StorageIndex.scan(root: f.downloads)
        let children = index.children(of: index.rootID)
        let map = StorageMapEntry.entries(for: children)
        #expect(map.count == 13)
        #expect(map.last?.isRemainder == true)
        #expect(map.reduce(0) { $0 + $1.bytes } == index.nodes[index.rootID]?.bytes)
        #expect(throws: (any Error).self) { _ = try index.reviewItems(ids: ["storage-remainder"], directory: index.rootID) }
        #expect(!SafetyEngine(home: f.home).permitsManualSelection(at: f.downloads, authorizedRoots: [f.home]))
        #expect(SafetyEngine(home: f.home).permitsManualSelection(at: children[0].url, authorizedRoots: [f.downloads]))
        #expect(!SafetyEngine(home: f.home).permitsManualSelection(at: children[0].url, authorizedRoots: []))
    }

    @Test func excludedAndUnreadableArePartialRatherThanEmpty() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file("local", content: "local")
        let remote = try f.file("remote/content").deletingLastPathComponent()
        let denied = try f.file("denied/content").deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        try FilesystemAccess.$restriction.withValue({ $0.path == remote.path ? .dataless : .local }) {
            let index = try StorageIndex.scan(root: f.downloads)
            #expect(index.nodes[index.rootID]?.isComplete == false)
            #expect(index.nodes[index.rootID]?.bytes == 5)
            #expect(index.nodes[remote.path]?.issue != nil)
            #expect(index.nodes[denied.path]?.issue != nil)
            #expect(index.nodes[remote.appendingPathComponent("content").path] == nil)
            #expect(throws: (any Error).self) { _ = try index.reviewItems(ids: [remote.path], directory: index.rootID) }
        }
    }

    @Test func boundedTreesAndLinks() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let target = try f.file("a/b/c/content")
        try FileManager.default.createSymbolicLink(at: f.downloads.appendingPathComponent("link"), withDestinationURL: target)
        let index = try StorageIndex.scan(root: f.downloads, limit: 3)
        #expect(index.nodes.count <= 3)
        #expect(index.nodes[index.rootID]?.isComplete == false)
        let full = try StorageIndex.scan(root: f.downloads)
        #expect(full.nodes[f.downloads.appendingPathComponent("link").path]?.isComplete == false)
    }

    @Test func cancellationProducesNoCompletedIndex() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file()
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { _ = try StorageIndex.scan(root: f.downloads) }
        }
        await worker.value
    }

    @Test func changedDeletedAndOutOfDirectorySelectionsReject() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file("folder/file")
        let index = try StorageIndex.scan(root: f.downloads)
        #expect(throws: (any Error).self) { _ = try index.reviewItems(ids: [file.path], directory: index.rootID) }
        try Data("replacement".utf8).write(to: file)
        #expect(throws: (any Error).self) { _ = try index.reviewItems(ids: [file.path], directory: file.deletingLastPathComponent().path) }
        try FileManager.default.removeItem(at: file)
        #expect(throws: (any Error).self) { _ = try index.reviewItems(ids: [file.path], directory: file.deletingLastPathComponent().path) }
    }

    @Test func reviewedNestedSelectionRoundTripAndProtectedRoots() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file("a/b/c/content", content: "nested data")
        _ = try f.file("preserved", content: "keep")
        let index = try StorageIndex.scan(root: f.downloads)
        let items = try index.reviewItems(ids: [file.path], directory: file.deletingLastPathComponent().path)
        let plan = try CleanupPlan(items: items, authorizedRoots: [f.downloads])
        let journal = try f.journal()
        let records = try await journal.execute(plan, context: { .init() })
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try await journal.restore(try #require(records.first))
        #expect(try String(contentsOf: file, encoding: .utf8) == "nested data")
        #expect(try String(contentsOf: f.downloads.appendingPathComponent("preserved"), encoding: .utf8) == "keep")
        let homeIndex = try StorageIndex.scan(root: f.home)
        let protected = try homeIndex.reviewItems(ids: [f.downloads.path], directory: homeIndex.rootID)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(protected[0], authorizedRoots: [f.home]) }
    }
}
