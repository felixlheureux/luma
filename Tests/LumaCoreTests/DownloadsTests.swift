import Foundation
import ImageIO
import Testing
import Darwin
@testable import LumaCore

private struct DownloadsFixture {
    let home: URL
    var root: URL { home.appendingPathComponent("Downloads") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/downloads-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, _ content: String = "fixture") throws -> URL { try file(path, data: Data(content.utf8)) }
    @discardableResult func file(_ path: String, data: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func origin(_ url: URL, _ value: Any) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let status = data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, data.count, 0, 0) }
        guard status == 0 else { throw PinnedPath.posixError() }
    }
    func scan(ignored: Set<String> = []) throws -> DownloadsInventory { try DownloadsScanner.scan(root: root, ignoredPaths: ignored) }
    func plan(_ inventory: DownloadsInventory, _ ids: Set<String>) throws -> CleanupPlan { try inventory.reviewPlan(ids: ids, authorizedRoots: [root], home: home) }
    func journal() throws -> CleanupJournal {
        let trash = home.appendingPathComponent(".Trash")
        return try CleanupJournal(home: home, trashMover: { source in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Focused Downloads review") struct DownloadsTests {
    @Test func exclusiveTypesAndOverlappingFiltersDoNotInflateSelection() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let dmg = try f.file("App.DMG", "disk image")
        try f.file("installer.pkg", "package")
        try f.file("nested/archive.tar.gz", "archive")
        try f.file("notes.txt", "personal notes")
        try f.file("transfer.crdownload", "partial")
        let old = Date().addingTimeInterval(-400 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dmg.path)
        let inventory = try f.scan()
        #expect(inventory.files.count == 5)
        #expect(Set(inventory.files.map(\.kind)).count == 5)
        #expect(DownloadKind.allCases.reduce(0) { $0 + inventory.bytes(kind: $1) } == inventory.bytes())
        let largeOld = inventory.files(matching: .init(kind: .diskImage, minimumBytes: 5, age: .year))
        #expect(largeOld.count == 1)
        let plan = try f.plan(inventory, Set(largeOld.map(\.id)))
        #expect(plan.items.count == 1 && plan.logicalBytes == Data("disk image".utf8).count)
        #expect(plan.items.allSatisfy { $0.safety == .userData && $0.category == .downloads })
    }

    @Test func namesEncodingAndSourcesNeverEstablishAnExactDuplicate() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let first = try f.file("one/Installer.dmg", "same name A")
        let other = try f.file("two/Installer.dmg", "same name B")
        try f.file("composed.txt", "é")
        try f.file("decomposed.txt", "e\u{301}")
        try f.file("archive.zip", "same meaningful data compressed differently")
        try f.origin(first, ["https://example.invalid/download"])
        try f.origin(other, ["https://example.invalid/download"])
        #expect(try f.scan().duplicates.isEmpty)
    }

    @Test func fullHashDistinguishesMatchingSizeAndPartialPrefix() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let prefix = Data(repeating: 97, count: 65_536)
        try f.file("different-a.dmg", data: prefix + Data([1]))
        try f.file("different-b.dmg", data: prefix + Data([2]))
        try f.file("copy-a.pkg", data: prefix + Data([3]))
        try f.file("nested/copy-b.zip", data: prefix + Data([3]))
        let inventory = try f.scan()
        #expect(inventory.duplicates.count == 1)
        #expect(inventory.duplicates[0].items.count == 2)
        #expect(inventory.duplicates[0].items.allSatisfy { $0.ruleID == "duplicates.sha256" && $0.category == .downloads })
        #expect(inventory.report.items.filter { $0.ruleID == "manual.folder-review" }.count == 2)
    }

    @Test func deliberateKeeperSelectionUsesCompleteGroupAndCoreKeepOnePolicy() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        for name in ["A.dmg", "B.dmg", "nested/C.dmg"] { try f.file(name, "same content") }
        let inventory = try f.scan()
        let group = try #require(inventory.duplicates.first)
        let keeper = group.items[1]
        let selected = try inventory.keeperSelection(groupID: group.id, keeperID: keeper.id)
        #expect(selected.count == 2 && !selected.contains(keeper.id))
        let plan = try f.plan(inventory, selected)
        try plan.preflight(home: f.home, context: CleanupExecutionContext())
        #expect(plan.logicalBytes == 2 * group.items[0].bytes)
        #expect(throws: (any Error).self) { try f.plan(inventory, Set(group.items.map(\.id))) }
        #expect(throws: (any Error).self) { try inventory.keeperSelection(groupID: group.id, keeperID: "not-a-member") }
    }

    @Test func changedKeeperBlocksAllMovesEvenWhenSizeAndTimestampAreRestored() async throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        try f.file("A.zip", "original"); try f.file("B.zip", "original")
        let inventory = try f.scan()
        let group = try #require(inventory.duplicates.first)
        let selected = try inventory.keeperSelection(groupID: group.id, keeperID: group.items[0].id)
        let plan = try f.plan(inventory, selected)
        let keeper = group.items[0].url
        let attributes = try FileManager.default.attributesOfItem(atPath: keeper.path)
        try Data("modified".utf8).write(to: keeper)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: keeper.path)
        let journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext() }) }
        #expect(await journal.snapshot().records.isEmpty)
        #expect(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    @Test func incompleteDirectoriesAndFilesAreNeverCandidatesOrDuplicateMembers() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        for name in ["file.part", "file.partial", "file.filepart", "file.crdownload", "Safari.download/chunk"] { try f.file(name, "same data") }
        try f.file("complete.zip", "same data")
        let inventory = try f.scan()
        #expect(inventory.files.filter { $0.kind == .incomplete }.count == 5)
        #expect(inventory.report.items.count == 1 && inventory.duplicates.isEmpty)
        #expect(!inventory.files.contains { $0.url.lastPathComponent == "chunk" })
        for file in inventory.files where file.kind == .incomplete {
            if case .unavailable = try DownloadPreviewReader.read(file) { } else { Issue.record("Incomplete file was previewed") }
        }
    }

    @Test func sourceMetadataIsOptionalBoundedAndNeverAFileOrURLAction() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let known = try f.file("known.txt", "text")
        let malformed = try f.file("malformed.txt", "other text")
        let tooLong = try f.file("long.txt", "more text")
        try f.file("unknown.txt", "missing metadata")
        try f.origin(known, ["https://example.invalid/file?x=1", "javascript:alert(1)\n"])
        try f.origin(malformed, ["wrong": "type"])
        try f.origin(tooLong, [String(repeating: "a", count: 3_000)])
        let inventory = try f.scan()
        #expect(inventory.files.first { $0.url == known }?.sources == ["https://example.invalid/file?x=1", "javascript:alert(1)"])
        #expect(inventory.files.filter { $0.url != known }.allSatisfy { $0.sources.isEmpty })
        #expect(inventory.report.items.count == 4)
    }

    @Test func textPreviewIsBoundedPlainAndRejectsBinaryOrUnsupportedContent() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        try f.file("plain.txt", "https://example.invalid is plain text\n<not rendered>")
        try f.file("large.txt", data: Data(repeating: 97, count: 70_000))
        try f.file("bad.txt", data: Data([97, 0, 98]))
        try f.file("invalid.txt", data: Data([97, 255]))
        try f.file("installer.dmg", "not opened")
        try f.file("web.html", "<script>alert(1)</script>")
        let inventory = try f.scan()
        for file in inventory.files {
            let preview = try DownloadPreviewReader.read(file)
            if file.url.lastPathComponent == "plain.txt" {
                if case .text(let value, let truncated) = preview { #expect(value.contains("<not rendered>") && !truncated) } else { Issue.record("Expected text preview") }
            } else if file.url.lastPathComponent == "large.txt" {
                if case .text(let value, let truncated) = preview { #expect(value.utf8.count == 65_536 && truncated) } else { Issue.record("Expected truncated text") }
            } else if case .unavailable = preview { } else { Issue.record("Unsupported content was previewed") }
        }
    }

    @Test func rasterPreviewUsesSmallInMemoryPNGOnly() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let pixels = [UInt8](repeating: 120, count: 4 * 2 * 2)
        let data = Data(pixels)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        try f.file("picture.png", data: encoded as Data)
        try f.file("fake.png", "unsupported content")
        for file in try f.scan().files {
            if file.url.lastPathComponent == "picture.png" {
                if case .png(let value) = try DownloadPreviewReader.read(file) { #expect(!value.isEmpty) } else { Issue.record("Expected raster preview") }
            } else if case .unavailable = try DownloadPreviewReader.read(file) { } else { Issue.record("Expected unavailable preview") }
        }
    }

    @Test func changedPreviewIgnoredScopesLinksAndProviderChangesAreBlocked() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let path = try f.file("notes.txt", "personal text")
        try f.file("nested/keep.txt", "do not inspect")
        let inventory = try f.scan()
        let file = try #require(inventory.files.first { $0.url == path })
        #expect(try f.scan(ignored: [f.root.path]).report.items.isEmpty)
        #expect(try !f.scan(ignored: [f.root.appendingPathComponent("nested").path]).report.items.contains { $0.url.lastPathComponent == "keep.txt" })
        try FilesystemAccess.$restriction.withValue({ url in url.path == path.path ? .providerManaged : .local }) { () throws -> Void in
            #expect(throws: (any Error).self) { try DownloadPreviewReader.read(file) }
            let restricted = try f.scan()
            #expect(!restricted.report.items.contains { $0.url == path })
        }
        try Data("changed text".utf8).write(to: path)
        #expect(throws: (any Error).self) { try DownloadPreviewReader.read(file) }
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("link.txt"), withDestinationURL: path)
        try FileManager.default.linkItem(at: path, to: f.root.appendingPathComponent("hardlink.txt"))
        #expect(try !f.scan().report.items.contains { ["notes.txt", "link.txt", "hardlink.txt"].contains($0.url.lastPathComponent) })
    }

    @Test func authorizationAndStaleReviewMatchManualStoragePolicy() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let path = try f.file("notes.txt", "personal text")
        let inventory = try f.scan()
        #expect(throws: (any Error).self) { try inventory.reviewPlan(ids: [path.path], authorizedRoots: [], home: f.home) }
        #expect(throws: (any Error).self) { try inventory.reviewPlan(ids: [path.path], authorizedRoots: [f.root], ignoredPaths: [path.path], home: f.home) }
        #expect(throws: (any Error).self) { try inventory.reviewPlan(ids: ["forged"], authorizedRoots: [f.root], home: f.home) }
        try Data("changed".utf8).write(to: path)
        #expect(throws: (any Error).self) { try f.plan(inventory, [path.path]) }
    }

    @Test func ordinaryFileMovesAndRestoreNeverOverwriteRecreatedDownloads() async throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let path = try f.file("offline.dmg", "irreplaceable old installer")
        try f.file("personal.txt", "keep")
        let inventory = try f.scan()
        let journal = try f.journal()
        let records = try await journal.execute(f.plan(inventory, [path.path]), context: { CleanupExecutionContext() })
        let record = try #require(records.first)
        #expect(record.planSource == .downloads)
        try f.file("offline.dmg", "new download")
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(try String(contentsOf: path, encoding: .utf8) == "new download")
        try FileManager.default.removeItem(at: path)
        try await f.journal().restore(record)
        #expect(try String(contentsOf: path, encoding: .utf8) == "irreplaceable old installer")
        #expect(try String(contentsOf: f.root.appendingPathComponent("personal.txt"), encoding: .utf8) == "keep")
    }

    @Test func directlyChosenPartialRootsAndStaleSnapshotsCannotAuthorizeReview() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        try f.file("Safari.download/chunk", "partial content")
        #expect(throws: (any Error).self) { try DownloadsScanner.scan(root: f.root.appendingPathComponent("Safari.download")) }
        let path = try f.file("old.txt", "valuable data")
        var inventory = try f.scan()
        let original = try #require(inventory.report.items.first)
        let stale = CleanupItem(url: original.url, bytes: original.bytes, category: original.category, safety: original.safety,
            explanation: original.explanation, consequence: original.consequence, ruleID: original.ruleID, ownerBundleID: nil,
            identity: original.identity, scannedAt: Date().addingTimeInterval(-1_900))
        inventory.report.items = [stale]
        #expect(throws: (any Error).self) { try f.plan(inventory, [path.path]) }
    }

    @Test func currentIgnoreRulesAndReplacedParentsInvalidateReviewedMoves() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let path = try f.file("nested/A.zip", "archive")
        try f.file("nested/B.zip", "archive")
        let inventory = try f.scan()
        let group = try #require(inventory.duplicates.first)
        #expect(throws: (any Error).self) { try inventory.keeperSelection(groupID: group.id, keeperID: group.items[0].id, ignoredPaths: [group.items[0].id]) }
        let plan = try f.plan(inventory, [path.path])
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext(ignoredPaths: [group.items[1].id])) }
        try FileManager.default.moveItem(at: f.root.appendingPathComponent("nested"), to: f.root.appendingPathComponent("moved"))
        try f.file("nested/A.zip", "archive")
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext()) }
    }

    @Test func ignoredProviderSubtreesAreNeverEnteredAndLimitsRemainExplicit() throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        let ignored = f.root.appendingPathComponent("Ignored")
        try f.file("Ignored/blocked.txt", "do not read")
        try f.file("read.txt", "read locally")
        try FilesystemAccess.$restriction.withValue({ url in Filesystem.isWithin(url, root: ignored) ? .providerManaged : .local }) { () throws -> Void in
            let inventory = try f.scan(ignored: [ignored.path])
            #expect(inventory.files.count == 1 && inventory.report.items.count == 1)
            #expect(inventory.report.coverage.contains { $0.ruleID == "downloads.ignored" })
            #expect(!inventory.report.coverage.contains { $0.accessCapability == .providerManaged })
        }
        #expect(throws: (any Error).self) { try DownloadsScanner.scan(root: f.root, limit: 1) }
    }

    @Test func scanEngineAndCancellationUseCommonLifecycle() async throws {
        let f = try DownloadsFixture(); defer { f.remove() }
        try f.file("file.zip")
        let result = try await ScanEngine.run(.init(.downloads, root: f.root))
        #expect(result.downloadsInventory?.files.count == 1)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try DownloadsScanner.scan(root: f.root) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
