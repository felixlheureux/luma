import Foundation
import Darwin
import Testing
@testable import LumaCore

/// All paths and metadata belong to disposable fixtures. Optional image roots
/// exercise the same corpus on explicitly mounted case-sensitive filesystems.
struct FilesystemEdgeFixture {
    let home: URL
    var downloads: URL { home.appendingPathComponent("Downloads") }
    var trash: URL { home.appendingPathComponent(".Trash") }
    init(root: URL? = nil) throws {
        let base = root ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures")
        home = base.appendingPathComponent(UUID().uuidString)
        for directory in [downloads, trash] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }
    func file(_ name: String = "file", content: String = "fixture") throws -> URL {
        let path = downloads.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: path)
        return path
    }
    func item(_ path: URL) throws -> CleanupItem {
        try Filesystem.item(path, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
    }
    func journal() throws -> CleanupJournal {
        let destination = trash
        return try CleanupJournal(home: home, trashMover: { source in
            var target = destination.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { target = destination.appendingPathComponent(UUID().uuidString) }
            try FileManager.default.moveItem(at: source, to: target)
            return target
        })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Descriptor filesystem boundaries") struct FilesystemIdentityTests {
    @Test(arguments: ["parent", "ancestor", "target", "link"])
    func substitutionBeforeTrashFailsWithoutMoving(_ replacement: String) async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let path = try f.file("folder/file")
        let item = try f.item(path)
        let plan = try CleanupPlan(items: [item], authorizedRoots: [f.downloads])
        let journal = try f.journal()
        await journal.setMutationCheckpoint {
            switch replacement {
            case "parent", "ancestor":
                let parent = replacement == "parent" ? path.deletingLastPathComponent() : f.downloads
                let saved = parent.appendingPathExtension("saved")
                try FileManager.default.moveItem(at: parent, to: saved)
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Same inode at the same pathname: only the ancestor evidence differs.
                let original = replacement == "parent" ? saved.appendingPathComponent("file") : saved.appendingPathComponent("folder/file")
                try FileManager.default.moveItem(at: original, to: path)
            case "target":
                try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("saved"))
                try Data("replacement".utf8).write(to: path)
            default:
                try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("saved"))
                try FileManager.default.createSymbolicLink(at: path, withDestinationURL: path.appendingPathExtension("saved"))
            }
        }
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { .init() }) }
        #expect(try FileManager.default.contentsOfDirectory(at: f.trash, includingPropertiesForKeys: nil).isEmpty)
        #expect(await journal.snapshot().records.isEmpty)
        #expect(await journal.snapshot().unresolved.isEmpty)
    }

    @Test func ambiguousAndRemotePathsAreRejected() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file()
        let dotted = URL(string: f.downloads.absoluteString + "/../Downloads/file")!
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(dotted) }
        let nul = URL(string: f.downloads.absoluteString + "/file%00other")!
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(nul) }
        let remote = URL(string: "file://remote-host" + f.downloads.path + "/file")!
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(remote) }
    }

    @Test func tokensAreBoundToPathObjectParentAndDevice() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let path = try f.file()
        let pin = try PinnedPath(path)
        let alias = f.downloads.appendingPathComponent("hardlink")
        try FileManager.default.linkItem(at: path, to: alias)
        #expect(throws: (any Error).self) { try PinnedPath(alias).revalidate(expected: pin.location) }
        var chain = pin.location.chain
        var foreign = pin.value
        foreign.st_dev = foreign.st_dev &+ 1
        chain[chain.count - 1] = FileLocation.Component(foreign)
        let forged = FileLocation(path: pin.location.path, chain: chain)
        #expect(throws: (any Error).self) { try pin.revalidate(expected: forged) }
        try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("saved"))
        try Data("different".utf8).write(to: path)
        #expect(throws: (any Error).self) { try pin.revalidate() }
    }

    @Test(arguments: ["parent", "source", "occupied"])
    func restoreBoundaryRejectsSubstitution(_ replacement: String) async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let item = try f.item(f.file())
        let journal = try f.journal()
        let records = try await journal.execute(CleanupPlan(items: [item], authorizedRoots: [f.downloads]), context: { .init() })
        let record = try #require(records.first)
        await journal.setMutationCheckpoint {
            if replacement == "parent" {
                try FileManager.default.moveItem(at: f.downloads, to: f.downloads.appendingPathExtension("saved"))
                try FileManager.default.createDirectory(at: f.downloads, withIntermediateDirectories: true)
            } else if replacement == "source" {
                try FileManager.default.moveItem(at: record.trashed, to: record.trashed.appendingPathExtension("saved"))
                try Data("replacement".utf8).write(to: record.trashed)
            } else { try Data("occupied".utf8).write(to: record.original) }
        }
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(await journal.snapshot().records.first?.restored == false)
        #expect(await journal.snapshot().unresolved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: record.trashed.path))
        if replacement == "occupied" { #expect(try String(contentsOf: record.original, encoding: .utf8) == "occupied") }
        else { #expect(!FileManager.default.fileExists(atPath: record.original.path)) }
    }

    @Test func replacedOriginalParentBeforeRestoreIsRejected() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let journal = try f.journal()
        let item = try f.item(f.file())
        let record = try #require(try await journal.execute(CleanupPlan(items: [item], authorizedRoots: [f.downloads]), context: { .init() }).first)
        try FileManager.default.moveItem(at: f.downloads, to: f.downloads.appendingPathExtension("saved"))
        try FileManager.default.createDirectory(at: f.downloads, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(FileManager.default.fileExists(atPath: record.trashed.path))
    }

    @Test func aliasesAndSpecialObjectsAreRejectedWithoutReading() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let target = try f.file()
        let alias = f.downloads.appendingPathComponent("alias")
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        #expect(try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true)
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(alias) }
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(f.downloads) }
        try FileManager.default.removeItem(at: alias)
        let fifo = f.downloads.appendingPathComponent("fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(fifo) }
        #expect(throws: (any Error).self) { _ = try Filesystem.hash(fifo) }
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(f.downloads) }
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(URL(fileURLWithPath: "/dev/null")) }
    }

    @Test func fingerprintEncodingPreservesUnusualNamesAndRelocation() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        for name in ["a|b\nc", "a\nb|c", "é", "Upper", "lower", String(repeating: "x", count: 220)] { _ = try f.file(name) }
        let before = try Filesystem.inspect(f.downloads)
        #expect(before.0 == 42)
        let renamed = f.home.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: f.downloads, to: renamed)
        let after = try Filesystem.inspect(renamed)
        #expect(before.1 == after.1)
        #expect(before.1.location != after.1.location)
        let a = renamed.appendingPathComponent("a|b\nc"), b = renamed.appendingPathComponent("a\nb|c")
        let first = try PinnedPath(a), second = try PinnedPath(b)
        #expect(first.location != second.location)
    }

    @Test func applicationFrameworkLinksRoundTripAndAliasesStayExcluded() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let bundle = f.downloads.appendingPathComponent("Example.app")
        _ = try f.file("Example.app/Contents/Info.plist", content: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.example.fixture</string></dict></plist>")
        let binary = try f.file("Example.app/Contents/Frameworks/Versions/A/library")
        let link = bundle.appendingPathComponent("Contents/Frameworks/Versions/Current")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "A")
        let item = try f.item(bundle)
        let journal = try f.journal()
        let record = try #require(try await journal.execute(CleanupPlan(items: [item], authorizedRoots: [f.downloads]), context: { .init() }).first)
        try await journal.restore(record)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "A")
        #expect(try String(contentsOf: binary, encoding: .utf8) == "fixture")
        let bookmark = try binary.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: bundle.appendingPathComponent("Contents/alias"))
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(bundle) }
    }

    @Test func caseAndUnicodeAreComparedAsFilesystemBytes() throws {
        // APFS may normalize names; byte comparisons still must never merge
        // distinct input paths just because Swift String equality does.
        let composed = URL(string: "file:///fixture/%C3%A9")!
        let decomposed = URL(string: "file:///fixture/e%CC%81")!
        #expect(!Filesystem.isWithin(composed, root: decomposed))
        #expect(!Filesystem.isWithin(URL(fileURLWithPath: "/fixture/A"), root: URL(fileURLWithPath: "/fixture/a")))
    }

    @Test func legacyJournalIdentityDecodesAndReconcilesWithoutEnablingRestore() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let file = try f.file()
        var legacy = try Filesystem.inspect(file, onFile: nil, legacyFingerprint: true).1
        legacy.location = nil
        let encoded = try JSONEncoder().encode(legacy)
        #expect(try JSONDecoder().decode(FileIdentity.self, from: encoded).location == nil)
        let destination = f.trash.appendingPathComponent("file")
        try FileManager.default.moveItem(at: file, to: destination)
        let intent = JournalIntent(id: UUID(), action: .trash, original: file, source: file, destination: destination,
                                   identity: legacy, bytes: legacy.size, date: Date(), recordID: nil)
        let directory = f.home.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(JournalState(pending: [intent])).write(to: directory.appendingPathComponent("operations.json"))
        let journal = try CleanupJournal(home: f.home, directory: directory)
        let snapshot = try await journal.reconcile()
        #expect(snapshot.unresolved.isEmpty)
        let record = try #require(snapshot.records.first)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }
}

struct FilesystemEdgeCorpus {
    let root: URL
    let tagged: URL
    let sparse: URL
    let hardlink: URL
    let attribute = Data("fixture extended attribute".utf8)
    let tags: Data
    let acl: Data
    let allocatedBlocks: Int64

    init(in directory: URL) throws {
        root = directory.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["pipe|name\nline", "é", "e\u{301}", "Upper", "lower", String(repeating: "l", count: 220)] {
            try Data(name.utf8).write(to: root.exactAppendingPathComponent(name))
        }
        tagged = root.appendingPathComponent("tagged")
        try Data("metadata and hard links".utf8).write(to: tagged)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: tagged.path)
        tags = try PropertyListSerialization.data(fromPropertyList: ["Fixture\n6"], format: .binary, options: 0)
        try Self.setAttribute("app.luma.fixture", value: attribute, at: tagged)
        try Self.setAttribute("com.apple.metadata:_kMDItemUserTags", value: tags, at: tagged)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "user:\(NSUserName()) allow read,readattr,readextattr,readsecurity", tagged.path]
        try chmod.run(); chmod.waitUntilExit()
        guard chmod.terminationStatus == 0 else { throw LumaError.rejected("Fixture ACL creation failed.") }
        acl = try Self.aclText(at: tagged)
        hardlink = root.appendingPathComponent("hardlink")
        try FileManager.default.linkItem(at: tagged, to: hardlink)
        sparse = root.appendingPathComponent("sparse")
        let fd = open(sparse.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw PinnedPath.posixError() }
        defer { close(fd) }
        guard ftruncate(fd, 16 * 1024 * 1024) == 0 else { throw PinnedPath.posixError() }
        let tail: [UInt8] = [1, 2, 3, 4]
        guard pwrite(fd, tail, tail.count, 16 * 1024 * 1024 - 4) == tail.count else { throw PinnedPath.posixError() }
        guard fsync(fd) == 0 else { throw PinnedPath.posixError() }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw PinnedPath.posixError() }
        allocatedBlocks = metadata.st_blocks
    }

    static func setAttribute(_ name: String, value: Data, at url: URL) throws {
        let result = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }
        guard result == 0 else { throw PinnedPath.posixError() }
    }

    static func getAttribute(_ name: String, at url: URL) throws -> Data {
        let count = getxattr(url.path, name, nil, 0, 0, 0)
        guard count >= 0 else { throw PinnedPath.posixError() }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }
        guard read == count else { throw PinnedPath.posixError() }
        return data
    }

    static func aclText(at url: URL) throws -> Data {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else { throw PinnedPath.posixError() }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length = 0
        guard let text = acl_to_text(acl, &length) else { throw PinnedPath.posixError() }
        defer { acl_free(text) }
        return Data(bytes: text, count: length)
    }

    func verify() throws {
        #expect(try Self.getAttribute("app.luma.fixture", at: tagged) == attribute)
        #expect(try Self.getAttribute("com.apple.metadata:_kMDItemUserTags", at: tagged) == tags)
        #expect(try Self.aclText(at: tagged) == acl)
        let first = try PinnedPath(tagged), second = try PinnedPath(hardlink)
        #expect(first.value.st_ino == second.value.st_ino)
        #expect(first.value.st_mode & 0o777 == 0o640)
        let sparsePin = try PinnedPath(sparse)
        #expect(sparsePin.value.st_size == 16 * 1024 * 1024)
        #expect(sparsePin.value.st_blocks == allocatedBlocks)
        let handle = try FileHandle(forReadingFrom: sparse)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(16 * 1024 * 1024 - 4))
        #expect(try handle.read(upToCount: 4) == Data([1, 2, 3, 4]))
    }
}

@Suite("Filesystem metadata corpus") struct FilesystemMetadataTests {
    @Test func journalRoundTripPreservesSupportedMetadata() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let corpus = try FilesystemEdgeCorpus(in: f.downloads)
        let item = try f.item(corpus.root)
        let journal = try f.journal()
        let record = try #require(try await journal.execute(CleanupPlan(items: [item], authorizedRoots: [f.downloads]), context: { .init() }).first)
        try await journal.restore(record)
        try corpus.verify()
        #expect(try Filesystem.inspect(corpus.root).1 == item.identity)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMA_NATIVE_TRASH_TEST"] == "1"))
    func nativeTrashRoundTripPreservesSupportedMetadata() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let corpus = try FilesystemEdgeCorpus(in: f.downloads)
        let item = try f.item(corpus.root)
        // Use the actual user's native Trash only for this generated corpus.
        // Activity state stays inside the fixture; no personal candidates exist.
        let journal = try CleanupJournal(directory: f.home.appendingPathComponent("native-journal"))
        let records = try await journal.execute(CleanupPlan(items: [item], authorizedRoots: [f.downloads]), context: { .init() })
        let record = try #require(records.first)
        defer {
            if !FileManager.default.fileExists(atPath: corpus.root.path) {
                try? FileManager.default.moveItem(at: record.trashed, to: corpus.root)
            }
        }
        #expect(try Filesystem.inspect(record.trashed).1 == item.identity)
        try await journal.restore(record)
        #expect(await journal.snapshot().records.first?.restored == true)
        try corpus.verify()
        #expect(try Filesystem.inspect(corpus.root).1 == item.identity)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMA_EDGE_VOLUME_ROOT"] != nil))
    func explicitVolumeCorpusAndBoundary() throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LUMA_EDGE_VOLUME_ROOT"]))
        let f = try FilesystemEdgeFixture(root: root); defer { f.remove() }
        let corpus = try FilesystemEdgeCorpus(in: f.downloads)
        try corpus.verify()
        let upper = corpus.root.exactAppendingPathComponent("Case")
        let lower = corpus.root.exactAppendingPathComponent("case")
        try Data("upper".utf8).write(to: upper)
        try Data("lower".utf8).write(to: lower)
        #expect(try PinnedPath(upper).value.st_ino != PinnedPath(lower).value.st_ino)
        let first = try Filesystem.inspect(corpus.root)
        let destination = f.trash.appendingPathComponent("corpus")
        try FileManager.default.moveItem(at: corpus.root, to: destination)
        #expect(try Filesystem.inspect(destination).1 == first.1)
        try FileManager.default.moveItem(at: destination, to: corpus.root)
        try corpus.verify()
        let item = try f.item(upper)
        let outsideVolumeHome = root.deletingLastPathComponent().deletingLastPathComponent()
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(root.deletingLastPathComponent()) }
        do {
            try SafetyEngine(home: outsideVolumeHome).validate(item, authorizedRoots: [root])
            Issue.record("A different-volume candidate was accepted.")
        } catch { #expect(error.localizedDescription.contains("different volume")) }
        let local = try FilesystemEdgeFixture(); defer { local.remove() }
        #expect(throws: (any Error).self) {
            try SafetyEngine(home: local.home).validate(item, authorizedRoots: [root])
        }
        let localFile = try local.file()
        let localPin = try PinnedPath(localFile)
        #expect(throws: (any Error).self) { try PinnedPath(upper).revalidate(expected: localPin.location) }
    }
}
