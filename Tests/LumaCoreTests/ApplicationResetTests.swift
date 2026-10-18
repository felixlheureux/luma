import Foundation
import Testing
@testable import LumaCore

private struct ResetFixture {
    let home: URL
    let app: ApplicationRecord
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/reset-\(UUID())")
        app = ApplicationRecord(url: home.appendingPathComponent("Applications/Fixture.app"), name: "Reset Fixture", bundleID: "org.lumatest.reset", version: "1", bytes: 0)
        try file("Applications/Fixture.app/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.lumatest.reset</string></dict></plist>")
        try file("Applications/Fixture.app/Contents/Library/LoginItems/Helper.app/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.other.helper</string></dict></plist>")
        try file("Library/Caches/org.lumatest.reset/cache", "cache")
        try file("Library/Preferences/org.lumatest.reset.plist", "custom settings")
        try file("Library/Saved Application State/org.lumatest.reset.savedState/windows", "recovery state")
        try file("Library/Application Support/org.lumatest.reset/document", "valuable offline document")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, _ content: String) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func footprint() throws -> ApplicationFootprint {
        try #require(ApplicationFootprintScanner.inspect(app, home: home).applicationFootprint)
    }
    func plan(_ categories: Set<ResetCategory> = [.caches, .preferences, .savedState]) throws -> CleanupPlan {
        let items = try footprint().entries.filter { entry in
            ResetCategory.category(for: entry.relationship).map(categories.contains) ?? false
        }.compactMap(\.item)
        return try CleanupPlan(items: items, source: .applicationReset, resetApplication: app)
    }
    func journal(failing: URL? = nil) throws -> CleanupJournal {
        let trash = home.appendingPathComponent(".Trash")
        return try CleanupJournal(home: home, trashMover: { source in
            if source == failing { throw LumaError.rejected("Injected move failure") }
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

private actor ResetCounter {
    var count = 0
    func next() -> Int { count += 1; return count }
}

@Suite("Explicit application reset") struct ApplicationResetTests {
    @Test func groupsSeparateConsequencesAndBundleCannotEnterReset() throws {
        let f = try ResetFixture(); defer { f.remove() }
        let footprint = try f.footprint()
        #expect(Set(footprint.entries.compactMap { ResetCategory.category(for: $0.relationship) }).count == 4)
        let bundle = try #require(footprint.items.first { $0.category == .applications })
        #expect(throws: (any Error).self) { try CleanupPlan(items: [bundle], source: .applicationReset, resetApplication: f.app) }
        #expect(throws: (any Error).self) { try CleanupPlan(items: footprint.items, source: .applicationReset, resetApplication: f.app) }
        #expect(throws: (any Error).self) { try CleanupPlan(items: f.plan().items, source: .applicationReset) }
        #expect(try f.plan().items.count == 3)
        #expect(try f.plan([.otherData]).items.count == 1)
    }

    @Test func subsetRoundTripAcrossRestartPreservesBundleAndUnselectedDocuments() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan([.preferences, .savedState])
        let records = try await f.journal().execute(plan, context: { CleanupExecutionContext(processPaths: []) })
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.planSource == .applicationReset })
        #expect(try String(contentsOf: f.home.appendingPathComponent("Library/Application Support/org.lumatest.reset/document"), encoding: .utf8) == "valuable offline document")
        #expect(FileManager.default.fileExists(atPath: f.app.url.path))
        let restarted = try f.journal()
        #expect(await restarted.snapshot().sessions.first?.source == .applicationReset)
        for record in records {
            let contents = try Filesystem.inspect(record.trashed)
            try await restarted.restore(record)
            #expect(try Filesystem.inspect(record.original).0 == contents.0)
        }
        #expect(try String(contentsOf: f.home.appendingPathComponent("Library/Preferences/org.lumatest.reset.plist"), encoding: .utf8) == "custom settings")
        #expect(await restarted.snapshot().records.allSatisfy(\.restored))
    }

    @Test func recreatedDestinationNeverOverwritesOnRestore() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let journal = try f.journal()
        let records = try await journal.execute(f.plan([.preferences]), context: { CleanupExecutionContext(processPaths: []) })
        let record = try #require(records.first)
        try f.file("Library/Preferences/org.lumatest.reset.plist", "new settings")
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(try String(contentsOf: record.original, encoding: .utf8) == "new settings")
        #expect(try String(contentsOf: record.trashed, encoding: .utf8) == "custom settings")
    }

    @Test func runningHelpersUnknownActivityAndUnownedAppRejectWholePlan() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan()
        for context in [CleanupExecutionContext(runningBundleIDs: ["org.other.helper"], processPaths: []),
                        CleanupExecutionContext(runningBundleIDs: [f.app.bundleID], processPaths: []),
                        CleanupExecutionContext(processPaths: [f.app.url.appendingPathComponent("Contents/MacOS/background").path]),
                        CleanupExecutionContext()] {
            await #expect(throws: (any Error).self) { try await f.journal().execute(plan, context: { context }) }
            #expect(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
            #expect(try await f.journal().snapshot().records.isEmpty)
        }
        try FileManager.default.removeItem(at: f.app.url)
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext(processPaths: [])) }
    }

    @Test func cancellationAndStalePreflightLeaveEveryFileUnchanged() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan()
        let journal = try f.journal()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.execute(plan, context: { CleanupExecutionContext(processPaths: []) })
        }
        await #expect(throws: (any Error).self) { try await cancelled.value }
        #expect(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        let fresh = try f.plan()
        try Data("changed".utf8).write(to: f.home.appendingPathComponent("Library/Saved Application State/org.lumatest.reset.savedState/new"))
        await #expect(throws: (any Error).self) { try await journal.execute(fresh, context: { CleanupExecutionContext(processPaths: []) }) }
        #expect(fresh.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func laterFailureStopsAndKeepsDurableEarlierSuccess() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan()
        let journal = try f.journal(failing: plan.items[1].url)
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext(processPaths: []) }) }
        #expect(await journal.snapshot().sessions.first?.phase == .recoveryNeeded)
        let restarted = try f.journal()
        let snapshot = try await restarted.reconcile()
        #expect(snapshot.unresolved.isEmpty)
        #expect(snapshot.records.count == 1 && snapshot.sessions.first?.phase == .partial)
        #expect(plan.items.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        try await restarted.restore(try #require(snapshot.records.first))
        #expect(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    @Test func resetRetainsProviderIgnoreAndSymlinkBoundaries() throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan([.preferences])
        let item = try #require(plan.items.first)
        #expect(throws: (any Error).self) {
            try plan.preflight(home: f.home, context: CleanupExecutionContext(ignoredPaths: [item.url.path], processPaths: []))
        }
        FilesystemAccess.$restriction.withValue({ url in
            Filesystem.isWithin(url, root: f.app.url) ? .providerManaged : .local
        }) {
            #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext(processPaths: [])) }
        }
        let document = f.home.appendingPathComponent("Library/Application Support/org.lumatest.reset/document")
        try FileManager.default.removeItem(at: item.url)
        try FileManager.default.createSymbolicLink(at: item.url, withDestinationURL: document)
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext(processPaths: [])) }
        #expect(try String(contentsOf: document, encoding: .utf8) == "valuable offline document")
    }

    @Test func helperStartingAfterFirstMoveStopsRemainingTargets() async throws {
        let f = try ResetFixture(); defer { f.remove() }
        let plan = try f.plan(), journal = try f.journal()
        let counter = ResetCounter()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: {
                CleanupExecutionContext(runningBundleIDs: await counter.next() >= 3 ? ["org.other.helper"] : [], processPaths: [])
            })
        }
        #expect(await journal.snapshot().records.count == 1)
        #expect(plan.items.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }
}
