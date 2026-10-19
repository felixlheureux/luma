import Foundation
import Darwin

public struct RecoveryNotice: Identifiable, Sendable {
    public let id: UUID
    public let original: URL
    public let detail: String
}

public struct JournalSnapshot: Sendable {
    public let records: [CleanupRecord]
    public let unresolved: [RecoveryNotice]
    public let sessions: [CleanupSession]
    public let undoAttempts: [UndoAttempt]
}

enum JournalAction: String, Codable { case trash, restore }
struct JournalIntent: Codable {
    let id: UUID
    let action: JournalAction
    let original: URL
    let source: URL
    var destination: URL?
    let identity: FileIdentity
    let bytes: Int64
    let date: Date
    let recordID: UUID?
    var planID: UUID? = nil
    var planSource: CleanupSource? = nil
    var accountedBytes: Int64? = nil

    func completedRecord(at destination: URL) -> CleanupRecord {
        CleanupRecord(id: id, date: date, original: original, trashed: destination, bytes: bytes, identity: identity,
                      planID: planID, planSource: planSource, accountedBytes: accountedBytes)
    }
}
struct JournalState: Codable {
    var version = 1
    var records: [CleanupRecord] = []
    var pending: [JournalIntent] = []
    var sessions: [CleanupSession]? = nil
    var undoAttempts: [UndoAttempt]? = nil
}

/// The operation intent reaches disk before any move. Completed history and
/// removal of its intent are committed together in one atomic state file.
public actor CleanupJournal {
    @TaskLocal static var persistenceObserver: (@Sendable (TimeInterval) -> Void)?
    private let home: URL
    private let directory: URL
    private let url: URL
    private let trashMover: @Sendable (URL) throws -> URL
    private var state: JournalState
    private var recoveryDetails: [UUID: String] = [:]
    private var executingPlan = false
    private var mutationCheckpoint: (@Sendable () throws -> Void)?
    private var journalWriteCheckpoint: (@Sendable () throws -> Void)?
    private var restoreOutcomeCheckpoint: (@Sendable () -> Void)?

    // Deterministic test synchronization; never supplies or bypasses validation.
    func setMutationCheckpoint(_ checkpoint: @escaping @Sendable () throws -> Void) {
        mutationCheckpoint = checkpoint
    }

    func setJournalWriteCheckpoint(_ checkpoint: @escaping @Sendable () throws -> Void) {
        journalWriteCheckpoint = checkpoint
    }

    func setRestoreOutcomeCheckpoint(_ checkpoint: @escaping @Sendable () -> Void) {
        restoreOutcomeCheckpoint = checkpoint
    }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL? = nil,
                trashMover: (@Sendable (URL) throws -> URL)? = nil) throws {
        self.home = home
        let directory = directory ?? home.appendingPathComponent("Library/Application Support/Luma")
        self.directory = directory; url = directory.appendingPathComponent("operations.json")
        self.trashMover = trashMover ?? Self.systemTrash
        if try Self.hasEntry(url) {
            try Filesystem.validatePath(url)
            let loaded = try JSONDecoder().decode(JournalState.self, from: Filesystem.readMetadata(url))
            guard loaded.version == 1 else { throw LumaError.rejected("This activity journal uses an unsupported version. Cleanup is paused to preserve it.") }
            state = loaded
        } else {
            let legacy = directory.appendingPathComponent("history.json")
            if try Self.hasEntry(legacy) {
                try Filesystem.validatePath(legacy)
                state = JournalState(records: try JSONDecoder().decode([CleanupRecord].self, from: Filesystem.readMetadata(legacy)))
            } else { state = JournalState() }
        }
    }

    private static func systemTrash(_ source: URL) throws -> URL {
        var destination: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
        guard let destination else { throw LumaError.rejected("macOS did not report the Trash location. Activity will check the interrupted operation.") }
        return destination as URL
    }

    public func snapshot() -> JournalSnapshot {
        JournalSnapshot(records: state.records, unresolved: state.pending.map {
            RecoveryNotice(id: $0.id, original: $0.original,
                detail: recoveryDetails[$0.id] ?? "An interrupted operation needs review. Check its original location and Trash before continuing.")
        }, sessions: state.sessions ?? [], undoAttempts: state.undoAttempts ?? [])
    }

    /// The only cleanup entry point. Hold the operation lock over the complete
    /// plan, including awaited UI context/progress callbacks and every move.
    public func execute(_ plan: CleanupPlan,
                        context: (@Sendable () async throws -> CleanupExecutionContext)? = nil,
                        onRecord: @Sendable (CleanupRecord) async -> Void = { _ in },
                        onProgress: @Sendable (CleanupProgress) async -> Void = { _ in },
                        onDetail: @escaping @Sendable (ScanPulse) -> Void = { _ in }) async throws -> [CleanupRecord] {
        try requireIdle()
        executingPlan = true; defer { executingPlan = false }
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        guard state.pending.isEmpty else { throw LumaError.rejected("Review interrupted operations in Activity before starting another cleanup.") }
        guard !(state.sessions ?? []).contains(where: { $0.id == plan.id }), !state.records.contains(where: { $0.planID == plan.id }) else {
            throw LumaError.rejected("This cleanup plan has already been used. Prepare a new review before moving more items.")
        }
        let context = context ?? { await plan.executionContext() }
        var prepared = state
        prepared.sessions = (prepared.sessions ?? []) + [CleanupSession(id: plan.id, source: plan.source, date: Date(),
            paths: plan.items.map(\.url), logicalBytes: plan.logicalBytes, phase: .validating)]
        try commit(prepared)
        var completed: [CleanupRecord] = []
        var currentPath: URL?
        do {
            await onProgress(CleanupProgress(sessionID: plan.id, phase: .validating, current: nil, completed: 0, total: plan.items.count))
            try Task.checkCancellation()
            onDetail(.init("Checking running applications"))
            let initialContext = try await context()
            onDetail(.init("Checking installed owners and helpers"))
            let owners = try plan.preflightOwners(home: home, progress: onDetail)
            for (index, item) in plan.items.enumerated() {
                currentPath = item.url
                try Task.checkCancellation()
                await onProgress(CleanupProgress(sessionID: plan.id, phase: .validating, current: item.url, completed: index, total: plan.items.count))
                try plan.validate(item, home: home, context: initialContext, preflightOwners: owners, progress: onDetail)
                await onProgress(CleanupProgress(sessionID: plan.id, phase: .validating, current: item.url, completed: index + 1, total: plan.items.count))
            }
            for item in plan.items {
                currentPath = item.url
                try Task.checkCancellation()
                await onProgress(CleanupProgress(sessionID: plan.id, phase: .moving, current: item.url, completed: completed.count, total: plan.items.count))
                onDetail(.init("Checking running applications", current: item.name))
                let currentContext = try await context()
                try Task.checkCancellation()
                let record = try trash(item, plan: plan, context: currentContext, onDetail: onDetail)
                completed.append(record)
                // A native operation must commit its outcome before observing Stop.
                await onRecord(record)
            }
            try updateSession(plan.id, phase: .completed)
            return completed
        } catch {
            let phase: CleanupPhase = state.pending.isEmpty
                ? (completed.isEmpty ? (error is CancellationError ? .stopped : .failed) : .partial)
                : .recoveryNeeded
            try updateSession(plan.id, phase: phase, detail: error is CancellationError ? "Stopped at a safe boundary." : error.localizedDescription,
                              blockedPath: error is CancellationError ? nil : currentPath)
            throw error
        }
    }

    private func updateSession(_ id: UUID, phase: CleanupPhase, detail: String? = nil, blockedPath: URL? = nil) throws {
        var next = state
        if let index = next.sessions?.firstIndex(where: { $0.id == id }) {
            next.sessions?[index].phase = phase
            next.sessions?[index].detail = detail
            next.sessions?[index].blockedPath = blockedPath
        }
        try commit(next)
    }

    private func requireIdle() throws {
        guard !executingPlan else { throw LumaError.rejected("A cleanup plan is already running. Wait for it to finish before changing Activity.") }
    }

    private func trash(_ item: CleanupItem, plan: CleanupPlan, context: CleanupExecutionContext,
                       onDetail: @escaping @Sendable (ScanPulse) -> Void) throws -> CleanupRecord {
        return try NonMaterializingIO.perform {
            try Task.checkCancellation()
            // Whole-plan preflight has already checked this immutable selection.
            // Keep the durable intent before the final full validation and move,
            // without doing the same expensive validation twice in this method.
            var intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: nil,
                                       identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
            intent.planID = plan.id; intent.planSource = plan.source; intent.accountedBytes = plan.accountedBytes(for: item)
            var prepared = state; prepared.pending.append(intent); try commit(prepared)
            var moveStarted = false
            do {
                let pinned = try PinnedPath(item.url)
                try mutationCheckpoint?()
                try plan.validate(item, home: home, context: context, progress: onDetail)
                try pinned.revalidate(expected: item.identity.location)
                try Task.checkCancellation()
                onDetail(.init("Moving to macOS Trash", current: item.name))
                moveStarted = true
                let destination = try withExtendedLifetime(pinned) { try trashMover(item.url) }
                return try MutationOutcome.$preserving.withValue(true) {
                    try validateTrashLocation(destination, readPath: false)
                    var moved = state
                    if let index = moved.pending.firstIndex(where: { $0.id == intent.id }) { moved.pending[index].destination = destination }
                    try commit(moved)
                    do {
                        onDetail(.init("Verifying moved files", current: item.name))
                        let movedPin = try PinnedPath(destination)
                        guard UInt64(UInt32(bitPattern: movedPin.value.st_dev)) == item.identity.device,
                              movedPin.value.st_ino == item.identity.inode,
                              (movedPin.value.st_uid == getuid() || (item.ruleID == "application.exact-bundle" && movedPin.value.st_uid == 0)),
                              try Filesystem.inspect(destination, progress: { entries, bytes in
                                  onDetail(.init("Verifying moved files", current: item.name, entries: entries, bytes: bytes))
                              }, applicationBundle: item.ruleID == "application.exact-bundle").1 == item.identity else {
                            throw LumaError.rejected("The moved item could not be identified. Review the interrupted operation in Activity.")
                        }
                        try movedPin.revalidate()
                    } catch {
                        // macOS can allow the Trash move without granting read access to
                        // Trash. Preserve its returned location and the pre-move identity;
                        // Restore will still require a full identity check before moving.
                        guard GeneratedDataScanner.failureState(error) == .blocked else { throw error }
                    }
                    let record = intent.completedRecord(at: destination)
                    var completed = state; completed.records.insert(record, at: 0); completed.pending.removeAll { $0.id == intent.id }
                    try commit(completed)
                    return record
                }
            } catch {
                if !moveStarted {
                    var cancelled = state; cancelled.pending.removeAll { $0.id == intent.id }
                    try? commit(cancelled)
                }
                // Keep the durable intent. Recovery can identify a move even if the
                // process stopped before macOS returned its destination.
                recoveryDetails[intent.id] = error.localizedDescription
                throw error
            }
        }
    }

    public func restore(_ record: CleanupRecord) throws {
        try requireIdle()
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        try restoreStored(record)
    }

    private func restoreStored(_ record: CleanupRecord) throws {
        return try NonMaterializingIO.perform {
            try Task.checkCancellation()
            guard state.pending.isEmpty else { throw LumaError.rejected("Review interrupted operations in Activity first.") }
            guard let stored = state.records.first(where: { $0.id == record.id }), !stored.restored,
                  let expected = stored.identity else { throw LumaError.rejected("This older activity entry has no stored file identity. Restore it through Finder’s Trash.") }
            guard expected.location != nil else {
                throw LumaError.rejected("This older activity entry has no parent-chain evidence. Restore it through Finder’s Trash.")
            }
            try validateTrashLocation(stored.trashed)
            guard try Filesystem.inspect(stored.trashed, applicationBundle: stored.planSource == .applications && stored.original.pathExtension == "app").1 == expected else { throw LumaError.rejected("The item in Trash has changed or was replaced. Inspect it in Finder before restoring.") }
            try validateOriginalParent(stored.original, expected: expected)
            guard !exists(stored.original) else { throw LumaError.rejected("The original location is occupied. Restore using Finder to choose another location.") }
            let intent = JournalIntent(id: UUID(), action: .restore, original: stored.original, source: stored.trashed,
                                       destination: stored.original, identity: expected, bytes: stored.bytes, date: Date(), recordID: stored.id, planSource: stored.planSource)
            var prepared = state; prepared.pending.append(intent); try commit(prepared)
            var moveStarted = false
            do {
                let sourcePin = try PinnedPath(stored.trashed)
                let parentPin = try PinnedPath(stored.original.exactDeletingLastPathComponent())
                try validateTrashLocation(stored.trashed)
                guard try Filesystem.inspect(stored.trashed, applicationBundle: stored.planSource == .applications && stored.original.pathExtension == "app").1 == expected else { throw LumaError.rejected("The item changed before restore. Review it in Finder.") }
                try validateOriginalParent(stored.original, expected: expected)
                try mutationCheckpoint?()
                try Task.checkCancellation()
                try sourcePin.revalidate()
                try parentPin.revalidate()
                try validateOriginalParent(stored.original, expected: expected)
                guard !exists(stored.original), try Filesystem.inspect(stored.trashed, applicationBundle: stored.planSource == .applications && stored.original.pathExtension == "app").1 == expected else {
                    throw LumaError.rejected("The restore source changed or the destination is occupied.")
                }
                // Native, exclusive same-volume rename relative to pinned directories.
                // The source name can still be raced; verify the outcome and retain
                // the intent on uncertainty. Never fall back to overwriting/copying.
                try sourcePin.revalidate()
                try parentPin.revalidate()
                moveStarted = true
                let sourceParent = sourcePin.descriptors[sourcePin.descriptors.count - 2]
                let result = withExtendedLifetime((sourcePin, parentPin)) {
                    renameatx_np(sourceParent, stored.trashed.lastPathComponent,
                                 parentPin.descriptor, stored.original.lastPathComponent, UInt32(RENAME_EXCL))
                }
                guard result == 0 else {
                    throw PinnedPath.posixError()
                }
                try MutationOutcome.$preserving.withValue(true) {
                    restoreOutcomeCheckpoint?()
                    try parentPin.revalidate()
                    guard try Filesystem.inspect(stored.original, applicationBundle: stored.planSource == .applications && stored.original.pathExtension == "app").1 == expected else {
                        throw LumaError.rejected("The restored item could not be verified. Review Activity and Finder.")
                    }
                    var completed = state
                    if let index = completed.records.firstIndex(where: { $0.id == stored.id }) { completed.records[index].restored = true }
                    completed.pending.removeAll { $0.id == intent.id }; try commit(completed)
                }
            } catch {
                if !moveStarted {
                    var cancelled = state; cancelled.pending.removeAll { $0.id == intent.id }
                    try? commit(cancelled)
                }
                recoveryDetails[intent.id] = error.localizedDescription; throw error
            }
        }
    }

    public func reviewUndo(sessionID: UUID) throws -> UndoReview {
        _ = try reconcile()
        try requireIdle()
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        guard state.pending.isEmpty else { throw LumaError.rejected("Resolve interrupted operations before reviewing Undo.") }
        guard (state.sessions ?? []).contains(where: { $0.id == sessionID }) || state.records.contains(where: { $0.planID == sessionID }) else {
            throw LumaError.rejected("This cleanup session is unavailable.")
        }
        // Exact path byte order, reversed: children would precede parents. Plans
        // reject overlapping paths; no parent creation or overwrite is allowed.
        let records = state.records.filter { $0.planID == sessionID }.sorted {
            $1.original.path.utf8.lexicographicallyPrecedes($0.original.path.utf8)
        }
        let items = try NonMaterializingIO.perform { records.map(undoItem) }
        return UndoReview(id: UUID(), sessionID: sessionID, items: items)
    }

    private func undoItem(_ record: CleanupRecord) -> UndoReviewItem {
        func item(_ status: UndoEligibility, _ detail: String) -> UndoReviewItem {
            UndoReviewItem(record: record, eligibility: status, detail: detail)
        }
        if record.restored { return item(.restored, "Already restored") }
        guard let identity = record.identity, identity.location != nil else { return item(.unavailable, "Missing identity or parent evidence; use Finder.") }
        do {
            if exists(record.original) { return item(.occupied, "Original destination is occupied; use Finder to choose another location.") }
            try validateTrashLocation(record.trashed)
            guard try Filesystem.inspect(record.trashed, applicationBundle: record.planSource == .applications && record.original.pathExtension == "app").1 == identity else { return item(.changed, "Trash contents changed; inspect in Finder.") }
            try validateOriginalParent(record.original, expected: identity)
            return item(.eligible, "Eligible for verified restore")
        } catch {
            return item(GeneratedDataScanner.failureState(error) == .missing ? .missing : .unavailable, error.localizedDescription)
        }
    }

    public func undo(_ review: UndoReview,
                     onProgress: @Sendable (CleanupProgress) async -> Void = { _ in }) async throws {
        try requireIdle()
        executingPlan = true; defer { executingPlan = false }
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        guard state.pending.isEmpty else { throw LumaError.rejected("Resolve interrupted operations before Undo.") }
        guard !(state.undoAttempts ?? []).contains(where: { $0.id == review.id }) else { throw LumaError.rejected("Review Undo again before another attempt.") }
        let ids = review.eligibleIDs
        guard !ids.isEmpty, Set(ids).count == ids.count,
              ids.allSatisfy({ id in state.records.contains { $0.id == id && $0.planID == review.sessionID } }) else {
            throw LumaError.rejected("The reviewed Undo selection is unavailable.")
        }
        var next = state
        next.undoAttempts = (next.undoAttempts ?? []) + [UndoAttempt(id: review.id, sessionID: review.sessionID,
            date: Date(), recordIDs: ids, outcomes: [], phase: .validating)]
        try commit(next)
        let index = state.undoAttempts!.count - 1
        do {
            for id in ids {
                try Task.checkCancellation()
                guard let record = state.records.first(where: { $0.id == id }) else { throw LumaError.rejected("Activity changed; review Undo again.") }
                await onProgress(CleanupProgress(sessionID: review.sessionID, phase: .moving, current: record.original, completed: state.undoAttempts![index].outcomes.filter(\.restored).count, total: ids.count))
                try Task.checkCancellation()
                do {
                    try restoreStored(record)
                    var updated = state
                    updated.undoAttempts?[index].outcomes.append(UndoOutcome(recordID: id, restored: true, detail: "Restored"))
                    try commit(updated)
                    await onProgress(CleanupProgress(sessionID: review.sessionID, phase: .moving, current: record.original,
                        completed: state.undoAttempts![index].outcomes.filter(\.restored).count, total: ids.count))
                } catch {
                    var updated = state
                    let restored = state.records.contains { $0.id == id && $0.restored }
                    updated.undoAttempts?[index].outcomes.append(UndoOutcome(recordID: id, restored: restored,
                        detail: restored ? "Restored; verified in Activity." : error.localizedDescription))
                    try commit(updated)
                    // Unknown operations require reconciliation, never a retry.
                    if error is CancellationError || !state.pending.isEmpty { throw error }
                }
            }
            var updated = state
            let allRestored = updated.undoAttempts![index].outcomes.allSatisfy(\.restored)
            updated.undoAttempts?[index].phase = allRestored ? .completed : .partial
            try commit(updated)
        } catch {
            var updated = state
            updated.undoAttempts?[index].phase = state.pending.isEmpty ? .stopped : .recoveryNeeded
            try commit(updated)
            throw error
        }
    }

    public func reconcile() throws -> JournalSnapshot {
        return try MutationOutcome.$preserving.withValue(true) {
            try NonMaterializingIO.perform {
                try requireIdle()
                let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
                try reload()
                var next = state
                var changed = false
                for intent in state.pending {
                    do {
                        switch intent.action {
                        case .trash:
                            if try matches(intent.source, identity: intent.identity, applicationBundle: intent.planSource == .applications && intent.original.pathExtension == "app") {
                                next.pending.removeAll { $0.id == intent.id }; changed = true
                                continue // The recorded move did not happen; never retry it automatically.
                            }
                            if let destination = intent.destination {
                                try validateTrashLocation(destination)
                                if try matches(destination, identity: intent.identity, applicationBundle: intent.planSource == .applications && intent.original.pathExtension == "app") {
                                    if !next.records.contains(where: { $0.id == intent.id }) {
                                        next.records.insert(intent.completedRecord(at: destination), at: 0)
                                    }
                                    next.pending.removeAll { $0.id == intent.id }; changed = true
                                    continue
                                }
                            }
                            let trash = home.appendingPathComponent(".Trash")
                            try Filesystem.validatePath(trash)
                            let children = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
                            var candidates: [URL] = []
                            for child in children {
                                let attributes = try? Filesystem.attributes(child)
                                if (attributes?[.systemNumber] as? NSNumber)?.uint64Value == intent.identity.device,
                                   (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value == intent.identity.inode,
                                   try matches(child, identity: intent.identity, applicationBundle: intent.planSource == .applications && intent.original.pathExtension == "app") { candidates.append(child) }
                            }
                            guard candidates.count == 1, let destination = candidates.first else {
                                throw LumaError.rejected("The moved item could not be uniquely identified in Trash. Nothing will be retried automatically.")
                            }
                            if !next.records.contains(where: { $0.id == intent.id }) {
                                next.records.insert(intent.completedRecord(at: destination), at: 0)
                            }
                            next.pending.removeAll { $0.id == intent.id }; changed = true
                        case .restore:
                            guard let destination = intent.destination, let recordID = intent.recordID else { throw LumaError.rejected("Incomplete restore metadata; review it in Finder.") }
                            if try matches(destination, identity: intent.identity, applicationBundle: intent.planSource == .applications && intent.original.pathExtension == "app"), !exists(intent.source) {
                                if let index = next.records.firstIndex(where: { $0.id == recordID }) { next.records[index].restored = true }
                                next.pending.removeAll { $0.id == intent.id }; changed = true
                            } else if try matches(intent.source, identity: intent.identity, applicationBundle: intent.planSource == .applications && intent.original.pathExtension == "app") {
                                next.pending.removeAll { $0.id == intent.id }; changed = true
                            } else { throw LumaError.rejected("The interrupted restore cannot be verified. Check the original location and Trash in Finder.") }
                        }
                        recoveryDetails.removeValue(forKey: intent.id)
                    } catch { recoveryDetails[intent.id] = error.localizedDescription }
                }
                for index in (next.sessions ?? []).indices {
                    let session = next.sessions![index]
                    let count = next.records.filter { $0.planID == session.id }.count
                    let pending = next.pending.contains { $0.planID == session.id }
                    if !session.phase.isTerminal || session.phase == .recoveryNeeded {
                        next.sessions?[index].phase = pending ? .recoveryNeeded : count == session.paths.count ? .completed : count > 0 ? .partial : .stopped
                        changed = true
                    }
                }
                for index in (next.undoAttempts ?? []).indices where !next.undoAttempts![index].phase.isTerminal || next.undoAttempts![index].phase == .recoveryNeeded {
                    let attempt = next.undoAttempts![index]
                    let unresolved = next.pending.contains { $0.recordID.map(attempt.recordIDs.contains) == true }
                    for id in attempt.recordIDs {
                        if next.records.contains(where: { $0.id == id && $0.restored }) {
                            next.undoAttempts?[index].outcomes.removeAll { $0.recordID == id }
                            next.undoAttempts?[index].outcomes.append(UndoOutcome(recordID: id, restored: true, detail: "Restored; verified during recovery."))
                        }
                    }
                    let restored = next.undoAttempts![index].outcomes.filter(\.restored).count
                    next.undoAttempts?[index].phase = unresolved ? .recoveryNeeded : restored == attempt.recordIDs.count ? .completed : .stopped
                    changed = true
                }
                if changed { try commit(next) }
                return snapshot()
            }
        }
    }

    /// Acknowledgement changes only the journal, never files. The UI asks the
    /// user to inspect both locations before dismissing an unresolved intent.
    public func acknowledge(_ id: UUID) throws -> JournalSnapshot {
        try requireIdle()
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        var next = state; next.pending.removeAll { $0.id == id }; try commit(next)
        recoveryDetails.removeValue(forKey: id)
        return snapshot()
    }

    private func matches(_ path: URL, identity: FileIdentity, applicationBundle: Bool = false) throws -> Bool {
        do {
            let attributes = try Filesystem.attributes(path)
            guard (attributes[.systemNumber] as? NSNumber)?.uint64Value == identity.device,
                  (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == identity.inode else { return false }
            return try Filesystem.inspect(path, onFile: nil, legacyFingerprint: identity.location == nil, applicationBundle: applicationBundle).1 == identity
        } catch {
            if GeneratedDataScanner.failureState(error) == .missing { return false }
            throw error
        }
    }

    private static func hasEntry(_ path: URL) throws -> Bool {
        do { _ = try Filesystem.attributes(path); return true }
        catch { if GeneratedDataScanner.failureState(error) == .missing { return false }; throw error }
    }

    private func exists(_ path: URL) -> Bool {
        // An unreadable path is occupied, never permission to overwrite it.
        do { _ = try Filesystem.attributes(path); return true }
        catch { return GeneratedDataScanner.failureState(error) != .missing }
    }

    private func validateTrashLocation(_ path: URL, readPath: Bool = true) throws {
        let root = home.appendingPathComponent(".Trash").exactStandardizedFileURL
        guard !Filesystem.samePath(path, root), Filesystem.samePath(path.exactDeletingLastPathComponent(), root) else {
            throw LumaError.rejected("The Trash location could not be verified on this volume.")
        }
        if readPath { try Filesystem.validatePath(path) }
    }

    private func validateOriginalParent(_ original: URL, expected: FileIdentity) throws {
        let parent = original.exactDeletingLastPathComponent()
        let allowed = Filesystem.isWithin(original, root: home) || ApplicationInventory.contains(original, home: home)
        guard allowed, !Filesystem.isWithin(original, root: home.appendingPathComponent(".Trash")), !Filesystem.samePath(original, home) else {
            throw LumaError.rejected("The original path is outside supported restore locations.")
        }
        guard let location = expected.location else {
            throw LumaError.rejected("This older activity entry requires Restore through Finder.")
        }
        let pinned = try PinnedPath.validateParent(of: original, expected: location)
        try pinned.revalidate()
        let attributes = try Filesystem.attributes(parent)
        guard (attributes[.systemNumber] as? NSNumber)?.uint64Value == expected.device,
              (attributes[.type] as? FileAttributeType) == .typeDirectory else { throw LumaError.rejected("The original folder is unavailable or on a different volume.") }
    }

    private func ensureDirectory() throws {
        return try NonMaterializingIO.perform {
            var ancestor = directory
            while !(try Self.hasEntry(ancestor)) { ancestor = ancestor.exactDeletingLastPathComponent() }
            try Filesystem.validatePath(ancestor)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Filesystem.validatePath(directory)
        }
    }

    private func acquireLock() throws -> Int32 {
        return try NonMaterializingIO.perform {
            try ensureDirectory()
            let descriptor = open(directory.appendingPathComponent("operations.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                close(descriptor)
                throw LumaError.rejected("Another Luma operation is using Activity. Wait for it to finish, then check again.")
            }
            return descriptor
        }
    }

    private func reload() throws {
        if try Self.hasEntry(url) {
            try Filesystem.validatePath(url)
            let loaded = try JSONDecoder().decode(JournalState.self, from: Filesystem.readMetadata(url))
            guard loaded.version == 1 else { throw LumaError.rejected("Unsupported activity journal version.") }
            state = loaded
        }
    }

    private func commit(_ next: JournalState) throws {
        let started = Date()
        defer { Self.persistenceObserver?(Date().timeIntervalSince(started)) }
        return try MutationOutcome.$preserving.withValue(true) {
            try NonMaterializingIO.perform {
                try ensureDirectory()
                if exists(url) { try Filesystem.validatePath(url) }
                try journalWriteCheckpoint?()
                let data = try JSONEncoder().encode(next)
                let temporary = directory.appendingPathComponent(".operations-\(UUID().uuidString).tmp")
                let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                defer { close(descriptor); try? FileManager.default.removeItem(at: temporary) }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                try handle.write(contentsOf: data)
                guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
                state = next
            }
        }
    }
}
