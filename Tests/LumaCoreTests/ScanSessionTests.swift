import Foundation
import Testing
@testable import LumaCore

private actor ScanGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let saved = waiters; waiters = []; for waiter in saved { waiter.resume() } }
}

private final class ScanEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ScanEvent] = []
    private var emitter: ScanEmitter?
    func append(_ event: ScanEvent) { lock.lock(); events.append(event); lock.unlock() }
    func values() -> [ScanEvent] { lock.lock(); defer { lock.unlock() }; return events }
    func capture(_ emit: @escaping ScanEmitter) { lock.lock(); emitter = emit; lock.unlock() }
    func send(_ event: ScanEvent) { lock.lock(); let saved = emitter; lock.unlock(); saved?(event) }
}

@MainActor private func settle(_ predicate: () -> Bool) async {
    for _ in 0..<20_000 {
        if predicate() { return }
        await Task.yield()
    }
    Issue.record("Scan state did not settle after the explicitly released worker.")
}

@Suite("Isolated scan sessions") @MainActor struct ScanSessionTests {
    @Test func mutationInvalidationDropsGeneratedEvidenceAndRetainsOtherFeatures() async throws {
        let controller = ScanController()
        controller.start(.init(.applications)) { _ in ScanResult() }
        await settle { !controller.isBusy }
        controller.start(.init(.generatedData)) { _ in ScanResult() }
        await settle { !controller.isBusy }
        #expect(controller.snapshots[.generatedData] != nil)
        controller.invalidateSnapshots(for: [.generatedData, .overview])
        #expect(controller.snapshots[.generatedData] == nil)
        #expect(controller.snapshots[.applications] != nil)
        #expect(controller.session == nil)
        controller.start(.init(.generatedData)) { _ in throw CancellationError() }
        await settle { !controller.isBusy }
        #expect(controller.snapshots[.generatedData] == nil)
        #expect(controller.snapshots[.applications] != nil)
    }

    @Test func cancelledWorkerCannotPublishEvenWhenItReturnsSuccess() async throws {
        let controller = ScanController(), started = ScanGate(), release = ScanGate(), log = ScanEventLog()
        controller.start(.init(.storage, root: URL(fileURLWithPath: "/fixture"))) { emit in
            log.capture(emit); emit(.progress(.init("Reading", current: "original")))
            await started.open(); await release.wait()
            emit(.notice("late exclusion"))
            return ScanResult()
        }
        await started.wait(); controller.poll()
        let original = try #require(controller.session?.id)
        controller.cancel()
        #expect(controller.isBusy)
        #expect(controller.session?.phase == .stopping(.cancelled))
        log.send(.progress(.init("late", current: "must not appear")))
        controller.poll()
        #expect(controller.session?.progress.current == "original")
        await release.open()
        await settle { !controller.isBusy }
        #expect(controller.session?.id == original)
        #expect(controller.session?.phase == .cancelled)
        #expect(controller.snapshots.isEmpty)
        #expect(controller.session?.preview.notices.isEmpty == true)
    }

    @Test func replacementIsBoundedAndLastQueuedRequestWins() async throws {
        let controller = ScanController(), started = ScanGate(), release = ScanGate(), secondStarted = ScanGate(), secondRelease = ScanGate()
        let old = ScanEventLog(), dropped = ScanEventLog()
        controller.start(.init(.applications)) { emit in
            old.capture(emit); await started.open(); await release.wait()
            return ScanResult()
        }
        await started.wait()
        controller.start(.init(.leftovers)) { _ in dropped.append(.notice("should never start")); return ScanResult() }
        controller.start(.init(.duplicates, root: URL(fileURLWithPath: "/new-scope"))) { _ in
            await secondStarted.open(); await secondRelease.wait(); return ScanResult()
        }
        #expect(controller.queuedRequest?.target == .duplicates)
        #expect(controller.session?.request.target == .applications)
        #expect(controller.session?.phase == .stopping(.replaced))
        await release.open(); await secondStarted.wait()
        let newID = try #require(controller.session?.id)
        old.send(.notice("old job cannot contaminate new results"))
        controller.poll()
        #expect(controller.isBusy)
        #expect(controller.session?.id == newID)
        #expect(controller.session?.request.root?.path == "/new-scope")
        #expect(controller.session?.preview.notices.isEmpty == true)
        #expect(controller.snapshots[.applications] == nil)
        #expect(controller.snapshots[.leftovers] == nil)
        #expect(dropped.values().isEmpty)
        await secondRelease.open(); await settle { !controller.isBusy }
        #expect(controller.snapshots[.duplicates]?.sessionID == newID)
    }

    @Test func cancellingWhileReplacementWaitsAlsoRemovesQueuedJob() async {
        let controller = ScanController(), started = ScanGate(), release = ScanGate(), log = ScanEventLog()
        controller.start(.init(.storage)) { _ in await started.open(); await release.wait(); return ScanResult() }
        await started.wait()
        controller.start(.init(.applications)) { _ in log.append(.notice("unexpected")); return ScanResult() }
        controller.cancel()
        #expect(controller.queuedRequest == nil)
        await release.open(); await settle { !controller.isBusy }
        #expect(log.values().isEmpty)
        #expect(controller.session?.phase == .cancelled)
    }

    @Test func stalledReadIsSeparateFromTimeoutAndBusyWaitsForWorker() async throws {
        let controller = ScanController(), started = ScanGate(), release = ScanGate(), log = ScanEventLog()
        let limits = ScanLimits(stallAfter: 1, idleTimeout: 10, totalTimeout: 30)
        controller.start(.init(.duplicates), limits: limits) { emit in
            log.capture(emit); await started.open(); await release.wait(); return ScanResult()
        }
        await started.wait()
        let start = try #require(controller.session?.startedAt)
        controller.poll(now: start.addingTimeInterval(2))
        #expect(controller.session?.stalled == true)
        #expect(controller.session?.phase == .running)
        log.send(.progress(.init("Reading full content", bytes: 1_048_576)))
        controller.poll()
        #expect(controller.session?.stalled == false)
        controller.poll(now: start.addingTimeInterval(40))
        #expect(controller.session?.phase == .stopping(.timedOut))
        #expect(controller.isBusy)
        await release.open(); await settle { !controller.isBusy }
        #expect(controller.session?.phase == .timedOut)
        #expect(controller.snapshots.isEmpty)
    }

    @Test func failedAndCancelledRefreshRetainThePreviousCompletedSnapshot() async throws {
        let controller = ScanController()
        let root = URL(fileURLWithPath: "/chosen/narrow-scope")
        let request = ScanRequest(.storage, root: root)
        controller.start(request) { _ in ScanResult() }
        await settle { !controller.isBusy }
        let snapshot = try #require(controller.snapshots[.storage])
        controller.start(request) { _ in throw LumaError.rejected("Access denied fixture") }
        await settle { !controller.isBusy }
        #expect(controller.session?.phase == .failed)
        #expect(controller.snapshots[.storage]?.sessionID == snapshot.sessionID)
        #expect(controller.session?.request.root == root)
        let started = ScanGate(), release = ScanGate()
        controller.start(request) { _ in await started.open(); await release.wait(); return ScanResult() }
        await started.wait(); controller.cancel(); await release.open(); await settle { !controller.isBusy }
        #expect(controller.snapshots[.storage]?.sessionID == snapshot.sessionID)
        #expect(controller.snapshots[.storage]?.finishedAt == snapshot.finishedAt)
    }

    @Test func completedExclusionsAreExplicitAndFeatureSnapshotsStayIndependent() async throws {
        let controller = ScanController()
        controller.start(.init(.applications)) { _ in ScanResult() }
        await settle { !controller.isBusy }
        let first = try #require(controller.snapshots[.applications])
        controller.start(.init(.storage)) { emit in
            var report = ScanReport(); report.isComplete = false; report.notices = ["One inaccessible folder"]
            emit(.notice(report.notices[0])); return ScanResult(report: report)
        }
        await settle { !controller.isBusy }
        #expect(controller.session?.phase == .completedWithExclusions)
        #expect(controller.snapshots[.storage]?.result.report.isComplete == false)
        #expect(controller.snapshots[.applications]?.sessionID == first.sessionID)
    }

    @Test func releasingControllerCancelsItsWorker() async {
        var controller: ScanController? = ScanController()
        weak var weakController = controller
        let started = ScanGate(), release = ScanGate(), log = ScanEventLog()
        controller?.start(.init(.storage)) { _ in
            await started.open(); await release.wait()
            if Task.isCancelled { log.append(.notice("cancelled")) }
            return ScanResult()
        }
        await started.wait()
        controller = nil
        #expect(weakController == nil)
        await release.open()
        await settle { !log.values().isEmpty }
    }

    @Test func previewMailboxIsBoundedAndNeverBecomesASnapshotBeforeFinish() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let item = try f.item(f.file())
        let controller = ScanController(), started = ScanGate(), release = ScanGate()
        controller.start(.init(.storage)) { emit in
            for index in 0..<2_000 { emit(.notice("skip \(index)")) }
            emit(.item(item)); await started.open(); await release.wait(); return ScanResult()
        }
        await started.wait(); controller.poll()
        #expect(controller.session?.preview.notices.count == 200)
        #expect(controller.session?.preview.truncated == true)
        #expect(controller.session?.preview.items.count == 1)
        #expect(controller.snapshots.isEmpty)
        controller.cancel(); await release.open(); await settle { !controller.isBusy }
        #expect(controller.snapshots.isEmpty)
    }
}

@Suite("Progressive scanner output") struct ProgressiveScannerTests {
    private func app(_ f: FilesystemEdgeFixture, name: String) throws -> URL {
        _ = try f.file("\(name).app/Contents/Info.plist", content: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.example.\(name)</string></dict></plist>")
        _ = try f.file("\(name).app/Contents/Resources/data")
        return f.downloads.appendingPathComponent("\(name).app")
    }

    @Test func applicationMetadataPrecedesAllBundleSizingAndUnknownIsNotZero() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try app(f, name: "Readable")
        let blocked = try app(f, name: "Blocked").appendingPathComponent("Contents/Resources")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        let log = ScanEventLog()
        let result = try ApplicationScanner.inventory(home: f.home, roots: [f.downloads], emit: { log.append($0) })
        let events = log.values()
        let firstSizing = try #require(events.firstIndex { if case .progress(let p) = $0 { return p.phase == "Measuring application bundles" }; return false })
        let rows = events.prefix(firstSizing).compactMap { event -> ApplicationRecord? in if case .application(let app) = event { return app }; return nil }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.sizeState == .pending })
        #expect(result.applications.first { $0.name == "Blocked" }?.sizeState == .unavailable)
        #expect(result.applications.first { $0.name == "Readable" }?.sizeState == .available)
        #expect(result.report.coverage.contains { $0.state == .blocked })
        #expect(!result.report.isComplete)
    }

    @Test func cancellingSizingPropagatesInsteadOfProducingUnavailableSize() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try app(f, name: "Example")
        let task = Task.detached {
            try ApplicationScanner.inventory(home: f.home, roots: [f.downloads], emit: { event in
                if case .progress(let pulse) = event, pulse.phase == "Measuring application bundles" {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func readableFolderItemsStreamDespiteDeniedSiblingAndRetryPreservesScope() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file("readable")
        _ = try f.file("denied/child")
        let denied = f.downloads.appendingPathComponent("denied")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
        let log = ScanEventLog()
        let first = try await FolderScanner(root: f.downloads, emit: { log.append($0) }).scan()
        #expect(first.items.count == 1)
        #expect(!first.isComplete)
        #expect(first.coverage.contains { $0.state == .blocked && $0.path == denied.path })
        #expect(log.values().contains { if case .item = $0 { true } else { false } })
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        let second = try await FolderScanner(root: f.downloads).scan()
        #expect(second.isComplete)
        #expect(second.items.count == 2)
        #expect(second.items.allSatisfy { $0.url.deletingLastPathComponent() == f.downloads })
    }

    @Test func footprintRetainsReadableRelationshipsAndStreamsCoverage() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let url = try app(f, name: "Footprint")
        let support = f.home.appendingPathComponent("Library/Application Support/org.example.Footprint")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("document".utf8).write(to: support.appendingPathComponent("data"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: support.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path) }
        let app = ApplicationRecord(url: url, name: "Footprint", bundleID: "org.example.Footprint", version: "1", bytes: 0, sizeState: .pending)
        let report = try ApplicationScanner.footprintReport(app, home: f.home)
        #expect(report.items.count == 1)
        #expect(report.items.first?.url == url)
        #expect(!report.isComplete)
        #expect(report.coverage.contains { $0.state == .blocked })
    }

    @Test func ownershipInventoryIgnoresExecutableNamesThatLookLikeBundles() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try app(f, name: "Owner")
        _ = try f.file("Owner.app/Contents/MacOS/helper.xpc", content: "executable fixture")
        let identifiers = try ApplicationPresence.bundleIdentifiers(home: f.home, roots: [f.downloads])
        #expect(identifiers.contains("org.example.owner"))
    }

    @Test func leftoverItemsAndCoverageStreamAfterOwnershipChecks() async throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        let cache = f.home.appendingPathComponent("Library/Caches/org.example.uninstalled.fixture")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("generated fixture".utf8).write(to: cache.appendingPathComponent("data"))
        let log = ScanEventLog()
        let report = try await LeftoverScanner(home: f.home, applicationRoots: [], lookup: { _ in false }, emit: { log.append($0) }).scan()
        #expect(report.items.count == 1)
        #expect(log.values().contains { if case .item(let item) = $0 { Filesystem.samePath(item.url, cache) } else { false } })
        #expect(log.values().contains { if case .coverage(let row) = $0 { row.state == .found && row.path == cache.path } else { false } })
    }

    @Test func duplicateGroupsStreamAfterFullHashesWithExplicitExclusions() throws {
        let f = try FilesystemEdgeFixture(); defer { f.remove() }
        _ = try f.file("first", content: "same content")
        _ = try f.file("second", content: "same content")
        try FileManager.default.createSymbolicLink(at: f.downloads.appendingPathComponent("link"), withDestinationURL: f.downloads.appendingPathComponent("first"))
        let log = ScanEventLog()
        let result = try DuplicateScanner(root: f.downloads, emit: { log.append($0) }).scanResult()
        #expect(result.duplicates.count == 1)
        #expect(log.values().contains { if case .duplicate = $0 { true } else { false } })
        #expect(log.values().contains { if case .progress(let p) = $0 { p.phase == "Verifying full content" && p.bytes > 0 } else { false } })
        #expect(!result.report.isComplete)
        #expect(result.report.coverage.contains { $0.state == .skipped })
    }
}
