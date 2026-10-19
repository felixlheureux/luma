import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import LumaCore

private final class FeedbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    func append(_ text: String) { lock.withLock { calls.append(text) } }
    var values: [String] { lock.withLock { calls } }
}

private struct FeedbackFixture {
    let home: URL
    var trash: URL { home.appendingPathComponent(".Trash") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/feedback-\(UUID())")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    func file(_ path: String, data: Data = Data("fixture".utf8)) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func leftovers() async throws -> [CleanupItem] {
        try await LeftoverScanner(home: home, applicationRoots: [home.appendingPathComponent("Applications")], lookup: { _ in false }).scan().items
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Cleanup feedback and application presentation") struct CleanupFeedbackTests {
    @Test func stoppingAfterOneValidatedItemStillMovesNothing() async throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        let a = try f.file("Downloads/a"), b = try f.file("Downloads/b")
        let items = try [a, b].map {
            try Filesystem.item($0, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        }
        let plan = try CleanupPlan(items: items, authorizedRoots: [f.home.appendingPathComponent("Downloads")])
        let journal = try CleanupJournal(home: f.home, trashMover: { _ in throw LumaError.rejected("Fixture must stop before its mover") })
        let task = Task {
            try await journal.execute(plan, context: { CleanupExecutionContext() }, onProgress: { value in
                if value.phase == .validating && value.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let snapshot = await journal.snapshot()
        #expect(snapshot.records.isEmpty && snapshot.unresolved.isEmpty)
        #expect(snapshot.sessions.first?.phase == .stopped)
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
    }

    @Test func sharedPreflightInventoryStillRechecksEveryMoveAndReportsValidation() async throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        _ = try f.file("Library/Caches/org.lumatest.feedback/cache")
        _ = try f.file("Library/Preferences/org.lumatest.feedback.plist")
        let items = try await f.leftovers()
        #expect(items.count == 2)
        let plan = try CleanupPlan(items: items, source: .leftovers)
        let inventories = FeedbackLog(), progress = FeedbackLog(), details = FeedbackLog()
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = f.trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        try await ApplicationPresence.$inventoryObserver.withValue({ owner in inventories.append(owner ?? "all") }) {
            _ = try await journal.execute(plan, context: { CleanupExecutionContext(runningBundleIDs: ["org.unrelated.running"]) },
                onProgress: { value in progress.append("\(value.phase.rawValue):\(value.completed)") },
                onDetail: { details.append($0.phase) })
        }
        // One inventory for whole-plan preflight, one fresh inventory per move.
        // No redundant owner-specific traversal for an owner already absent.
        #expect(inventories.values == ["all", "all", "all"])
        #expect(progress.values.contains("validating:1"))
        #expect(progress.values.contains("validating:2"))
        #expect(details.values.contains("Verifying current files"))
        #expect(details.values.contains("Moving to macOS Trash"))
        #expect(details.values.contains("Verifying moved files"))
        #expect(await journal.snapshot().records.count == 2)
    }

    @Test func reinstallationAtFinalCheckpointStillBlocksTrash() async throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        _ = try f.file("Library/Caches/org.lumatest.feedback/cache")
        let items = try await f.leftovers()
        let plan = try CleanupPlan(items: items, source: .leftovers)
        let moves = FeedbackLog()
        let journal = try CleanupJournal(home: f.home, trashMover: { source in moves.append(source.path); return source })
        await journal.setMutationCheckpoint {
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.lumatest.feedback"], format: .xml, options: 0)
            _ = try f.file("Applications/Reinstalled.app/Contents/Info.plist", data: data)
        }
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext() }) }
        #expect(moves.values.isEmpty)
        #expect(FileManager.default.fileExists(atPath: items[0].url.path))
        let snapshot = await journal.snapshot()
        #expect(snapshot.records.isEmpty && snapshot.unresolved.isEmpty)
    }

    @Test @MainActor func remainingSnapshotKeepsTimeAndScopeButDropsChangedOverlaps() async throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        let a = try f.file("Library/Caches/org.lumatest.a/child")
        let b = try f.file("Library/Preferences/org.lumatest.b.plist")
        let items = try [a.deletingLastPathComponent(), a, b].map {
            try Filesystem.item($0, category: .related, safety: .review, explanation: "fixture", consequence: "fixture", rule: "fixture")
        }
        let controller = ScanController()
        controller.start(.init(.leftovers)) { _ in var report = ScanReport(); report.items = items; return ScanResult(report: report) }
        for _ in 0..<10_000 { if !controller.isBusy { break }; await Task.yield() }
        let before = try #require(controller.snapshots[.leftovers])
        let remaining = try #require(controller.retainRemainingLeftovers(excluding: [a]))
        #expect(remaining.result.report.items.map(\.url) == [b])
        #expect(remaining.finishedAt == before.finishedAt && remaining.request.scope == before.request.scope)
        #expect(remaining.sessionID != before.sessionID)
        #expect(!remaining.result.report.notices.isEmpty)
    }

    @Test func leftoverOwnersDefaultToIdentifierOrderWithStableItemOrder() throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        let data = try ["com.zeta.app", "com.alpha.second", "com.alpha.first"].map { owner -> CleanupItem in
            let url = try f.file("Library/Caches/" + owner)
            return try Filesystem.item(url, category: .caches, safety: .review, explanation: "fixture", consequence: "fixture", rule: "fixture", owner: owner)
        }
        #expect(LeftoverGroup.groups(for: data).map(\.id) == ["com.alpha.first", "com.alpha.second", "com.zeta.app"])
        #expect(LeftoverGroup.groups(for: data, search: "com.alpha").count == 2)
    }

    @Test func localIconsAreBoundedAndProviderOrUnsafeResourcesUseFallback() async throws {
        let f = try FeedbackFixture(); defer { f.remove() }
        let bundle = f.home.appendingPathComponent("Applications/Fixture.app")
        let metadata: [String: Any] = ["CFBundleIdentifier": "org.lumatest.icon", "CFBundleIconFile": "Fixture.png"]
        _ = try f.file("Applications/Fixture.app/Contents/Info.plist", data: PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0))
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.2, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let resource = try f.file("Applications/Fixture.app/Contents/Resources/Fixture.png", data: png as Data)
        let loaded = try ApplicationIcon.png(bundle: bundle, metadata: metadata)
        let image = try #require(loaded)
        #expect(image.count <= 131_072)
        #expect(try ApplicationScanner.restoredRecord(at: bundle).iconPNG == image)
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconName": "Fixture.png"]) == nil)
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconName": "AssetIcon", "CFBundleIconFile": "Fixture.png"]) == image)
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconName": "AssetIcon", "CFBundleIconFile": "Missing.png"]) == nil)
        // A bounded loose ICNS representation, with the extension omitted in metadata.
        var icns = Data("icns".utf8)
        var length = UInt32(png.length + 16).bigEndian
        withUnsafeBytes(of: &length) { icns.append(contentsOf: $0) }
        icns.append(Data("icp6".utf8))
        length = UInt32(png.length + 8).bigEndian
        withUnsafeBytes(of: &length) { icns.append(contentsOf: $0) }
        icns.append(png as Data)
        _ = try f.file("Applications/Fixture.app/Contents/Resources/Loose.icns", data: icns)
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconFile": "Loose"]) != nil)
        let result = try ApplicationScanner.inventory(home: f.home, roots: [bundle.deletingLastPathComponent()])
        #expect(result.applications.first?.iconPNG != nil)
        try FilesystemAccess.$restriction.withValue({ $0.path == resource.path ? .providerManaged : .local }) { () throws -> Void in
            let restricted = try ApplicationIcon.png(bundle: bundle, metadata: metadata)
            #expect(restricted == nil)
            #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconName": "AssetIcon", "CFBundleIconFile": "Fixture.png"]) == nil)
        }
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: ["CFBundleIconFile": "../private.png"]) == nil)
        try FileManager.default.removeItem(at: resource)
        let external = try f.file("Personal.png", data: png as Data)
        try FileManager.default.createSymbolicLink(at: resource, withDestinationURL: external)
        #expect(try ApplicationIcon.png(bundle: bundle, metadata: metadata) == nil)
    }
}
