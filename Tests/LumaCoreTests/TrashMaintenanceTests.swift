import Foundation
import Testing
import Darwin
@testable import LumaCore

struct TrashMaintenanceTests {
    private func fixture() throws -> (URL, URL, CleanupJournal) {
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/luma-trash-\(UUID())")
        let root = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (home, root, try CleanupJournal(home: home))
    }
    private func write(_ root: URL, _ name: String, _ value: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(value.utf8).write(to: url); return url
    }
    @Test func onlyApprovedUnchangedEntriesAreDeleted() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let approved = try write(root, "approved")
        let changed = try write(root, "changed")
        let review = try TrashReview.capture(root: root)
        try Data("changed after approval".utf8).write(to: changed)
        let arrival = try write(root, "arrival")
        let result = try await journal.emptyTrash(review)
        #expect(!FileManager.default.fileExists(atPath: approved.path))
        #expect(FileManager.default.fileExists(atPath: changed.path))
        #expect(FileManager.default.fileExists(atPath: arrival.path))
        #expect(result.outcomes.contains { $0.state == "skipped" && $0.path == changed })
        #expect(FileManager.default.fileExists(atPath: root.path))
        await #expect(throws: (any Error).self) { try await journal.emptyTrash(review) }
    }
    @Test func changedDescendantPreservesWholeTreeAndLinksAreExcluded() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let child = try write(folder, "child")
        let outside = try write(home, "outside")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let review = try TrashReview.capture(root: root)
        #expect(review.excluded == 1)
        try Data("different".utf8).write(to: child)
        let result = try await journal.emptyTrash(review)
        #expect(result.outcomes.allSatisfy { $0.state == "skipped" })
        #expect(FileManager.default.fileExists(atPath: child.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
    @Test func newArrivalDuringDeletionPreventsDirectoryRemoval() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try write(folder, "approved")
        let review = try TrashReview.capture(root: root)
        await journal.setMutationCheckpoint {
            try Data("new".utf8).write(to: folder.appendingPathComponent("arrival"))
        }
        let result = try await journal.emptyTrash(review)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("arrival").path))
        #expect(result.outcomes.contains { $0.state == "removed" })
        #expect(result.outcomes.contains { $0.state == "failed" })
    }
    @Test func rootReplacementAndProviderScopeAreRejected() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        _ = try write(root, "item")
        let review = try TrashReview.capture(root: root)
        try FileManager.default.moveItem(at: root, to: home.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await journal.emptyTrash(review) }
        #expect(throws: (any Error).self) {
            try FilesystemAccess.$restriction.withValue({ _ in .providerManaged }) { try TrashReview.capture(root: root) }
        }
    }
    @Test func cancellationAndRestartDoNotRepeatApproval() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        _ = try write(root, "a"); _ = try write(root, "b")
        let review = try TrashReview.capture(root: root)
        let task = Task {
            return try await journal.emptyTrash(review, progress: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        let result = try await task.value
        #expect(!result.finished)
        #expect(result.outcomes.filter { $0.state == "removed" }.count == 1)
        let restarted = try CleanupJournal(home: home)
        #expect(await restarted.trashRemovalHistory().count == 1)
        await #expect(throws: (any Error).self) { try await restarted.emptyTrash(review) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }
    @Test func boundedInspectionExcludesOversizedTree() throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try write(folder, "a"); _ = try write(folder, "b")
        let review = try TrashReview.capture(root: root, limit: 2)
        #expect(review.count == 0 && review.excluded == 1)
    }
}

extension TrashMaintenanceTests {
    @Test func permanentRemovalInvalidatesOnlyAffectedRestoreAndSerializes() async throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let journal = try CleanupJournal(home: home, trashMover: { source in
            let destination = root.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        let first = try write(downloads, "first"), second = try write(downloads, "second")
        let items = try [first, second].map {
            try Filesystem.item($0, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        }
        let plan = try CleanupPlan(items: items, authorizedRoots: [downloads])
        let records = try await journal.execute(plan, context: { CleanupExecutionContext() })
        let reviewed = try TrashReview.capture(root: root)
        // A changed second target is skipped; its complete Restore stays available.
        let secondRecord = try #require(records.first { $0.original == second })
        try Data("changed".utf8).write(to: secondRecord.trashed)
        let firstRecord = try #require(records.first { $0.original == first })
        _ = try await journal.emptyTrash(reviewed, progress: { _ in
            await #expect(throws: (any Error).self) { try await journal.restore(secondRecord) }
        })
        let snapshot = await journal.snapshot()
        #expect(snapshot.records.first { $0.id == firstRecord.id }?.permanentlyRemoved == true)
        #expect(snapshot.records.first { $0.id == secondRecord.id }?.permanentlyRemoved != true)
        await #expect(throws: (any Error).self) { try await journal.restore(firstRecord) }
        let undo = try await journal.reviewUndo(sessionID: plan.id)
        #expect(undo.items.first { $0.record.id == firstRecord.id }?.eligibility == .unavailable)
    }

    @Test func interruptedIntentSurvivesRestartWithoutRetry() async throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let target = try write(root, "keep")
        let session = TrashRemovalSession(id: UUID(), date: Date(), root: root,
            outcomes: [.init(path: target, state: "deleting", detail: "Interrupted after intent")], finished: false)
        let directory = home.appendingPathComponent("Library/Application Support/Luma")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = JournalState(); state.trashSessions = [session]
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("operations.json"))
        let restarted = try CleanupJournal(home: home)
        _ = try await restarted.reconcile()
        let history = await restarted.trashRemovalHistory()
        #expect(history.first?.outcomes.first?.state == "interrupted")
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
}

extension TrashMaintenanceTests {
    @Test func partiallyEmptiedTreeCannotRestoreAsComplete() async throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        let folder = downloads.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try write(folder, "original")
        let journal = try CleanupJournal(home: home, trashMover: { source in
            let destination = root.appendingPathComponent("folder")
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        let item = try Filesystem.item(folder, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        let plan = try CleanupPlan(items: [item], authorizedRoots: [downloads])
        let record = try #require(try await journal.execute(plan, context: { CleanupExecutionContext() }).first)
        let review = try TrashReview.capture(root: root)
        await journal.setMutationCheckpoint {
            try Data("arrival".utf8).write(to: record.trashed.appendingPathComponent("arrival"))
        }
        _ = try await journal.emptyTrash(review)
        #expect(FileManager.default.fileExists(atPath: record.trashed.path))
        #expect(!FileManager.default.fileExists(atPath: record.trashed.appendingPathComponent("original").path))
        #expect(await journal.snapshot().records.first?.permanentlyRemoved == true)
        await #expect(throws: (any Error).self) { try await journal.restore(record) }
        let restarted = try CleanupJournal(home: home)
        #expect(await restarted.snapshot().records.first?.permanentlyRemoved == true)
    }

    @Test func failedIntentPersistencePreventsPermanentRemoval() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let item = try write(root, "keep")
        let review = try TrashReview.capture(root: root)
        await journal.setJournalWriteCheckpoint { throw LumaError.rejected("Injected unavailable journal") }
        await #expect(throws: (any Error).self) { try await journal.emptyTrash(review) }
        #expect(FileManager.default.fileExists(atPath: item.path))
    }
}

extension TrashMaintenanceTests {
    @Test func changedDirectoryPermissionsAfterChildRemovalArePreserved() async throws {
        let (home, root, journal) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = try write(folder, "child")
        let review = try TrashReview.capture(root: root)
        await journal.setMutationCheckpoint {
            try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: folder.path)
        }
        let result = try await journal.emptyTrash(review)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(result.outcomes.contains { $0.path == folder && $0.state == "failed" })
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}

extension TrashMaintenanceTests {
    @Test func knownFailedDeletionKeepsCompleteRestoreAvailable() async throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let source = try write(downloads, "file")
        let journal = try CleanupJournal(home: home, trashMover: { url in
            let destination = root.appendingPathComponent("file")
            try FileManager.default.moveItem(at: url, to: destination); return destination
        })
        let item = try Filesystem.item(source, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        let plan = try CleanupPlan(items: [item], authorizedRoots: [downloads])
        let record = try #require(try await journal.execute(plan, context: { CleanupExecutionContext() }).first)
        let review = try TrashReview.capture(root: root)
        await journal.setMutationCheckpoint { throw LumaError.rejected("Injected permission failure before unlink") }
        let result = try await journal.emptyTrash(review)
        #expect(result.outcomes.first?.state == "failed")
        #expect(await journal.snapshot().records.first?.permanentlyRemoved != true)
        await journal.setMutationCheckpoint {}
        try await journal.restore(record)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}

extension TrashMaintenanceTests {
    @Test func replacementAtOldTrashNameDoesNotRetargetHistory() async throws {
        let (home, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let source = try write(downloads, "file")
        let journal = try CleanupJournal(home: home, trashMover: { url in
            let destination = root.appendingPathComponent("file")
            try FileManager.default.moveItem(at: url, to: destination); return destination
        })
        let item = try Filesystem.item(source, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        let plan = try CleanupPlan(items: [item], authorizedRoots: [downloads])
        let record = try #require(try await journal.execute(plan, context: { CleanupExecutionContext() }).first)
        let retained = home.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: record.trashed, to: retained)
        _ = try write(root, "file", "different object")
        _ = try await journal.emptyTrash(TrashReview.capture(root: root))
        #expect(await journal.snapshot().records.first?.permanentlyRemoved != true)
        #expect(FileManager.default.fileExists(atPath: retained.path))
    }
}
