import Foundation
import Darwin
import Testing
@testable import LumaCore

private final class AccessState: @unchecked Sendable {
    private let lock = NSLock()
    private var state: FilesystemCapability = .local
    private var moves = 0
    func set(_ value: FilesystemCapability) { lock.withLock { state = value } }
    func get() -> FilesystemCapability { lock.withLock { state } }
    func moved() { lock.withLock { moves += 1 } }
    var moveCount: Int { lock.withLock { moves } }
}

@Suite("Provider-aware filesystem access") struct FilesystemAccessTests {
    @Test(arguments: [FilesystemCapability.providerManaged, .dataless, .network, .unknown])
    func ancestorCapabilityRejectsDirectContentAPIs(_ capability: FilesystemCapability) throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        let file = try fixture.file("folder/file")
        let parent = file.deletingLastPathComponent()
        try FilesystemAccess.$restriction.withValue({ $0.path == parent.path ? capability : .local }) { () throws in
            #expect(try FilesystemAccess.capability(at: file) == capability)
            #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.inspect(file) }
            #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.hash(file) }
            #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.hash(file, partial: true) }
            #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.readMetadata(file) }
            #expect(throws: FilesystemAccessError.self) { _ = try fixture.item(file) }
        }
    }

    @Test func downloadedProviderFilesAreNotOrdinaryCleanupTargets() async throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        let file = try fixture.file()
        let item = try fixture.item(file)
        let plan = try CleanupPlan(items: [item], authorizedRoots: [fixture.downloads])
        let access = AccessState()
        let journal = try CleanupJournal(home: fixture.home, trashMover: { _ in access.moved(); throw POSIXError(.EIO) })
        await FilesystemAccess.$restriction.withValue({ $0.path == file.path ? .providerManaged : .local }) {
            #expect(throws: FilesystemAccessError.self) { try SafetyEngine(home: fixture.home).validate(item, authorizedRoots: [fixture.downloads]) }
            await #expect(throws: FilesystemAccessError.self) { _ = try await journal.execute(plan, context: { .init() }) }
        }
        #expect(access.moveCount == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test(arguments: ["source", "restore source", "restore parent"])
    func changesAtMutationBoundaryPreventMoves(_ boundary: String) async throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        let file = try fixture.file(), item = try fixture.item(file)
        let journal = try fixture.journal(), state = AccessState()
        let plan = try CleanupPlan(items: [item], authorizedRoots: [fixture.downloads])
        let affected = boundary == "source" ? file : boundary == "restore parent" ? fixture.downloads : fixture.trash
        try await FilesystemAccess.$restriction.withValue({ url in
            url.path == affected.path ? state.get() : .local
        }) {
            if boundary == "source" {
                await journal.setMutationCheckpoint { state.set(.providerManaged) }
                await #expect(throws: FilesystemAccessError.self) { _ = try await journal.execute(plan, context: { .init() }) }
                #expect(FileManager.default.fileExists(atPath: file.path))
                #expect(try FileManager.default.contentsOfDirectory(at: fixture.trash, includingPropertiesForKeys: nil).isEmpty)
            } else {
                let record = try #require(try await journal.execute(plan, context: { .init() }).first)
                await journal.setMutationCheckpoint { state.set(.unknown) }
                await #expect(throws: FilesystemAccessError.self) { try await journal.restore(record) }
                #expect(!FileManager.default.fileExists(atPath: file.path))
                #expect(FileManager.default.fileExists(atPath: record.trashed.path))
            }
            #expect(await journal.snapshot().unresolved.isEmpty)
        }
    }

    @Test func scansRetainLocalResultsAndReportSkippedProviderBytes() async throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        _ = try fixture.file("local", content: "local")
        let cloud = try fixture.file("managed/remote", content: "remote bytes must not count")
        try await FilesystemAccess.$restriction.withValue({ $0.path == cloud.deletingLastPathComponent().path ? .dataless : .local }) {
            let report = try await FolderScanner(root: fixture.downloads).scan()
            #expect(report.items.count == 1)
            #expect(report.items.first?.bytes == 5)
            #expect(!report.isComplete)
            #expect(report.coverage.contains { $0.state == .skipped && $0.bytes == 0 && $0.detail.contains("Online-only") })
            let duplicates = try DuplicateScanner(root: fixture.downloads).scanResult()
            #expect(duplicates.duplicates.isEmpty)
            #expect(!duplicates.report.isComplete)
        }
    }

    @Test func systemCloudContainersStayExcludedWithLocalContents() throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        for name in ["CloudStorage", "Mobile Documents"] {
            let directory = fixture.home.appendingPathComponent("Library/\(name)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("downloaded")
            try Data("downloaded".utf8).write(to: file)
            #expect(try FilesystemAccess.capability(at: file) == .providerManaged)
            #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.hash(file) }
        }
    }

    @Test func opaqueProviderMetadataDoesNotGrantLocalAuthority() throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        let file = try fixture.file()
        let bytes: [UInt8] = [1]
        let result = bytes.withUnsafeBytes { setxattr(file.path, "com.apple.fileprovider.luma-test", $0.baseAddress, $0.count, 0, 0) }
        #expect(result == 0)
        #expect(try FilesystemAccess.capability(at: file) == .unknown)
        #expect(throws: FilesystemAccessError.self) { _ = try Filesystem.hash(file) }
    }

    @Test func platformMetadataChangedBeforeTrashPreventsMoverInvocation() async throws {
        let fixture = try FilesystemEdgeFixture(); defer { fixture.remove() }
        let file = try fixture.file(), item = try fixture.item(file), state = AccessState()
        let journal = try CleanupJournal(home: fixture.home, trashMover: { _ in state.moved(); throw POSIXError(.EIO) })
        let plan = try CleanupPlan(items: [item], authorizedRoots: [fixture.downloads])
        await journal.setMutationCheckpoint {
            let value: [UInt8] = [1]
            let result = value.withUnsafeBytes { setxattr(file.path, "com.apple.fileprovider.luma-test", $0.baseAddress, $0.count, 0, 0) }
            guard result == 0 else { throw POSIXError(.EIO) }
        }
        await #expect(throws: FilesystemAccessError.self) { _ = try await journal.execute(plan, context: { .init() }) }
        #expect(state.moveCount == 0)
        #expect(await journal.snapshot().records.isEmpty)
        #expect(await journal.snapshot().unresolved.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "fixture")
    }

    @Test func workerPolicyRestoresOnSuccessFailureAndCancellation() throws {
        func current() -> Int32 { getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) }
        let original = current()
        try NonMaterializingIO.perform {
            #expect(current() == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
            try NonMaterializingIO.perform { #expect(current() == IOPOL_MATERIALIZE_DATALESS_FILES_OFF) }
            #expect(current() == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        }
        #expect(current() == original)
        #expect(throws: CancellationError.self) { try NonMaterializingIO.perform { throw CancellationError() } }
        #expect(current() == original)
        #expect(throws: POSIXError.self) { try NonMaterializingIO.perform { throw POSIXError(.EIO) } }
        #expect(current() == original)
    }
}
