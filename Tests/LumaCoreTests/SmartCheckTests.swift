import Foundation
import Testing
@testable import LumaCore

private actor SmartGate {
    var open = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { open = true; let saved = waiters; waiters = []; for waiter in saved { waiter.resume() } }
}

@MainActor private func waitForSmart(_ condition: () -> Bool) async {
    for _ in 0..<20_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Smart Check did not settle after releasing its fixture worker")
}

@Suite("Progressive Smart Check") @MainActor struct SmartCheckTests {
    @Test func stopFromCompletionCallbackDoesNotReviveOrPublishLaterChecks() async {
        let controller = ScanController(), request = ScanRequest(.overview)
        controller.onComplete = { [weak controller] snapshot in
            if snapshot.request.target == .generatedData { controller?.cancel() }
        }
        controller.start(request) { emit in
            try await SmartCheck.run(request, emit: emit) { _, _ in ScanResult() }
        }
        await waitForSmart { !controller.isBusy }
        #expect(controller.session?.phase == .cancelled)
        #expect(controller.snapshots[.generatedData] != nil)
        #expect(controller.snapshots[.applications] == nil)
        #expect(controller.snapshots[.overview] == nil)
    }

    @Test func unauthorizedSubcheckScopeCannotGainSnapshotAuthority() async {
        let controller = ScanController(), request = ScanRequest(.overview)
        controller.start(request) { emit in
            emit(.checkCompleted(ScanSnapshot(sessionID: UUID(), request: .init(.downloads, root: URL(fileURLWithPath: "/unauthorized")), finishedAt: Date(), result: ScanResult())))
            return ScanResult()
        }
        await waitForSmart { !controller.isBusy }
        #expect(controller.snapshots[.downloads] == nil)
        #expect(controller.snapshots[.overview] != nil)
    }

    @Test func optionalScopesRequireExplicitAuthorizationAndPreserveIgnores() {
        let root = URL(fileURLWithPath: "/fixture/chosen")
        let request = ScanRequest(.overview, ignoredPaths: ["/fixture/keep"], smartScopes: [.downloads: root, .storage: root])
        let children = SmartCheck.requests(for: request)
        #expect(children.map(\.target) == [.generatedData, .applications, .leftovers, .downloads])
        #expect(children.last?.root == root)
        #expect(children.allSatisfy { $0.ignoredPaths == request.ignoredPaths })
        #expect(SmartCheck.requests(for: .init(.overview)).count == 3)
    }

    @Test func completedStageIsAvailableWhileDeepCheckIsStillRunning() async throws {
        let gate = SmartGate(), entered = SmartGate(), controller = ScanController()
        let root = URL(fileURLWithPath: "/fixture/downloads")
        let request = ScanRequest(.overview, smartScopes: [.downloads: root])
        controller.start(request) { emit in
            try await SmartCheck.run(request, emit: emit) { child, _ in
                if child.target == .downloads { await entered.release(); await gate.wait() }
                return ScanResult()
            }
        }
        await entered.wait(); controller.poll()
        #expect(controller.isBusy)
        #expect(controller.snapshots[.generatedData]?.sessionID == controller.session?.id)
        #expect(controller.snapshots[.applications] != nil)
        #expect(controller.snapshots[.downloads] == nil)
        let time = try #require(controller.snapshots[.generatedData]?.finishedAt)
        await gate.release(); await waitForSmart { !controller.isBusy }
        #expect(controller.snapshots[.downloads]?.request.root == root)
        #expect(controller.snapshots[.generatedData]?.finishedAt == time)
        #expect(controller.snapshots[.overview]?.result.report.items.isEmpty == true)
    }

    @Test func failedCategoryDoesNotPreventLaterChecksOrClaimHealthy() async throws {
        let controller = ScanController(), request = ScanRequest(.overview)
        controller.start(request) { emit in
            try await SmartCheck.run(request, emit: emit) { child, _ in
                if child.target == .generatedData { throw LumaError.rejected("Access denied fixture") }
                return ScanResult()
            }
        }
        await waitForSmart { !controller.isBusy }
        let failed = try #require(controller.snapshots[.generatedData])
        #expect(SmartCheck.status(snapshot: failed, startedAt: nil, phase: .completed) == "Could not check")
        #expect(failed.result.report.items.isEmpty)
        #expect(controller.snapshots[.leftovers] != nil)
        #expect(controller.session?.phase == .completedWithExclusions)
    }

    @Test func deniedAndStaleAndUnrunResultsAreDistinct() async throws {
        let controller = ScanController()
        controller.start(.init(.generatedData)) { _ in
            var report = ScanReport(); report.isComplete = false
            report.coverage = [ScanCoverage(ruleID: "fixture", title: "Denied", path: "/fixture", category: .caches,
                state: .blocked, bytes: 0, detail: "Access needed")]
            return ScanResult(report: report)
        }
        await waitForSmart { !controller.isBusy }
        let snapshot = try #require(controller.snapshots[.generatedData])
        #expect(SmartCheck.status(snapshot: snapshot, startedAt: nil, phase: nil) == "Limited coverage")
        #expect(SmartCheck.status(snapshot: snapshot, startedAt: nil, phase: nil, now: snapshot.finishedAt.addingTimeInterval(901)) == "Stale · check again")
        #expect(SmartCheck.status(snapshot: snapshot, startedAt: snapshot.finishedAt.addingTimeInterval(1), phase: .cancelled) == "Cancelled · not checked")
        #expect(SmartCheck.status(snapshot: nil, startedAt: nil, phase: nil) == "Not checked")
        #expect(SmartCheck.status(snapshot: nil, startedAt: nil, phase: .timedOut) == "Timed out · not checked")
    }

    @Test func cancellationRetainsCompletedChecksAndRejectsLateResults() async throws {
        let controller = ScanController(), entered = SmartGate(), release = SmartGate()
        let request = ScanRequest(.overview)
        controller.start(request) { emit in
            try await SmartCheck.run(request, emit: emit) { child, _ in
                if child.target == .applications { await entered.release(); await release.wait() }
                return ScanResult()
            }
        }
        await entered.wait(); controller.poll()
        let completed = try #require(controller.snapshots[.generatedData])
        controller.cancel()
        #expect(controller.isBusy)
        await release.release(); await waitForSmart { !controller.isBusy }
        #expect(controller.session?.phase == .cancelled)
        #expect(controller.snapshots[.generatedData]?.finishedAt == completed.finishedAt)
        #expect(controller.snapshots[.applications] == nil)
        #expect(controller.snapshots[.overview] == nil)
    }

    @Test func replacementWaitsAndNeverAttributesOldChecksToNewScope() async throws {
        let controller = ScanController(), entered = SmartGate(), release = SmartGate()
        let old = ScanRequest(.overview, smartScopes: [.downloads: URL(fileURLWithPath: "/fixture/old")])
        controller.start(old) { emit in
            try await SmartCheck.run(old, emit: emit) { _, _ in
                await entered.release(); await release.wait(); return ScanResult()
            }
        }
        await entered.wait()
        let new = ScanRequest(.overview, smartScopes: [.downloads: URL(fileURLWithPath: "/fixture/new")])
        controller.start(new) { emit in
            try await SmartCheck.run(new, emit: emit) { _, _ in ScanResult() }
        }
        #expect(controller.session?.request.smartScopes[.downloads] == old.smartScopes[.downloads])
        #expect(controller.queuedRequest?.smartScopes[.downloads] == new.smartScopes[.downloads])
        await release.release(); await waitForSmart { !controller.isBusy }
        #expect(controller.snapshots[.downloads]?.request.root == new.smartScopes[.downloads])
        #expect(controller.snapshots[.downloads]?.sessionID == controller.snapshots[.overview]?.sessionID)
    }

    @Test func overlappingFindingsNeverBecomeAggregateSavingsOrCandidates() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/smart-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("overlap")
        try Data("same bytes across views".utf8).write(to: file)
        let item = try Filesystem.item(file, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual")
        let controller = ScanController(), request = ScanRequest(.overview, smartScopes: [.developerProjects: root, .downloads: root])
        controller.start(request) { emit in
            try await SmartCheck.run(request, emit: emit) { _, _ in
                var report = ScanReport(); report.items = [item]; return ScanResult(report: report)
            }
        }
        await waitForSmart { !controller.isBusy }
        #expect(controller.snapshots[.overview]?.result.report.items.isEmpty == true)
        #expect(controller.snapshots[.generatedData]?.result.report.items.count == 1)
        #expect(controller.snapshots[.downloads]?.result.report.items.count == 1)
        controller.invalidateSnapshots(for: [.overview, .generatedData, .applications, .leftovers, .developerProjects, .downloads])
        #expect(controller.snapshots.isEmpty)
    }
}
