import Foundation
import Testing
@testable import LumaCore

private struct JournalFixture {
    let home: URL
    var directory: URL { home.appendingPathComponent("Library/Application Support/Luma") }
    var trash: URL { home.appendingPathComponent(".Trash") }
    var downloads: URL { home.appendingPathComponent("Downloads") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/\(UUID())")
        for folder in [directory, trash, downloads] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }
    func item(_ name: String = "example.txt") throws -> CleanupItem {
        let url = downloads.appendingPathComponent(name)
        try Data("important fixture".utf8).write(to: url)
        return try Filesystem.item(url, category: .storage, safety: .userData, explanation: "test", consequence: "test", rule: "manual.folder-review")
    }
    func journal() throws -> CleanupJournal {
        let root = trash
        return try CleanupJournal(home: home, trashMover: { source in
            let destination = root.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
    }
    func persist(_ state: JournalState) throws {
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("operations.json"), options: .atomic)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}


private extension CleanupJournal {
    func executeFixture(_ item: CleanupItem, authorizedRoots: [URL], ignoredPaths: Set<String>, runningBundleIDs: Set<String>) async throws -> CleanupRecord {
        let plan = try CleanupPlan(items: [item], authorizedRoots: authorizedRoots, ignoredPaths: ignoredPaths)
        let records = try await execute(plan, context: { CleanupExecutionContext(ignoredPaths: ignoredPaths, runningBundleIDs: runningBundleIDs) })
        return try #require(records.first)
    }
}

private final class JournalWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let failingWrite: Int
    init(_ failingWrite: Int) { self.failingWrite = failingWrite }
    func check() throws {
        let fail = lock.withLock { count += 1; return count == failingWrite }
        if fail { throw LumaError.rejected("Injected journal write failure") }
    }
}

@Suite("Durable cleanup and restoration") struct JournalTests {
    @Test func moveAndRestorePersistAcrossJournalInstances() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        let record = try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(record.identity == item.identity)
        let reopened = try f.journal()
        #expect(await reopened.snapshot().records.count == 1)
        try await reopened.restore(record)
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "important fixture")
        #expect(await reopened.snapshot().records.first?.restored == true)
        #expect(try await f.journal().snapshot().records.first?.restored == true)
    }

    @Test func interruptedTrashIsRecoveredByIdentityIncludingRenamedFolders() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let folder = f.downloads.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("contents".utf8).write(to: folder.appendingPathComponent("child"))
        let item = try Filesystem.item(folder, category: .storage, safety: .userData, explanation: "test", consequence: "test", rule: "manual.folder-review")
        let intent = JournalIntent(id: UUID(), action: .trash, original: folder, source: folder, destination: nil, identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        try f.persist(JournalState(pending: [intent]))
        let renamed = f.trash.appendingPathComponent("folder 2")
        try FileManager.default.moveItem(at: folder, to: renamed)
        let journal = try f.journal()
        let recovered = try await journal.reconcile()
        #expect(recovered.unresolved.isEmpty)
        #expect(recovered.records.first?.trashed.path == renamed.path)
        try await journal.restore(try #require(recovered.records.first))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("child").path))
    }

    @Test func preparedButUnmovedIntentNeverRetriesCleanup() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: nil, identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        try f.persist(JournalState(pending: [intent]))
        let recovered = try await f.journal().reconcile()
        #expect(recovered.records.isEmpty)
        #expect(recovered.unresolved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: item.url.path))
    }

    @Test func unknownInterruptedMoveBlocksFurtherCleanupUntilAcknowledged() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: nil, identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        try f.persist(JournalState(pending: [intent]))
        try FileManager.default.removeItem(at: item.url) // Simulate an externally removed item after interruption.
        let journal = try f.journal()
        let recovered = try await journal.reconcile()
        #expect(recovered.unresolved.count == 1)
        let another = try f.item("another.txt")
        await #expect(throws: (any Error).self) { try await journal.executeFixture(another, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: []) }
        #expect(FileManager.default.fileExists(atPath: another.url.path))
        #expect(try await journal.acknowledge(intent.id).unresolved.isEmpty)
    }

    @Test func replacementAndEditsInTrashBlockRestore() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        let record = try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        try Data("changed after cleanup".utf8).write(to: record.trashed)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(FileManager.default.fileExists(atPath: record.trashed.path))
    }

    @Test func occupiedOriginalIsNeverOverwritten() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        let record = try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        try Data("new file".utf8).write(to: item.url)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "new file")
    }

    @Test func interruptedRestoreIsReconciled() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        let record = try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        let intent = JournalIntent(id: UUID(), action: .restore, original: record.original, source: record.trashed, destination: record.original,
                                   identity: item.identity, bytes: item.bytes, date: Date(), recordID: record.id)
        try f.persist(JournalState(records: [record], pending: [intent]))
        try FileManager.default.moveItem(at: record.trashed, to: record.original)
        let recovered = try await f.journal().reconcile()
        #expect(recovered.unresolved.isEmpty)
        #expect(recovered.records.first?.restored == true)
    }

    @Test func failedIntentPersistencePreventsAnyMove() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        try FileManager.default.removeItem(at: f.directory)
        try Data("not a directory".utf8).write(to: f.directory)
        await #expect(throws: (any Error).self) { try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: []) }
        #expect(FileManager.default.fileExists(atPath: item.url.path))
        #expect(try FileManager.default.contentsOfDirectory(at: f.trash, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func staleJournalInstancesPreserveOtherCompletedOperations() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let first = try f.item("first.txt"), second = try f.item("second.txt")
        let a = try f.journal(), b = try f.journal()
        _ = try await a.executeFixture(first, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        _ = try await b.executeFixture(second, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        #expect(try await f.journal().snapshot().records.count == 2)
    }

    @Test func replacedOriginalParentSymlinkBlocksRestore() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let journal = try f.journal()
        let record = try await journal.executeFixture(item, authorizedRoots: [f.downloads], ignoredPaths: [], runningBundleIDs: [])
        let other = f.home.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: f.downloads)
        try FileManager.default.createSymbolicLink(at: f.downloads, withDestinationURL: other)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        #expect(FileManager.default.fileExists(atPath: record.trashed.path))
        #expect(try FileManager.default.contentsOfDirectory(at: other, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func ambiguousTrashIdentityIsLeftForManualReview() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: nil, identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        try f.persist(JournalState(pending: [intent]))
        let one = f.trash.appendingPathComponent("one.txt")
        try FileManager.default.moveItem(at: item.url, to: one)
        try FileManager.default.linkItem(at: one, to: f.trash.appendingPathComponent("two.txt"))
        let snapshot = try await f.journal().reconcile()
        #expect(snapshot.records.isEmpty)
        #expect(snapshot.unresolved.count == 1)
    }

    @Test func corruptJournalIsPreservedAndLegacyHistoryMigrates() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let url = f.directory.appendingPathComponent("operations.json")
        try Data("corrupt".utf8).write(to: url)
        #expect(throws: (any Error).self) { _ = try f.journal() }
        #expect(try String(contentsOf: url, encoding: .utf8) == "corrupt")
        try FileManager.default.removeItem(at: url)
        let record = CleanupRecord(original: f.downloads.appendingPathComponent("old"), trashed: f.trash.appendingPathComponent("old"), bytes: 10)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([record])) as? [[String: Any]])
        json[0].removeValue(forKey: "identity")
        try JSONSerialization.data(withJSONObject: json).write(to: f.directory.appendingPathComponent("history.json"))
        let journal = try f.journal()
        #expect(await journal.snapshot().records.count == 1)
        #expect(await journal.snapshot().records.first?.planID == nil)
        #expect(await journal.snapshot().records.first?.accountedBytes == nil)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
    }

    @Test func knownTrashDestinationWaitsForUnavailableProviderMetadata() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item()
        let destination = f.trash.appendingPathComponent("example.txt")
        let intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: destination,
            identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        try f.persist(JournalState(pending: [intent]))
        try FileManager.default.moveItem(at: item.url, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o100], ofItemAtPath: f.trash.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.trash.path) }
        let snapshot = try await f.journal().reconcile()
        #expect(snapshot.records.isEmpty)
        #expect(snapshot.unresolved.count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.trash.path)
        let recovered = try await f.journal().reconcile()
        #expect(recovered.records.count == 1)
        #expect(recovered.unresolved.isEmpty)
    }
    private func plan(_ f: JournalFixture, _ names: [String]) throws -> CleanupPlan {
        try CleanupPlan(items: names.map { try f.item($0) }, authorizedRoots: [f.downloads])
    }

    @Test func stopDuringPreflightMovesNothingAndPersistsSession() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        let task = Task {
            try await journal.execute(p, context: { CleanupExecutionContext() }, onProgress: { progress in
                if progress.phase == .validating { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let snapshot = try await f.journal().reconcile()
        #expect(snapshot.records.isEmpty && snapshot.unresolved.isEmpty)
        #expect(snapshot.sessions.first?.phase == .stopped)
        #expect(snapshot.sessions.first?.paths.count == 2)
        #expect(FileManager.default.fileExists(atPath: f.downloads.appendingPathComponent("a").path))
    }

    @Test func cancellationInsideNativeMoveCommitsBeforeReturning() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"])
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = f.trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            withUnsafeCurrentTask { $0?.cancel() }
            return destination
        })
        let task = Task { try await journal.execute(p, context: { CleanupExecutionContext() }) }
        await #expect(throws: CancellationError.self) { try await task.value }
        // No reconciliation needed: a finished move is already durable.
        let snapshot = try await f.journal().snapshot()
        #expect(snapshot.records.count == 1 && snapshot.unresolved.isEmpty)
        #expect(snapshot.sessions.first?.phase == .partial)
        #expect(FileManager.default.fileExists(atPath: f.downloads.appendingPathComponent("b").path))
    }

    @Test func undoReviewClassifiesMixedItemsAndOnlyRestoresChosenSession() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b", "c", "d"]), journal = try f.journal()
        let records = try await journal.execute(p, context: { CleanupExecutionContext() })
        let other = try plan(f, ["other"])
        _ = try await journal.execute(other, context: { CleanupExecutionContext() })
        try Data("occupied".utf8).write(to: f.downloads.appendingPathComponent("b"))
        try Data("edited trash".utf8).write(to: records[2].trashed)
        try FileManager.default.removeItem(at: records[3].trashed)
        let review = try await journal.reviewUndo(sessionID: p.id)
        #expect(review.items.first { $0.record.original.lastPathComponent == "a" }?.eligibility == .eligible)
        #expect(review.items.first { $0.record.original.lastPathComponent == "b" }?.eligibility == .occupied)
        #expect(review.items.first { $0.record.original.lastPathComponent == "c" }?.eligibility == .changed)
        #expect(review.items.first { $0.record.original.lastPathComponent == "d" }?.eligibility == .missing)
        try await journal.undo(review)
        let snapshot = try await f.journal().snapshot()
        #expect(snapshot.records.filter(\.restored).count == 1)
        #expect(snapshot.records.first { $0.planID == other.id }?.restored == false)
        #expect(snapshot.undoAttempts.first?.phase == .completed)
        #expect(try String(contentsOf: f.downloads.appendingPathComponent("b"), encoding: .utf8) == "occupied")
        await #expect(throws: (any Error).self) { try await journal.undo(review) }
    }

    @Test func undoRevalidatesConflictsAfterReviewAndRecordsFailure() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        try Data("new occupant".utf8).write(to: f.downloads.appendingPathComponent("b"))
        try await journal.undo(review)
        let snapshot = try await f.journal().snapshot()
        #expect(snapshot.records.filter(\.restored).count == 1)
        #expect(snapshot.undoAttempts.first?.phase == .partial)
        #expect(snapshot.undoAttempts.first?.outcomes.count == 2)
        #expect(try String(contentsOf: f.downloads.appendingPathComponent("b"), encoding: .utf8) == "new occupant")
    }

    @Test func stopUndoBetweenRestoresPreservesOutcomesAcrossRestart() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b", "c"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        let task = Task {
            try await journal.undo(review, onProgress: { progress in
                if progress.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let reopened = try f.journal()
        let snapshot = try await reopened.reconcile()
        #expect(snapshot.records.filter(\.restored).count == 1)
        #expect(snapshot.undoAttempts.first?.outcomes.filter(\.restored).count == 1)
        #expect(snapshot.undoAttempts.first?.phase == .stopped)
        let next = try await reopened.reviewUndo(sessionID: p.id)
        #expect(next.eligibleIDs.count == 2)
        #expect(next.items.filter { $0.eligibility == .restored }.count == 1)
        try await reopened.undo(next)
        #expect(await reopened.snapshot().records.allSatisfy(\.restored))
    }

    @Test func undoRejectsReplacedParentAndPreservesTrash() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a"]), journal = try f.journal()
        let records = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        try FileManager.default.removeItem(at: f.downloads)
        try FileManager.default.createDirectory(at: f.downloads, withIntermediateDirectories: false)
        try await journal.undo(review)
        #expect(await journal.snapshot().records.first?.restored == false)
        #expect(FileManager.default.fileExists(atPath: records[0].trashed.path))
    }

    @Test func interruptedSessionIsClassifiedWithoutInventingLegacyGrouping() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let item = try f.item(), id = UUID()
        let legacy = CleanupRecord(original: item.url, trashed: f.trash.appendingPathComponent("old"), bytes: 1)
        let session = CleanupSession(id: id, source: .storage, date: Date(), paths: [item.url], logicalBytes: item.bytes, phase: .moving)
        try f.persist(JournalState(records: [legacy], sessions: [session]))
        let snapshot = try await f.journal().reconcile()
        #expect(snapshot.sessions.first?.phase == .stopped)
        #expect(snapshot.records.first?.planID == nil)
    }

    @Test func failedCompletionWriteRetainsRecoverableMoveAndSession() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        let gate = JournalWriteGate(4) // Session, intent, destination, completion.
        await journal.setJournalWriteCheckpoint { try gate.check() }
        await #expect(throws: (any Error).self) {
            try await journal.execute(p, context: { CleanupExecutionContext() })
        }
        #expect(await journal.snapshot().sessions.first?.phase == .recoveryNeeded)
        let reopened = try f.journal()
        let recovered = try await reopened.reconcile()
        #expect(recovered.records.count == 1 && recovered.unresolved.isEmpty)
        #expect(recovered.sessions.first?.phase == .partial)
        #expect(FileManager.default.fileExists(atPath: f.downloads.appendingPathComponent("b").path))
    }

    @Test func interruptedUndoCompletionRecoversOutcomeWithoutRetry() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        let gate = JournalWriteGate(3) // Undo attempt, restore intent, completion.
        await journal.setJournalWriteCheckpoint { try gate.check() }
        await #expect(throws: (any Error).self) { try await journal.undo(review) }
        let reopened = try f.journal()
        let recovered = try await reopened.reconcile()
        #expect(recovered.records.filter(\.restored).count == 1)
        #expect(recovered.unresolved.isEmpty)
        #expect(recovered.undoAttempts.first?.outcomes.filter(\.restored).count == 1)
        #expect(recovered.undoAttempts.first?.phase == .stopped)
        #expect(try await reopened.reviewUndo(sessionID: p.id).eligibleIDs.count == 1)
    }

    @Test func stopInsideRestoreCommitsBeforeNextItem() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        await journal.setRestoreOutcomeCheckpoint { withUnsafeCurrentTask { $0?.cancel() } }
        let operation = Task { try await journal.undo(review) }
        await #expect(throws: CancellationError.self) { try await operation.value }
        let persisted = try await f.journal().snapshot()
        #expect(persisted.records.filter(\.restored).count == 1)
        #expect(persisted.unresolved.isEmpty)
        #expect(persisted.undoAttempts.first?.outcomes.filter(\.restored).count == 1)
        #expect(persisted.undoAttempts.first?.phase == .stopped)
    }

    @Test func providerStateChangedAfterUndoReviewBlocksRestore() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        try await FilesystemAccess.$restriction.withValue({ $0.path == f.trash.path ? .providerManaged : .local }) {
            try await journal.undo(review)
        }
        let snapshot = await journal.snapshot()
        #expect(snapshot.records.first?.restored == false)
        #expect(snapshot.undoAttempts.first?.phase == .partial)
        #expect(!FileManager.default.fileExists(atPath: f.downloads.appendingPathComponent("a").path))
    }

    @Test func preflightFailureIdentifiesBlockedPathAndMovesNothing() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a", "b"]), journal = try f.journal()
        try Data("changed after review".utf8).write(to: p.items[1].url)
        await #expect(throws: (any Error).self) { try await journal.execute(p, context: { CleanupExecutionContext() }) }
        let snapshot = try await f.journal().snapshot()
        #expect(snapshot.records.isEmpty)
        #expect(snapshot.sessions.first?.phase == .failed)
        #expect(snapshot.sessions.first?.blockedPath == p.items[1].url)
        #expect(FileManager.default.fileExists(atPath: p.items[0].url.path))
    }

    @Test func failedUndoSummaryWriteCannotMislabelCommittedRestore() async throws {
        let f = try JournalFixture(); defer { f.remove() }
        let p = try plan(f, ["a"]), journal = try f.journal()
        _ = try await journal.execute(p, context: { CleanupExecutionContext() })
        let review = try await journal.reviewUndo(sessionID: p.id)
        let gate = JournalWriteGate(4) // Attempt, intent, restored record, attempt outcome.
        await journal.setJournalWriteCheckpoint { try gate.check() }
        try await journal.undo(review)
        let snapshot = try await f.journal().snapshot()
        #expect(snapshot.records.first?.restored == true)
        #expect(snapshot.undoAttempts.first?.outcomes.first?.restored == true)
        #expect(snapshot.undoAttempts.first?.phase == .completed)
        #expect(snapshot.unresolved.isEmpty)
    }

}
