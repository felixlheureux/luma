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
}

/// The operation intent reaches disk before any move. Completed history and
/// removal of its intent are committed together in one atomic state file.
public actor CleanupJournal {
    private let home: URL
    private let directory: URL
    private let url: URL
    private let trashMover: @Sendable (URL) throws -> URL
    private var state: JournalState
    private var recoveryDetails: [UUID: String] = [:]
    private var executingPlan = false
    private var mutationCheckpoint: (@Sendable () throws -> Void)?

    // Deterministic test synchronization; never supplies or bypasses validation.
    func setMutationCheckpoint(_ checkpoint: @escaping @Sendable () throws -> Void) {
        mutationCheckpoint = checkpoint
    }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL? = nil,
                trashMover: (@Sendable (URL) throws -> URL)? = nil) throws {
        self.home = home
        let directory = directory ?? home.appendingPathComponent("Library/Application Support/Luma")
        self.directory = directory; url = directory.appendingPathComponent("operations.json")
        self.trashMover = trashMover ?? Self.systemTrash
        if try Self.hasEntry(url) {
            try Filesystem.validatePath(url)
            let loaded = try JSONDecoder().decode(JournalState.self, from: Data(contentsOf: url))
            guard loaded.version == 1 else { throw LumaError.rejected("This activity journal uses an unsupported version. Cleanup is paused to preserve it.") }
            state = loaded
        } else {
            let legacy = directory.appendingPathComponent("history.json")
            if try Self.hasEntry(legacy) {
                try Filesystem.validatePath(legacy)
                state = JournalState(records: try JSONDecoder().decode([CleanupRecord].self, from: Data(contentsOf: legacy)))
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
        })
    }

    /// The only cleanup entry point. Hold the operation lock over the complete
    /// plan, including awaited UI context/progress callbacks and every move.
    public func execute(_ plan: CleanupPlan,
                        context: @Sendable () async throws -> CleanupExecutionContext = { await .current() },
                        onRecord: @Sendable (CleanupRecord) async -> Void = { _ in }) async throws -> [CleanupRecord] {
        try requireIdle()
        executingPlan = true; defer { executingPlan = false }
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        guard state.pending.isEmpty else { throw LumaError.rejected("Review interrupted operations in Activity before starting another cleanup.") }
        guard !state.records.contains(where: { $0.planID == plan.id }) else {
            throw LumaError.rejected("This cleanup plan has already been used. Prepare a new review before moving more items.")
        }
        let initialContext = try await context()
        try plan.preflight(home: home, context: initialContext)
        var completed: [CleanupRecord] = []
        for item in plan.items {
            try Task.checkCancellation()
            let currentContext = try await context()
            let record = try trash(item, plan: plan, context: currentContext)
            completed.append(record)
            // Commit first; cancellation must not lose evidence of a finished move.
            await onRecord(record)
        }
        return completed
    }

    private func requireIdle() throws {
        guard !executingPlan else { throw LumaError.rejected("A cleanup plan is already running. Wait for it to finish before changing Activity.") }
    }

    private func trash(_ item: CleanupItem, plan: CleanupPlan, context: CleanupExecutionContext) throws -> CleanupRecord {
        try plan.validate(item, home: home, context: context, checkDuplicateContent: false)
        var intent = JournalIntent(id: UUID(), action: .trash, original: item.url, source: item.url, destination: nil,
                                   identity: item.identity, bytes: item.bytes, date: Date(), recordID: nil)
        intent.planID = plan.id; intent.planSource = plan.source; intent.accountedBytes = plan.accountedBytes(for: item)
        var prepared = state; prepared.pending.append(intent); try commit(prepared)
        var moveStarted = false
        do {
            let pinned = try PinnedPath(item.url)
            try mutationCheckpoint?()
            try plan.validate(item, home: home, context: context)
            try pinned.revalidate(expected: item.identity.location)
            moveStarted = true
            let destination = try withExtendedLifetime(pinned) { try trashMover(item.url) }
            try validateTrashLocation(destination, readPath: false)
            var moved = state
            if let index = moved.pending.firstIndex(where: { $0.id == intent.id }) { moved.pending[index].destination = destination }
            try commit(moved)
            do {
                let movedPin = try PinnedPath(destination)
                guard UInt64(UInt32(bitPattern: movedPin.value.st_dev)) == item.identity.device,
                      movedPin.value.st_ino == item.identity.inode,
                      movedPin.value.st_uid == getuid(),
                      try Filesystem.inspect(destination).1 == item.identity else {
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

    public func restore(_ record: CleanupRecord) throws {
        try requireIdle()
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        guard state.pending.isEmpty else { throw LumaError.rejected("Review interrupted operations in Activity first.") }
        guard let stored = state.records.first(where: { $0.id == record.id }), !stored.restored,
              let expected = stored.identity else { throw LumaError.rejected("This older activity entry has no stored file identity. Restore it through Finder’s Trash.") }
        guard expected.location != nil else {
            throw LumaError.rejected("This older activity entry has no parent-chain evidence. Restore it through Finder’s Trash.")
        }
        try validateTrashLocation(stored.trashed)
        guard try Filesystem.inspect(stored.trashed).1 == expected else { throw LumaError.rejected("The item in Trash has changed or was replaced. Inspect it in Finder before restoring.") }
        try validateOriginalParent(stored.original, expected: expected)
        guard !exists(stored.original) else { throw LumaError.rejected("The original location is occupied. Restore using Finder to choose another location.") }
        let intent = JournalIntent(id: UUID(), action: .restore, original: stored.original, source: stored.trashed,
                                   destination: stored.original, identity: expected, bytes: stored.bytes, date: Date(), recordID: stored.id)
        var prepared = state; prepared.pending.append(intent); try commit(prepared)
        var moveStarted = false
        do {
            let sourcePin = try PinnedPath(stored.trashed)
            let parentPin = try PinnedPath(stored.original.exactDeletingLastPathComponent())
            try validateTrashLocation(stored.trashed)
            guard try Filesystem.inspect(stored.trashed).1 == expected else { throw LumaError.rejected("The item changed before restore. Review it in Finder.") }
            try validateOriginalParent(stored.original, expected: expected)
            try mutationCheckpoint?()
            try sourcePin.revalidate()
            try parentPin.revalidate()
            try validateOriginalParent(stored.original, expected: expected)
            guard !exists(stored.original), try Filesystem.inspect(stored.trashed).1 == expected else {
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
            try parentPin.revalidate()
            guard try Filesystem.inspect(stored.original).1 == expected else {
                throw LumaError.rejected("The restored item could not be verified. Review Activity and Finder.")
            }
            var completed = state
            if let index = completed.records.firstIndex(where: { $0.id == stored.id }) { completed.records[index].restored = true }
            completed.pending.removeAll { $0.id == intent.id }; try commit(completed)
        } catch {
            if !moveStarted {
                var cancelled = state; cancelled.pending.removeAll { $0.id == intent.id }
                try? commit(cancelled)
            }
            recoveryDetails[intent.id] = error.localizedDescription; throw error
        }
    }

    public func reconcile() throws -> JournalSnapshot {
        try requireIdle()
        let lock = try acquireLock(); defer { flock(lock, LOCK_UN); close(lock) }
        try reload()
        var next = state
        var changed = false
        for intent in state.pending {
            do {
                switch intent.action {
                case .trash:
                    if try matches(intent.source, identity: intent.identity) {
                        next.pending.removeAll { $0.id == intent.id }; changed = true
                        continue // The recorded move did not happen; never retry it automatically.
                    }
                    if let destination = intent.destination {
                        try validateTrashLocation(destination)
                        if try matches(destination, identity: intent.identity) {
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
                           try matches(child, identity: intent.identity) { candidates.append(child) }
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
                    if try matches(destination, identity: intent.identity), !exists(intent.source) {
                        if let index = next.records.firstIndex(where: { $0.id == recordID }) { next.records[index].restored = true }
                        next.pending.removeAll { $0.id == intent.id }; changed = true
                    } else if try matches(intent.source, identity: intent.identity) {
                        next.pending.removeAll { $0.id == intent.id }; changed = true
                    } else { throw LumaError.rejected("The interrupted restore cannot be verified. Check the original location and Trash in Finder.") }
                }
                recoveryDetails.removeValue(forKey: intent.id)
            } catch { recoveryDetails[intent.id] = error.localizedDescription }
        }
        if changed { try commit(next) }
        return snapshot()
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

    private func matches(_ path: URL, identity: FileIdentity) throws -> Bool {
        do {
            let attributes = try Filesystem.attributes(path)
            guard (attributes[.systemNumber] as? NSNumber)?.uint64Value == identity.device,
                  (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == identity.inode else { return false }
            return try Filesystem.inspect(path, onFile: nil, legacyFingerprint: identity.location == nil).1 == identity
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
        let allowed = Filesystem.isWithin(original, root: home) || parent.exactStandardizedFileURL.path == "/Applications"
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
        var ancestor = directory
        while !(try Self.hasEntry(ancestor)) { ancestor = ancestor.exactDeletingLastPathComponent() }
        try Filesystem.validatePath(ancestor)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Filesystem.validatePath(directory)
    }

    private func acquireLock() throws -> Int32 {
        try ensureDirectory()
        let descriptor = open(directory.appendingPathComponent("operations.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw LumaError.rejected("Another Luma operation is using Activity. Wait for it to finish, then check again.")
        }
        return descriptor
    }

    private func reload() throws {
        if try Self.hasEntry(url) {
            try Filesystem.validatePath(url)
            let loaded = try JSONDecoder().decode(JournalState.self, from: Data(contentsOf: url))
            guard loaded.version == 1 else { throw LumaError.rejected("Unsupported activity journal version.") }
            state = loaded
        }
    }

    private func commit(_ next: JournalState) throws {
        try ensureDirectory()
        if exists(url) { try Filesystem.validatePath(url) }
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
