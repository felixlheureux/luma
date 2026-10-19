import Foundation
import Testing
@testable import LumaCore

private struct UninstallFixture {
    let home: URL
    let app: ApplicationRecord
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/uninstall-\(UUID())")
        app = ApplicationRecord(url: home.appendingPathComponent("Applications/Fixture.app"), name: "Uninstall Fixture", bundleID: "org.lumatest.uninstall", version: "1", bytes: 0)
        try install("Applications/Fixture.app")
        try file("Library/Caches/org.lumatest.uninstall/cache", "cache")
        try file("Library/Logs/org.lumatest.uninstall/log", "diagnostic")
        try file("Library/Preferences/org.lumatest.uninstall.plist", "settings")
        try file("Library/Saved Application State/org.lumatest.uninstall.savedState/window", "state")
        try file("Library/Application Support/org.lumatest.uninstall/document", "valuable document")
        try file("Library/Containers/org.lumatest.uninstall/document", "container document")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    }
    func install(_ path: String) throws {
        try file(path + "/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.lumatest.uninstall</string></dict></plist>")
    }
    func file(_ path: String, _ value: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }
    func withInventory<T>(_ operation: () throws -> T) rethrows -> T {
        try ApplicationUninstall.$fixtureInstallationRoots.withValue([home.appendingPathComponent("Applications"), home.appendingPathComponent("OtherApplications")]) {
            try ApplicationUninstall.$fixtureRegisteredURLs.withValue([]) { try operation() }
        }
    }
    func withInventory<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await ApplicationUninstall.$fixtureInstallationRoots.withValue([home.appendingPathComponent("Applications"), home.appendingPathComponent("OtherApplications")]) {
            try await ApplicationUninstall.$fixtureRegisteredURLs.withValue([]) { try await operation() }
        }
    }
    func journal(fail: URL? = nil) throws -> CleanupJournal {
        let trash = home.appendingPathComponent(".Trash")
        return try CleanupJournal(home: home, trashMover: { source in
            if source == fail { throw LumaError.rejected("Injected failure") }
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Direct application uninstall") struct ApplicationUninstallTests {
    @Test func exclusiveContractAndRoundTrip() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        try await f.withInventory {
            let plan = try ApplicationUninstall.prepare(f.app, home: f.home)
            #expect(plan.items.count == 5)
            #expect(plan.items.last?.url == f.app.url)
            #expect(!plan.items.contains { $0.url.path.contains("Application Support") || $0.url.path.contains("Containers") })
            let journal = try f.journal()
            let records = try await journal.execute(plan, context: { CleanupExecutionContext(processPaths: []) })
            #expect(records.count == 5)
            #expect(await journal.snapshot().sessions.first?.phase == .completed)
            #expect(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/org.lumatest.uninstall/document").path))
            let review = try await journal.reviewUndo(sessionID: plan.id)
            try await journal.undo(review)
            #expect(await journal.snapshot().records.allSatisfy(\.restored))
            #expect(try ApplicationScanner.restoredRecord(at: f.app.url).bundleID == f.app.bundleID)
        }
    }

    @Test func sameIDCopiesAndUnknownMultiplicityRetainAllData() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        try await f.withInventory {
            try f.install("OtherApplications/Copy.app")
            #expect(try ApplicationUninstall.multiplicity(app: f.app, home: f.home) == .shared)
            let plan = try ApplicationUninstall.prepare(f.app, home: f.home)
            #expect(plan.items.count == 1)
            _ = try await f.journal().execute(plan, context: { CleanupExecutionContext(processPaths: []) })
            #expect(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("OtherApplications/Copy.app").path))
            #expect(FileManager.default.fileExists(atPath: f.home.appendingPathComponent("Library/Caches/org.lumatest.uninstall/cache").path))
        }
        let unknown = try UninstallFixture(); defer { unknown.remove() }
        try unknown.withInventory {
            try FileManager.default.createSymbolicLink(at: unknown.home.appendingPathComponent("Applications/Unknown.app"), withDestinationURL: unknown.home.appendingPathComponent("absent"))
            #expect(try ApplicationUninstall.multiplicity(app: unknown.app, home: unknown.home) == .unknown)
            #expect(try ApplicationUninstall.prepare(unknown.app, home: unknown.home).items.count == 1)
        }
    }

    @Test func newCopyAfterPlanBlocksRelatedDataAndRunningProcessesFailClosed() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        try await f.withInventory {
            let plan = try ApplicationUninstall.prepare(f.app, home: f.home)
            try f.install("OtherApplications/Reinstalled.app")
            await #expect(throws: (any Error).self) { try await f.journal().execute(plan, context: { CleanupExecutionContext(processPaths: []) }) }
            #expect(FileManager.default.fileExists(atPath: f.app.url.path))
        }
        let running = try UninstallFixture(); defer { running.remove() }
        try await running.withInventory {
            for context in [CleanupExecutionContext(), CleanupExecutionContext(processPaths: [running.app.url.appendingPathComponent("Contents/MacOS/helper").path]), CleanupExecutionContext(runningBundleIDs: [running.app.bundleID], processPaths: [])] {
                let plan = try ApplicationUninstall.prepare(running.app, home: running.home)
                let journal = try running.journal()
                await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { context }) }
                #expect(await journal.snapshot().sessions.last?.phase == .failed)
            }
        }
    }

    @Test func partialFailureKeepsBundleAndRecordsCompletedData() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        try await f.withInventory {
            let plan = try ApplicationUninstall.prepare(f.app, home: f.home)
            let journal = try f.journal(fail: plan.items[1].url)
            await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext(processPaths: []) }) }
            let snapshot = try await journal.reconcile()
            #expect(snapshot.sessions.first?.phase == .partial)
            #expect(snapshot.records.count == 1)
            #expect(FileManager.default.fileExists(atPath: f.app.url.path))
        }
    }

    @Test(arguments: ["manual", "generated", "residue"])
    func currentIgnoredChildBlocksEveryNormalTrashSource(_ source: String) async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        let path: String, ruleID: String, category: ItemCategory, safety: SafetyLevel, owner: String?
        switch source {
        case "manual":
            path = "Downloads/parent"; ruleID = "manual.folder-review"; category = .storage; safety = .userData; owner = nil
        case "generated":
            path = "Library/Developer/Xcode/DerivedData"; ruleID = Rules.generated[0].id; category = .developer; safety = .safe; owner = Rules.generated[0].owner
        default:
            path = "Library/Caches/org.lumatest.absent"; ruleID = "application.leftover.exact-identifier"; category = .related; safety = .review; owner = "org.lumatest.absent"
        }
        try f.file(path + "/child", "ignored content")
        let parent = f.home.appendingPathComponent(path)
        let child = parent.appendingPathComponent("child").path
        let item = try Filesystem.item(parent, category: category, safety: safety, explanation: "fixture", consequence: "fixture", rule: ruleID, owner: owner)
        let roots = [f.home.appendingPathComponent("Downloads")]
        #expect(throws: (any Error).self) { try CleanupPlan(items: [item], authorizedRoots: roots, ignoredPaths: [child]) }
        let plan = try CleanupPlan(items: [item], authorizedRoots: roots)
        let initial = CleanupExecutionContext(ignoredPaths: [child], activity: .init(tools: []))
        await #expect(throws: (any Error).self) { try await f.journal().execute(plan, context: { initial }) }
        let freshPlan = try CleanupPlan(items: [item], authorizedRoots: roots)
        let counter = UninstallContextCounter()
        let journal = try f.journal()
        await #expect(throws: (any Error).self) {
            try await journal.execute(freshPlan, context: {
                let attempt = await counter.next()
                return CleanupExecutionContext(ignoredPaths: attempt > 1 ? [child] : [], activity: .init(tools: []))
            })
        }
        #expect(await counter.value == 2)
        #expect(await journal.snapshot().records.isEmpty)
        #expect(FileManager.default.fileExists(atPath: child))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMA_UNINSTALL_BENCHMARK"] == "1"))
    func fixedFixtureTimings() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        for index in 0..<512 {
            try f.file("Applications/Fixture.app/Contents/Resources/file-\(index)", "app fixture")
            try f.file("Library/Application Support/org.lumatest.uninstall/file-\(index)", "retained fixture")
            try f.file("Library/Caches/org.lumatest.uninstall/file-\(index)", "cache fixture")
        }
        try await f.withInventory {
            for temperature in ["cold", "warm"] {
                let before = Date()
                let footprint = try ApplicationFootprintScanner.inspect(f.app, home: f.home).applicationFootprint!
                let items = footprint.entries.filter { [.bundle, .generated, .settings].contains($0.relationship.category) }.compactMap(\.item)
                let baseline = try CleanupPlan(items: items, source: .applications)
                let baselinePreparation = Date().timeIntervalSince(before)
                let after = Date()
                let direct = try ApplicationUninstall.prepare(f.app, home: f.home)
                let directPreparation = Date().timeIntervalSince(after)
                let contextStart = Date()
                _ = await CleanupExecutionContext.current()
                let oldContext = Date().timeIntervalSince(contextStart)
                let leanStart = Date()
                _ = await CleanupExecutionContext.current(checkingTools: false)
                let leanContext = Date().timeIntervalSince(leanStart)
                let validationContext = CleanupExecutionContext(runningBundleIDs: ["org.lumatest.unrelated"], processPaths: [])
                let baselineCounter = UninstallReadCounter()
                let oldValidationStart = Date()
                try ApplicationPresence.$inventoryObserver.withValue({ _ in baselineCounter.increment() }) {
                    try baseline.preflight(home: f.home, context: validationContext)
                }
                let baselineValidation = Date().timeIntervalSince(oldValidationStart)
                let directCounter = UninstallReadCounter()
                let newValidationStart = Date()
                try ApplicationPresence.$inventoryObserver.withValue({ _ in directCounter.increment() }) {
                    try direct.preflight(home: f.home, context: validationContext)
                }
                let directValidation = Date().timeIntervalSince(newValidationStart)
                #expect(baselineCounter.count == direct.items.count)
                #expect(directCounter.count == 1)
                print("UNINSTALL_BENCHMARK \(temperature) appFiles=513 cacheFiles=513 retainedFiles=513 baselinePrepare=\(baselinePreparation) directPrepare=\(directPreparation) baselineContext=\(oldContext) directContext=\(leanContext) baselinePreflight=\(baselineValidation) directPreflight=\(directValidation) ownerWalks=\(baselineCounter.count)->\(directCounter.count)")
                for variant in ["baseline", "direct"] {
                    let execution = try UninstallFixture(); defer { execution.remove() }
                    for index in 0..<512 {
                        try execution.file("Applications/Fixture.app/Contents/Resources/file-\(index)", "app fixture")
                        try execution.file("Library/Caches/org.lumatest.uninstall/file-\(index)", "cache fixture")
                    }
                    try await execution.withInventory {
                        let prepared = try ApplicationUninstall.prepare(execution.app, home: execution.home)
                        let plan = variant == "direct" ? prepared : try CleanupPlan(items: prepared.items, source: .applications)
                        let timings = UninstallReadCounter()
                        let trash = execution.home.appendingPathComponent(".Trash")
                        let journal = try CleanupJournal(home: execution.home, trashMover: { source in
                            let start = Date()
                            let destination = trash.appendingPathComponent(UUID().uuidString)
                            try FileManager.default.moveItem(at: source, to: destination)
                            timings.record("move", Date().timeIntervalSince(start))
                            return destination
                        })
                        let start = Date()
                        try await CleanupJournal.$persistenceObserver.withValue({ timings.record("persistence", $0) }) {
                            try await Filesystem.$inspectionObserver.withValue({ timings.record("tree", $0) }) {
                                _ = try await journal.execute(plan, context: { validationContext })
                            }
                        }
                        print("UNINSTALL_EXECUTION \(temperature) \(variant) total=\(Date().timeIntervalSince(start)) tree=\(timings.seconds("tree")) injectedNativeMove=\(timings.seconds("move")) journalPersistence=\(timings.seconds("persistence"))")
                    }
                }

            }
        }
    }

    @Test func ignoredDescendantsRejectParentsAtPlanPreflightAndFinalMove() async throws {
        let f = try UninstallFixture(); defer { f.remove() }
        try await f.withInventory {
            let plan = try ApplicationUninstall.prepare(f.app, home: f.home)
            let ignored = plan.items[0].url.appendingPathComponent("cache").path
            #expect(throws: (any Error).self) { try ApplicationUninstall.prepare(f.app, home: f.home, ignoredPaths: [ignored]) }
            let journal = try f.journal()
            let counter = UninstallContextCounter()
            await #expect(throws: (any Error).self) {
                try await journal.execute(plan, context: {
                    let count = await counter.next()
                    return CleanupExecutionContext(ignoredPaths: count > 1 ? [ignored] : [], processPaths: [])
                })
            }
            #expect(await journal.snapshot().records.isEmpty)
            #expect(await journal.snapshot().sessions.first?.phase == .failed)
        }
        // The central policy applies equally to manual, residue and generated parents.
        for path in ["Downloads/folder", "Library/Caches/org.lumatest.uninstall", "Applications/Fixture.app"] {
            let url = f.home.appendingPathComponent(path)
            #expect(throws: (any Error).self) { try SafetyEngine.validateIgnores(url, ignoredPaths: [url.appendingPathComponent("child").path]) }
        }
    }
}

private actor UninstallContextCounter {
    var value = 0
    func next() -> Int { value += 1; return value }
}

private final class UninstallReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var durations: [String: TimeInterval] = [:]
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
    func record(_ key: String, _ seconds: TimeInterval) { lock.withLock { durations[key, default: 0] += seconds } }
    func seconds(_ key: String) -> TimeInterval { lock.withLock { durations[key, default: 0] } }
}
