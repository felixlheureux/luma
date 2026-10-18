import Foundation
import Darwin
import GRDB

public struct AnalysisCacheSummary: Sendable {
    public enum State: Sendable { case updated, changed, unavailable, notSaved }
    public let state: State
    public var reusedMetadata = 0
    public var reusedHashes = 0
}

/// Disposable observations only. No journal, preferences, CleanupItem or removal
/// permission is persisted here. All callers still enumerate and validate paths.
public final class AnalysisIndex: @unchecked Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/app.luma.mac/Analysis")
    }
    let directory: URL
    private let monitorEvents: Bool
    private let lock = NSLock()
    private var database: DatabaseQueue?
    private var epoch = UUID()
    private var monitors: [Data: AnalysisEvents] = [:]
    private var savedEvents: [Data: UInt64] = [:]
    public init(directory: URL = AnalysisIndex.defaultDirectory) { self.directory = directory; self.monitorEvents = true }
    init(directory: URL, monitorEvents: Bool) { self.directory = directory; self.monitorEvents = monitorEvents }

    private func open() throws -> DatabaseQueue {
        if let database { return database }
        try NonMaterializingIO.perform {
            // Validate the existing chain before creating this app-owned folder.
            var ancestor = directory
            while !FileManager.default.fileExists(atPath: ancestor.path) { ancestor = ancestor.deletingLastPathComponent() }
            try Filesystem.validatePath(ancestor)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let pin = try PinnedPath(directory)
            guard pin.value.st_uid == getuid() else { throw LumaError.rejected("Analysis cache has a different owner.") }
            for name in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm", "index.sqlite-journal"] {
                let url = directory.appendingPathComponent(name)
                var value = stat()
                if lstat(url.path, &value) == 0 {
                    guard value.st_mode & S_IFMT == S_IFREG, value.st_uid == getuid(), value.st_nlink == 1 else {
                        throw LumaError.rejected("Analysis cache contains an unsafe database path.")
                    }
                    try Filesystem.validatePath(url)
                } else if errno != ENOENT { throw PinnedPath.posixError() }
            }
            try pin.revalidate()
        }
        var configuration = Configuration()
        configuration.busyMode = .timeout(1)
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("index.sqlite").path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("analysis-v1") { db in
            try db.execute(sql: "CREATE TABLE roots (path BLOB PRIMARY KEY NOT NULL, anchor BLOB NOT NULL, version TEXT NOT NULL, updated REAL NOT NULL)")
            try db.execute(sql: "CREATE TABLE entries (root BLOB NOT NULL REFERENCES roots(path) ON DELETE CASCADE, path BLOB NOT NULL, fingerprint BLOB NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(root, path))")
        }
        migrator.registerMigration("analysis-v2-generation") { db in
            try db.execute(sql: "ALTER TABLE roots ADD COLUMN generation TEXT NOT NULL DEFAULT ''")
            // Earlier cached observations have no generation boundary.
            try db.execute(sql: "DELETE FROM entries")
        }
        guard try !queue.read({ try migrator.hasBeenSuperseded($0) }) else {
            throw LumaError.rejected("Analysis cache was created by a newer schema; use fresh analysis or clear the cache.")
        }
        try migrator.migrate(queue)
        guard try queue.read({ try String.fetchOne($0, sql: "PRAGMA quick_check(1)") }) == "ok" else {
            throw LumaError.rejected("Analysis cache failed its integrity check.")
        }
        database = queue
        return queue
    }

    private struct RootAnchor: Codable {
        let location: FileLocation
        let volume: String
        let birthSeconds: Int64
        let birthNanoseconds: Int64
    }
    private static func anchor(for pin: PinnedPath) throws -> Data {
        try NonMaterializingIO.perform {
            var filesystem = statfs()
            guard fstatfs(pin.descriptor, &filesystem) == 0 else { throw PinnedPath.posixError() }
            let kind = withUnsafeBytes(of: filesystem.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            // Coarse or unsupported change-time semantics must not authorize hash
            // reuse after same-size edits with a restored modification timestamp.
            guard kind == "apfs" else { throw LumaError.rejected("Saved analysis reuse requires a local APFS volume.") }
            var url = pin.url; url.removeAllCachedResourceValues()
            guard let volume = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
                throw LumaError.rejected("Volume identity unavailable; use fresh analysis.")
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return try encoder.encode(RootAnchor(location: pin.location, volume: volume,
                birthSeconds: Int64(pin.value.st_birthtimespec.tv_sec), birthNanoseconds: Int64(pin.value.st_birthtimespec.tv_nsec)))
        }
    }

    func begin(root: URL, version: String) throws -> AnalysisIndexSession {
        try Task.checkCancellation()
        let pin = try PinnedPath(root)
        guard pin.value.st_mode & S_IFMT == S_IFDIR else { throw LumaError.rejected("Choose a local folder.") }
        let key = Data(pin.url.path.utf8)
        let anchor = try Self.anchor(for: pin)
        lock.lock(); defer { lock.unlock() }
        let queue = try open()
        if monitors[key] == nil {
            // A bounded set of explicitly scanned roots; evicting a stream only
            // loses hints, since every future scan fully revalidates metadata.
            if monitors.count >= 8, let old = monitors.keys.first { monitors.removeValue(forKey: old); savedEvents.removeValue(forKey: old) }
            monitors[key] = AnalysisEvents(root: pin.url, enabled: monitorEvents)
        }
        let events = monitors[key]?.generation() ?? 0
        let invalidated = savedEvents[key].map { $0 != events } ?? false
        var entries: [Data: AnalysisIndexSession.Entry] = [:]
        try queue.read { db in
            guard !invalidated, let row = try Row.fetchOne(db, sql: "SELECT anchor, version FROM roots WHERE path = ? AND typeof(anchor) = 'blob' AND typeof(version) = 'text'", arguments: [key]),
                  row["anchor"] as Data == anchor, row["version"] as String == version else { return }
            for row in try Row.fetchAll(db, sql: "SELECT path, fingerprint, payload FROM entries WHERE root = ? AND typeof(path) = 'blob' AND typeof(fingerprint) = 'blob' AND typeof(payload) = 'blob' AND length(payload) <= 4096 AND length(fingerprint) <= 512 AND length(path) <= 16384 LIMIT 100001", arguments: [key]) {
                guard entries.count < 100_000 else { throw LumaError.rejected("Analysis cache entry limit exceeded.") }
                let payload: Data = row["payload"]
                guard payload.count <= 16_384 else { throw LumaError.rejected("Invalid analysis cache record.") }
                entries[row["path"]] = AnalysisIndexSession.Entry(fingerprint: row["fingerprint"], payload: try JSONDecoder().decode(AnalysisIndexSession.Payload.self, from: payload))
            }
        }
        return AnalysisIndexSession(store: self, root: pin.url, anchor: anchor, version: version,
            epoch: epoch, events: events, entries: entries, invalidated: invalidated)
    }

    fileprivate func commit(_ session: AnalysisIndexSession) throws -> Bool {
        try Task.checkCancellation()
        let pin = try PinnedPath(session.root)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard try Self.anchor(for: pin) == session.anchor else { return false }
        lock.lock(); defer { lock.unlock() }
        guard session.epoch == epoch, monitors[session.key]?.generation() == session.events else { return false }
        let queue = try open()
        try queue.write { db in
            try db.execute(sql: "DELETE FROM roots WHERE path = ?", arguments: [session.key])
            try db.execute(sql: "INSERT INTO roots(path, anchor, version, updated, generation) VALUES (?, ?, ?, ?, ?)",
                arguments: [session.key, session.anchor, session.version, Date().timeIntervalSince1970, UUID().uuidString])
            for (path, entry) in session.updated {
                try Task.checkCancellation()
                try db.execute(sql: "INSERT INTO entries(root, path, fingerprint, payload) VALUES (?, ?, ?, ?)",
                    arguments: [session.key, path, entry.fingerprint, try encoder.encode(entry.payload)])
            }
            try db.execute(sql: "DELETE FROM roots WHERE path NOT IN (SELECT path FROM roots ORDER BY updated DESC LIMIT 8)")
        }
        savedEvents[session.key] = session.events
        return true
    }

    /// Removing only the owned database and sidecar files also recovers a corrupt cache.
    /// Activity, ignores and all scanned data remain untouched.
    /// Epoch changes prevent an in-flight scan from repopulating a cleared cache.
    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        epoch = UUID(); monitors.removeAll(); savedEvents.removeAll()
        database = nil
        try NonMaterializingIO.perform {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            let pin = try PinnedPath(directory)
            guard pin.value.st_uid == getuid() else { throw LumaError.rejected("Analysis cache has a different owner.") }
            for name in ["index.sqlite-wal", "index.sqlite-shm", "index.sqlite-journal", "index.sqlite"] {
                var info = stat()
                if fstatat(pin.descriptor, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                    if errno == ENOENT { continue }
                    throw PinnedPath.posixError()
                }
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
                    throw LumaError.rejected("Unsafe analysis cache file; nothing else was removed.")
                }
                try pin.revalidate()
                guard unlinkat(pin.descriptor, name, 0) == 0 else { throw PinnedPath.posixError() }
            }
            try pin.revalidate()
        }
    }

    /// Event loss/reset/unmount is a root-wide invalidation, never a claim that
    /// unmentioned descendants stayed unchanged. Also used by generated fixtures.
    func invalidate(root: URL) {
        lock.lock(); defer { lock.unlock() }
        monitors[Data(root.exactStandardizedFileURL.path.utf8)]?.invalidate()
    }
}

struct IndexedStorageMetadata: Codable, Sendable {
    let package: Bool
    let hidden: Bool
    let created: Date?
}

/// Synchronous, worker-owned state. Nothing is committed on cancellation/failure.
final class AnalysisIndexSession {
    struct Payload: Codable {
        var metadata: IndexedStorageMetadata?
        var partial: String?
        var full: String?
    }
    struct Entry { let fingerprint: Data; var payload: Payload }
    let store: AnalysisIndex
    let root: URL
    var key: Data { Data(root.path.utf8) }
    let anchor: Data
    let version: String
    let epoch: UUID
    let events: UInt64
    let entries: [Data: Entry]
    var updated: [Data: Entry] = [:]
    var reusedHashes = 0
    var reusedMetadata = 0
    let invalidated: Bool
    init(store: AnalysisIndex, root: URL, anchor: Data, version: String, epoch: UUID, events: UInt64, entries: [Data: Entry], invalidated: Bool) {
        self.store = store; self.root = root; self.anchor = anchor; self.version = version
        self.epoch = epoch; self.events = events; self.entries = entries; self.invalidated = invalidated
    }

    /// Nanosecond change time detects content rewritten with a restored mtime.
    /// Permissions, ownership, flags, birth and link count are also significant.
    static func fingerprint(_ info: stat) -> Data {
        Data([info.st_dev.description, info.st_ino.description, info.st_size.description,
              info.st_mtimespec.tv_sec.description, info.st_mtimespec.tv_nsec.description,
              info.st_ctimespec.tv_sec.description, info.st_ctimespec.tv_nsec.description,
              info.st_birthtimespec.tv_sec.description, info.st_birthtimespec.tv_nsec.description,
              info.st_mode.description, info.st_uid.description, info.st_gid.description,
              info.st_flags.description, info.st_nlink.description].joined(separator: ":").utf8)
    }
    func entry(url: URL, info: stat) -> Entry {
        let key = Data(url.path.utf8), fingerprint = Self.fingerprint(info)
        if let value = updated[key] ?? entries[key], value.fingerprint == fingerprint { return value }
        return Entry(fingerprint: fingerprint, payload: Payload())
    }
    func metadata(url: URL, info: stat) -> IndexedStorageMetadata? {
        let value = entry(url: url, info: info)
        guard let metadata = value.payload.metadata else { return nil }
        updated[Data(url.path.utf8)] = value; reusedMetadata += 1
        return metadata
    }
    func recordMetadata(_ metadata: IndexedStorageMetadata, url: URL, info: stat) {
        guard updated.count < 100_000 else { return }
        var value = entry(url: url, info: info); value.payload.metadata = metadata
        updated[Data(url.path.utf8)] = value
    }
    func cachedHash(_ item: CleanupItem, partial: Bool) throws -> String? {
        try Task.checkCancellation()
        let key = Data(item.url.path.utf8)
        guard item.safety == .userData, let saved = updated[key] ?? entries[key],
              (partial ? saved.payload.partial : saved.payload.full) != nil else { return nil }
        return try NonMaterializingIO.perform {
            let pin = try PinnedPath(item.url)
            guard Filesystem.isWithin(pin.url, root: root), pin.value.st_mode & S_IFMT == S_IFREG,
                  UInt64(UInt32(bitPattern: pin.value.st_dev)) == item.identity.device,
                  pin.value.st_ino == item.identity.inode, pin.value.st_size == item.identity.size,
                  Date(timeIntervalSince1970: Double(pin.value.st_mtimespec.tv_sec) + Double(pin.value.st_mtimespec.tv_nsec) / 1e9) == item.identity.modified,
                  pin.location == item.identity.location else { return nil }
            let value = entry(url: pin.url, info: pin.value)
            guard let hash = partial ? value.payload.partial : value.payload.full,
                  hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
            try pin.revalidate()
            var after = stat()
            guard fstat(pin.descriptor, &after) == 0, Self.fingerprint(after) == value.fingerprint else { return nil }
            updated[Data(pin.url.path.utf8)] = value; reusedHashes += 1
            return hash
        }
    }
    func recordHash(_ hash: String, item: CleanupItem, partial: Bool, before: Data, after: Data) {
        guard updated.count < 100_000, before == after else { return }
        let key = Data(item.url.path.utf8)
        var value = updated[key] ?? entries[key] ?? Entry(fingerprint: before, payload: Payload())
        if value.fingerprint != before { value = Entry(fingerprint: before, payload: Payload()) }
        if partial { value.payload.partial = hash } else { value.payload.full = hash }
        updated[key] = value
    }
    func finish() throws -> Bool { try store.commit(self) }
}
