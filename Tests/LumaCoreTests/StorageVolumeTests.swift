import Foundation
import Testing
@testable import LumaCore

private struct VolumeFixture {
    let home: URL
    var root: URL { home.appendingPathComponent("Data") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/volume-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    @discardableResult func file(_ name: String, text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Volume-bound read-only storage analysis") struct StorageVolumeTests {
    @Test func capacityAndLogicalBytesRemainSeparateAndScopeStaysVisible() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        try f.file("nested/a.txt")
        let index = try StorageIndex.scan(root: f.root, home: f.home)
        #expect(Filesystem.samePath(index.scope.root, f.root))
        #expect(!index.scope.inspectionOnly)
        #expect(index.scope.volume.capacity.map { $0 > 0 } == true)
        #expect(index.scope.volume.free.map { $0 >= 0 } == true)
        #expect(!index.scope.volume.identity.uuid.isEmpty)
        #expect(index.nodes[index.rootID]?.bytes == 7)
        try index.scope.validate()
        #expect(index.breadcrumbs(to: f.root.appendingPathComponent("nested").path).map(\.id) == [f.root.path, f.root.appendingPathComponent("nested").path])
    }

    @Test func broaderTargetCannotProduceCleanupEvenForReadableHomeChildren() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let child = try f.file("a.txt")
        let hypotheticalHome = f.root.appendingPathComponent("SeparateHome")
        try FileManager.default.createDirectory(at: hypotheticalHome, withIntermediateDirectories: true)
        let index = try StorageIndex.scan(root: f.root, home: hypotheticalHome)
        #expect(index.scope.inspectionOnly)
        #expect(index.nodes[child.path]?.bytes == 7)
        #expect(throws: (any Error).self) { try index.reviewItems(ids: [child.path], directory: f.root.path) }
    }

    @Test func replacedOrMissingRootInvalidatesScopeAndReview() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let child = try f.file("a.txt")
        let index = try StorageIndex.scan(root: f.root, home: f.home)
        try FileManager.default.moveItem(at: f.root, to: f.home.appendingPathComponent("Detached"))
        #expect(throws: (any Error).self) { try index.scope.validate() }
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        try f.file("a.txt")
        #expect(throws: (any Error).self) { try index.scope.validate() }
        #expect(throws: (any Error).self) { try index.reviewItems(ids: [child.path], directory: f.root.path) }
        let replacement = try StorageIndex.scan(root: f.root, home: f.home)
        #expect(replacement.scope.rootLocation != index.scope.rootLocation)
    }

    @Test func volumeIdentityIncludesUuidDeviceMountAndFilesystemGeneration() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let scope = try StorageScope.capture(root: f.root, home: f.home)
        let identity = scope.volume.identity
        #expect(identity != StorageVolumeIdentity(uuid: "replacement", device: identity.device, mountPath: identity.mountPath, filesystemID: identity.filesystemID))
        #expect(identity != StorageVolumeIdentity(uuid: identity.uuid, device: identity.device + 1, mountPath: identity.mountPath, filesystemID: identity.filesystemID))
        #expect(identity != StorageVolumeIdentity(uuid: identity.uuid, device: identity.device, mountPath: "/Volumes/replacement", filesystemID: identity.filesystemID))
        #expect(identity != StorageVolumeIdentity(uuid: identity.uuid, device: identity.device, mountPath: identity.mountPath, filesystemID: Data()))
    }

    @Test func changedPickerVolumeIsRejectedBeforeTraversal() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        try f.file("a.txt")
        let identity = try StorageVolume.inspect(at: f.root).identity
        let wrong = StorageVolumeIdentity(uuid: "different-media", device: identity.device, mountPath: identity.mountPath, filesystemID: identity.filesystemID)
        #expect(throws: (any Error).self) { try StorageIndex.scan(root: f.root, home: f.home, expectedVolume: wrong) }
        let current = try StorageIndex.scan(root: f.root, home: f.home, expectedVolume: identity)
        #expect(current.nodes[current.rootID]?.bytes == 7)
    }

    @Test func filesystemRootHasInspectionMetadataButMutationPinsStillRejectIt() throws {
        let root = URL(fileURLWithPath: "/")
        #expect(throws: (any Error).self) { try PinnedPath(root) }
        let scope = try StorageScope.capture(root: root)
        #expect(scope.inspectionOnly)
        #expect(!scope.volume.identity.uuid.isEmpty)
        try scope.validate()
        let index = try StorageIndex.scan(root: root, limit: 1)
        #expect(index.scope.inspectionOnly)
        #expect(index.nodes[index.rootID]?.isComplete == false)
        #expect(throws: (any Error).self) { try index.reviewItems(ids: ["/"], directory: "/") }
    }

    @Test func ignoresStopTraversalAndRetainUnknownCoverage() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        try f.file("keep.txt"); try f.file("Ignored/secret.txt", text: "must not count")
        let ignored = f.root.appendingPathComponent("Ignored")
        let index = try StorageIndex.scan(root: f.root, ignoredPaths: [ignored.path], home: f.home)
        #expect(index.nodes[ignored.path]?.isComplete == false)
        #expect(index.nodes[ignored.appendingPathComponent("secret.txt").path] == nil)
        #expect(index.nodes[index.rootID]?.bytes == 7)
        #expect(index.nodes[index.rootID]?.isComplete == false)
    }

    @Test func ignoredPackageDescendantCannotBeReadForAnOpaqueTotal() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let secret = try f.file("Demo.app/Contents/private.txt")
        let index = try StorageIndex.scan(root: f.root, ignoredPaths: [secret.path], home: f.home)
        let package = try #require(index.nodes[f.root.appendingPathComponent("Demo.app").path])
        #expect(!package.isComplete && package.bytes == 0)
    }

    @Test func providerAndPermissionFailuresArePartialRatherThanEmpty() throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let child = try f.file("online/file.txt")
        let parent = child.deletingLastPathComponent()
        let index = try FilesystemAccess.$restriction.withValue({ url in Filesystem.samePath(url, parent) ? .providerManaged : .local }) {
            try StorageIndex.scan(root: f.root, home: f.home)
        }
        #expect(index.nodes[parent.path]?.accessCapability == .providerManaged)
        #expect(index.nodes[child.path] == nil)
        #expect(index.nodes[index.rootID]?.isComplete == false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
        let denied = try StorageIndex.scan(root: f.root, home: f.home)
        #expect(denied.nodes[index.rootID]?.isComplete == false)
    }

    @Test func symlinkReplacementAndCancellationDoNotPublishFreshAuthority() async throws {
        let f = try VolumeFixture(); defer { f.remove() }
        let scope = try StorageScope.capture(root: f.root, home: f.home)
        let moved = f.home.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: f.root, to: moved)
        try FileManager.default.createSymbolicLink(at: f.root, withDestinationURL: moved)
        #expect(throws: (any Error).self) { try scope.validate() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try StorageIndex.scan(root: moved, home: f.home) }
        }
        await task.value
    }
}
