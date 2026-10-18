import Foundation
import Testing
@testable import LumaCore

private struct PlanFixture: Sendable {
    let home: URL
    var downloads: URL { home.appendingPathComponent("Downloads") }
    var trash: URL { home.appendingPathComponent(".Trash") }
    var directory: URL { home.appendingPathComponent("Library/Application Support/Luma") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/\(UUID())")
        for path in [downloads, trash, directory] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
    }
    @discardableResult func file(_ path: String, contents: String = "same content") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }
    func manual(_ path: String) throws -> CleanupItem {
        try Filesystem.item(home.appendingPathComponent(path), category: .storage, safety: .userData,
                            explanation: "Fixture", consequence: "Fixture", rule: "manual.folder-review")
    }
    func groups() throws -> [DuplicateGroup] { try DuplicateScanner(root: downloads).scan().0 }
    func plan(_ items: [CleanupItem], groups: [DuplicateGroup] = []) throws -> CleanupPlan {
        try CleanupPlan(items: items, authorizedRoots: [downloads], duplicateGroups: groups)
    }
    func journal(mover: (@Sendable (URL) throws -> URL)? = nil) throws -> CleanupJournal {
        let root = trash
        return try CleanupJournal(home: home, trashMover: mover ?? { source in
            let destination = root.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
    }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path) }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

private actor ContextCounter {
    var count = 0
    func next() -> Int { count += 1; return count }
}

private let idleContext: @Sendable () async throws -> CleanupExecutionContext = { CleanupExecutionContext() }

@Suite("Complete cleanup plan boundary") struct CleanupPlanTests {
    @Test func repeatedPathsAndNestedSelectionsAreRejected() throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/folder/child")
        let child = try f.manual("Downloads/folder/child"), parent = try f.manual("Downloads/folder")
        #expect(throws: (any Error).self) { try f.plan([child, child]) }
        #expect(throws: (any Error).self) { try f.plan([child, parent]) }
        #expect(throws: (any Error).self) { try f.plan([parent, child]) }
        #expect(f.exists("Downloads/folder/child"))
    }

    @Test func repeatedObjectAliasesCannotExecuteTwice() throws {
        let f = try PlanFixture(); defer { f.remove() }
        let one = try f.file("Downloads/one")
        try FileManager.default.linkItem(at: one, to: f.downloads.appendingPathComponent("alias"))
        #expect(throws: (any Error).self) { try f.plan([f.manual("Downloads/one"), f.manual("Downloads/alias")]) }
        #expect(f.exists("Downloads/one") && f.exists("Downloads/alias"))
    }

    @Test func hardLinkedContentAcrossTreesIsAccountedOnceAndSessionPersists() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        let one = try f.file("Downloads/first/shared", contents: "content")
        try FileManager.default.createDirectory(at: f.downloads.appendingPathComponent("second"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: one, to: f.downloads.appendingPathComponent("second/shared"))
        let plan = try f.plan([f.manual("Downloads/first"), f.manual("Downloads/second")])
        #expect(plan.logicalBytes == 7)
        let journal = try f.journal()
        let records = try await journal.execute(plan, context: idleContext)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.planID == plan.id && $0.planSource == .storage && $0.bytes == 7 })
        #expect(records.compactMap(\.accountedBytes).reduce(0, +) == plan.logicalBytes)
        let reopened = try f.journal()
        #expect(await reopened.snapshot().records.allSatisfy { $0.planID == plan.id })
        for record in records.reversed() { try await reopened.restore(record) }
        #expect(f.exists("Downloads/first/shared") && f.exists("Downloads/second/shared"))
    }

    @Test func duplicateRuleWithoutGroupAndAllCopiesSelectionAreRejected() throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let group = try #require(f.groups().first)
        #expect(throws: (any Error).self) { try f.plan([group.items[0]]) }
        #expect(throws: (any Error).self) { try f.plan(group.items, groups: [group]) }
        #expect(f.exists("Downloads/a") && f.exists("Downloads/b"))
    }

    @Test func keeperCannotBeSelectedThroughAnotherRuleOrEnclosingFolder() throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/folder/b")
        let group = try #require(f.groups().first)
        let selected = try #require(group.items.first { $0.name == "a" })
        #expect(throws: (any Error).self) { try f.plan([selected, f.manual("Downloads/folder/b")], groups: [group]) }
        #expect(throws: (any Error).self) { try f.plan([selected, f.manual("Downloads/folder")], groups: [group]) }
    }

    @Test func keeperMissingAfterReviewPreventsTheFirstMove() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let group = try #require(f.groups().first)
        let plan = try f.plan([group.items[0]], groups: [group])
        try FileManager.default.removeItem(at: group.items[1].url)
        let journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(FileManager.default.fileExists(atPath: group.items[0].url.path))
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func unreadableKeeperPreventsTheFirstMove() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let group = try #require(f.groups().first)
        let plan = try f.plan([group.items[0]], groups: [group])
        let keeper = group.items[1].url
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: keeper.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keeper.path) }
        let journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func contentChangeWithIdenticalMetadataStillInvalidatesKeeper() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for name in ["a", "b"] {
            let url = try f.file("Downloads/\(name)", contents: "aaaa")
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let group = try #require(f.groups().first)
        let plan = try f.plan([group.items[0]], groups: [group])
        let keeper = group.items[1]
        try Data("bbbb".utf8).write(to: keeper.url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: keeper.url.path)
        #expect(try Filesystem.inspect(keeper.url).1 == keeper.identity)
        let journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func forgedDigestAndUnrelatedKeeperAreNotProof() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let group = try #require(f.groups().first)
        let forged = DuplicateGroup(id: String(repeating: "0", count: 64), items: group.items)
        let plan = try f.plan([group.items[0]], groups: [forged])
        let journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(f.exists("Downloads/a") && f.exists("Downloads/b"))
    }

    @Test func keeperChangedBetweenPreflightAndMoveIsRechecked() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let group = try #require(f.groups().first)
        let plan = try f.plan([group.items[0]], groups: [group])
        let counter = ContextCounter(), keeper = group.items[1].url
        let journal = try f.journal()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: {
                if await counter.next() == 2 { try FileManager.default.removeItem(at: keeper) }
                return CleanupExecutionContext()
            })
        }
        #expect(await journal.snapshot().records.isEmpty)
        #expect(FileManager.default.fileExists(atPath: group.items[0].url.path))
    }

    @Test func keeperChangedAfterEarlierSuccessStopsRemainingMoves() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        for name in ["a", "b", "keeper"] { try f.file("Downloads/\(name)") }
        let group = try #require(f.groups().first)
        let items = group.items.filter { $0.name != "keeper" }
        let keeper = try #require(group.items.first { $0.name == "keeper" })
        let plan = try f.plan(items, groups: [group])
        let journal = try f.journal()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: idleContext, onRecord: { _ in
                try? Data("changed".utf8).write(to: keeper.url)
            })
        }
        let snapshot = try await journal.reconcile()
        #expect(snapshot.records.count == 1 && snapshot.unresolved.isEmpty)
        #expect(snapshot.records.first?.planID == plan.id)
        #expect(!FileManager.default.fileExists(atPath: items[0].url.path))
        #expect(FileManager.default.fileExists(atPath: items[1].url.path))
    }

    @Test func wholePlanPreflightPreventsPartialMoveForChangedOrIgnoredItems() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let items = try [f.manual("Downloads/a"), f.manual("Downloads/b")]
        let plan = try f.plan(items), journal = try f.journal()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: { CleanupExecutionContext(ignoredPaths: [items[1].url.path]) })
        }
        try Data("changed after review".utf8).write(to: items[1].url)
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(f.exists("Downloads/a") && f.exists("Downloads/b"))
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func freshIgnorePolicyAfterFirstMoveStopsThePlan() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let items = try [f.manual("Downloads/a"), f.manual("Downloads/b")]
        let plan = try f.plan(items), journal = try f.journal(), counter = ContextCounter()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: {
                CleanupExecutionContext(ignoredPaths: await counter.next() >= 3 ? [items[1].url.path] : [])
            })
        }
        #expect(!f.exists("Downloads/a") && f.exists("Downloads/b"))
        #expect(await journal.snapshot().records.count == 1)
    }

    @Test func staleCandidateAndForgedSizeCannotAuthorizeMoves() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a")
        let item = try f.manual("Downloads/a")
        let stale = CleanupItem(url: item.url, bytes: item.bytes, category: item.category, safety: item.safety,
            explanation: item.explanation, consequence: item.consequence, ruleID: item.ruleID, ownerBundleID: nil,
            identity: item.identity, scannedAt: .distantPast)
        let plan = try f.plan([stale]), journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        let forged = CleanupItem(url: item.url, bytes: 0, category: item.category, safety: item.safety,
            explanation: item.explanation, consequence: item.consequence, ruleID: item.ruleID, ownerBundleID: nil,
            identity: item.identity, scannedAt: item.scannedAt)
        #expect(throws: (any Error).self) { try f.plan([forged]) }
        #expect(f.exists("Downloads/a"))
    }

    @Test func reentrantOperationsAndOtherInstancesCannotInterleaveWithAPlan() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let plan = try f.plan([f.manual("Downloads/a")]), another = try f.plan([f.manual("Downloads/b")])
        let journal = try f.journal(), other = try f.journal()
        _ = try await journal.execute(plan, context: idleContext, onRecord: { record in
            await #expect(throws: (any Error).self) { try await journal.restore(record) }
            await #expect(throws: (any Error).self) { try await other.execute(another, context: idleContext) }
        })
        #expect(f.exists("Downloads/b"))
        #expect(await journal.snapshot().records.count == 1)
    }

    @Test func completedPlanCannotBeReplayedEvenAfterRestore() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a")
        let plan = try f.plan([f.manual("Downloads/a")]), journal = try f.journal()
        let record = try #require(await journal.execute(plan, context: idleContext).first)
        try await journal.restore(record)
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(f.exists("Downloads/a"))
    }

    @Test func cancellationAfterNativeMoveStillCommitsBeforeStopping() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Downloads/b")
        let plan = try f.plan([f.manual("Downloads/a"), f.manual("Downloads/b")])
        let journal = try f.journal(mover: { source in
            let destination = f.trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            withUnsafeCurrentTask { $0?.cancel() }
            return destination
        })
        let operation = Task { try await journal.execute(plan, context: idleContext) }
        await #expect(throws: CancellationError.self) { try await operation.value }
        let snapshot = try await journal.reconcile()
        #expect(snapshot.records.count == 1 && snapshot.unresolved.isEmpty)
        #expect(!f.exists("Downloads/a") && f.exists("Downloads/b"))
    }

    @Test func interruptedMoveRetainsPlanMetadataDuringRecovery() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a")
        let item = try f.manual("Downloads/a"), plan = try f.plan([item])
        let destination = f.trash.appendingPathComponent("a")
        var intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: destination,
            identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        intent.planID = plan.id; intent.planSource = .storage; intent.accountedBytes = plan.logicalBytes
        try JSONEncoder().encode(JournalState(pending: [intent])).write(to: f.directory.appendingPathComponent("operations.json"))
        try FileManager.default.moveItem(at: item.url, to: destination)
        let snapshot = try await f.journal().reconcile()
        let record = try #require(snapshot.records.first)
        #expect(record.planID == plan.id && record.planSource == .storage && record.accountedBytes == plan.logicalBytes)
        #expect(snapshot.unresolved.isEmpty)
    }

    @Test func protectedItemInAPlanPreventsAllMoves() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        try f.file("Downloads/a"); try f.file("Documents/personal")
        let plan = try f.plan([f.manual("Downloads/a"), f.manual("Documents")]), journal = try f.journal()
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        #expect(f.exists("Downloads/a") && f.exists("Documents/personal"))
        #expect(await journal.snapshot().records.isEmpty)
    }

    @Test func generatedDataUsesThePlanAndRechecksRunningOwners() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        let rule = try #require(Rules.generated.first { $0.id == "browser.chrome.cache" })
        try f.file(rule.relativePath + "/entry")
        let item = try #require(await GeneratedDataScanner(home: f.home).scan().items.first)
        let plan = try CleanupPlan(items: [item], source: .generatedData), journal = try f.journal()
        let counter = ContextCounter(), owner = try #require(rule.owner)
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: {
                CleanupExecutionContext(runningBundleIDs: await counter.next() >= 2 ? [owner] : [])
            })
        }
        #expect(await journal.snapshot().records.isEmpty)
        let records = try await journal.execute(plan, context: idleContext)
        #expect(records.first?.planSource == .generatedData)
        try await journal.restore(try #require(records.first))
        #expect(f.exists(rule.relativePath + "/entry"))
    }

    @Test func applicationAndRelatedDataShareOneValidatedPlan() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        let identifier = "org.example.fixture\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let bundlePath = "Applications/Fixture.app"
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
        let infoURL = try f.file(bundlePath + "/Contents/Info.plist")
        try info.write(to: infoURL)
        try f.file("Library/Caches/\(identifier)/entry")
        try f.file("Library/Application Support/\(identifier)/document", contents: "valuable content")
        let appURL = f.home.appendingPathComponent(bundlePath)
        let app = ApplicationRecord(url: appURL, name: "Fixture", bundleID: identifier, version: "1", bytes: try Filesystem.inspect(appURL).0)
        let footprint = try ApplicationScanner.footprint(app, home: f.home)
        let plan = try CleanupPlan(items: footprint, source: .applications), journal = try f.journal()
        let records = try await journal.execute(plan, context: idleContext)
        #expect(records.count == 3 && records.allSatisfy { $0.planID == plan.id && $0.planSource == .applications })
        for record in records.reversed() { try await journal.restore(record) }
        #expect(f.exists(bundlePath))
        #expect(try String(contentsOf: f.home.appendingPathComponent("Library/Application Support/\(identifier)/document"), encoding: .utf8) == "valuable content")
    }

    @Test func leftoversUseTheSameExecutionBoundary() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        let identifier = "org.example.orphan\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try f.file("Library/Caches/\(identifier)/entry")
        let report = try await LeftoverScanner(home: f.home, applicationRoots: [], lookup: { _ in false }).scan()
        let plan = try CleanupPlan(items: report.items, source: .leftovers), journal = try f.journal()
        let records = try await journal.execute(plan, context: idleContext)
        #expect(records.count == 1 && records.first?.planSource == .leftovers)
        try await journal.restore(try #require(records.first))
        #expect(f.exists("Library/Caches/\(identifier)/entry"))
    }

    @Test func moveFailureStopsThePlanAndRecoveryDoesNotRetry() async throws {
        let f = try PlanFixture(); defer { f.remove() }
        for name in ["a", "b", "c"] { try f.file("Downloads/\(name)") }
        let items = try ["a", "b", "c"].map { try f.manual("Downloads/\($0)") }
        let plan = try f.plan(items)
        let journal = try f.journal(mover: { source in
            if source.lastPathComponent == "b" { throw POSIXError(.EIO) }
            let destination = f.trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: idleContext) }
        let snapshot = try await journal.reconcile()
        #expect(snapshot.records.count == 1 && snapshot.unresolved.isEmpty)
        #expect(!f.exists("Downloads/a") && f.exists("Downloads/b") && f.exists("Downloads/c"))
    }
}
