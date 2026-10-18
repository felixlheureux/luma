import Foundation
import Darwin
import GRDB
import Testing
@testable import LumaCore

private struct IndexFixture {
    let home: URL
    var root: URL { home.appendingPathComponent("Data") }
    var cache: URL { home.appendingPathComponent("Analysis") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/index-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func file(_ path: String, _ text: String = "same fixture data") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func store() -> AnalysisIndex { AnalysisIndex(directory: cache, monitorEvents: false) }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Local analysis index") struct AnalysisIndexTests {
    @Test func cachedHashesNeverAuthorizeDuplicateRemoval() throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a"); _ = try f.file("b")
        let store = f.store(), first = try store.begin(root: f.root, version: "fixture")
        _ = try DuplicateScanner(root: f.root).scanResult(cache: first)
        #expect(try first.finish())
        // Deliberately poison only the disposable hash cache. Even a plausible
        // cached digest cannot substitute for current content at plan preflight.
        let queue = try DatabaseQueue(path: f.cache.appendingPathComponent("index.sqlite").path)
        try queue.write { db in
            for row in try Row.fetchAll(db, sql: "SELECT path, payload FROM entries") {
                let path: Data = row["path"], payload: Data = row["payload"]
                var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
                object["full"] = String(repeating: "a", count: 64)
                try db.execute(sql: "UPDATE entries SET payload = ? WHERE path = ?", arguments: [try JSONSerialization.data(withJSONObject: object), path])
            }
        }
        let warm = try store.begin(root: f.root, version: "fixture")
        let result = try DuplicateScanner(root: f.root).scanResult(cache: warm)
        let group = try #require(result.duplicates.first), item = try #require(group.items.first)
        #expect(warm.reusedHashes == 4)
        let plan = try CleanupPlan(items: [item], authorizedRoots: [f.root], duplicateGroups: [group], source: .duplicates)
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: CleanupExecutionContext()) }
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "same fixture data")
    }

    @Test func persistentHashHitsMatchFreshResultsAcrossRestart() throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a"); _ = try f.file("b")
        let cold = try DuplicateScanner(root: f.root).scanResult()
        do {
            let cache = try f.store().begin(root: f.root, version: "fixture")
            let first = try DuplicateScanner(root: f.root).scanResult(cache: cache)
            #expect(first.duplicates.map(\.id) == cold.duplicates.map(\.id))
            #expect(cache.reusedHashes == 0)
            #expect(try cache.finish())
        }
        let warm = try f.store().begin(root: f.root, version: "fixture")
        let result = try DuplicateScanner(root: f.root).scanResult(cache: warm)
        #expect(result.duplicates.map(\.id) == cold.duplicates.map(\.id))
        #expect(warm.reusedHashes == 4)
        #expect(result.report.isComplete == cold.report.isComplete)
    }

    @Test func storageStillEnumeratesNewChildrenAndCountsHardLinksOnce() throws {
        let f = try IndexFixture(); defer { f.remove() }
        let file = try f.file("nested/a")
        try FileManager.default.linkItem(at: file, to: f.root.appendingPathComponent("alias"))
        let store = f.store(), first = try store.begin(root: f.root, version: "fixture")
        _ = try StorageIndex.scan(root: f.root, cache: first)
        #expect(try first.finish())
        let warm = try store.begin(root: f.root, version: "fixture")
        _ = try StorageIndex.scan(root: f.root, cache: warm)
        #expect(warm.reusedMetadata == 4)
        _ = try f.file("nested/new", "new bytes")
        let changed = try store.begin(root: f.root, version: "fixture")
        let indexed = try StorageIndex.scan(root: f.root, cache: changed)
        let cold = try StorageIndex.scan(root: f.root)
        #expect(indexed.nodes.keys.sorted() == cold.nodes.keys.sorted())
        #expect(indexed.nodes[indexed.rootID]?.bytes == cold.nodes[cold.rootID]?.bytes)
        #expect(indexed.nodes[indexed.rootID]?.bytes == Int64("same fixture data".utf8.count + "new bytes".utf8.count))
    }

    @Test func missedEventsAndRestoredMtimeCannotReuseChangedContent() throws {
        let f = try IndexFixture(); defer { f.remove() }
        let a = try f.file("a"), b = try f.file("b")
        let store = f.store(), first = try store.begin(root: f.root, version: "fixture")
        _ = try DuplicateScanner(root: f.root).scanResult(cache: first)
        #expect(try first.finish())
        let time = try #require(FileManager.default.attributesOfItem(atPath: b.path)[.modificationDate] as? Date)
        try Data("different content".utf8).write(to: b)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: b.path)
        let next = try store.begin(root: f.root, version: "fixture")
        let result = try DuplicateScanner(root: f.root).scanResult(cache: next)
        #expect(result.duplicates.isEmpty)
        let item = try Filesystem.item(a, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review")
        #expect(try next.cachedHash(item, partial: false) != nil)
        #expect(try Filesystem.hash(a) != Filesystem.hash(b))
    }

    @Test func ruleChangeRootReplacementAndEventLossInvalidateEntries() throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a"); _ = try f.file("b")
        let store = f.store(), first = try store.begin(root: f.root, version: "v1")
        _ = try DuplicateScanner(root: f.root).scanResult(cache: first)
        #expect(try first.finish())
        #expect(try store.begin(root: f.root, version: "v2").entries.isEmpty)
        store.invalidate(root: f.root)
        let dropped = try store.begin(root: f.root, version: "v1")
        #expect(dropped.entries.isEmpty && dropped.invalidated)
        try FileManager.default.moveItem(at: f.root, to: f.home.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        #expect(try store.begin(root: f.root, version: "v1").entries.isEmpty)
    }

    @Test func clearingPreservesOtherDataAndPreventsInflightRepopulation() throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a"); _ = try f.file("b")
        let activity = f.home.appendingPathComponent("Activity.json"), ignores = f.home.appendingPathComponent("ignores.json")
        try Data("activity fixture".utf8).write(to: activity)
        try Data("ignore fixture".utf8).write(to: ignores)
        let store = f.store(), running = try store.begin(root: f.root, version: "fixture")
        _ = try DuplicateScanner(root: f.root).scanResult(cache: running)
        try store.clear()
        #expect(try !running.finish())
        #expect(try store.begin(root: f.root, version: "fixture").entries.isEmpty)
        #expect(try String(contentsOf: activity, encoding: .utf8) == "activity fixture")
        #expect(try String(contentsOf: ignores, encoding: .utf8) == "ignore fixture")
        #expect(try String(contentsOf: f.root.appendingPathComponent("a"), encoding: .utf8) == "same fixture data")
    }

    @Test func providerAndDeniedPathsCannotBeResurrectedFromCache() async throws {
        let f = try IndexFixture(); defer { f.remove() }
        let a = try f.file("a"); _ = try f.file("b")
        let store = f.store(), first = try store.begin(root: f.root, version: "fixture")
        _ = try StorageIndex.scan(root: f.root, cache: first)
        #expect(try first.finish())
        try FilesystemAccess.$restriction.withValue({ url in url.path == a.path ? .providerManaged : .local }) {
            let next = try store.begin(root: f.root, version: "fixture")
            let result = try StorageIndex.scan(root: f.root, cache: next)
            #expect(result.nodes[a.path]?.accessCapability == .providerManaged)
            #expect(result.nodes[a.path]?.isComplete == false)
        }
        #expect(chmod(a.path, 0) == 0)
        defer { _ = chmod(a.path, 0o600) }
        let denied = try DuplicateScanner(root: f.root).scanResult(cache: store.begin(root: f.root, version: "fixture"))
        #expect(denied.duplicates.isEmpty)
        #expect(!denied.report.isComplete)
    }

    @Test func cancellationDoesNotCommitIncompleteGeneration() async throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a")
        let store = f.store()
        let task = Task {
            let session = try store.begin(root: f.root, version: "fixture")
            withUnsafeCurrentTask { $0?.cancel() }
            return try session.finish()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try store.begin(root: f.root, version: "fixture").entries.isEmpty)
    }

    @Test func corruptDatabaseAndFailedMigrationFallBackAndCanBeCleared() async throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("a")
        try FileManager.default.createDirectory(at: f.cache, withIntermediateDirectories: true)
        let path = f.cache.appendingPathComponent("index.sqlite")
        try Data("not a database".utf8).write(to: path)
        let store = f.store()
        let result = try await ScanEngine.run(.init(.storage, root: f.root), analysisIndex: store)
        #expect(result.storageIndex?.nodes.count == 2)
        #expect(result.analysisCache?.state == .unavailable)
        try store.clear()
        do {
            let queue = try DatabaseQueue(path: path.path)
            try await queue.write { db in try db.execute(sql: "CREATE TABLE roots (wrong_schema TEXT)") }
        }
        let failed = try await ScanEngine.run(.init(.storage, root: f.root), analysisIndex: f.store())
        #expect(failed.storageIndex?.nodes.count == 2)
        #expect(failed.analysisCache?.state == .unavailable)
        try store.clear()
        #expect(try store.begin(root: f.root, version: "fixture").entries.isEmpty)
    }

    @Test func v1MigratesWithoutTrustingOlderRecords() throws {
        let f = try IndexFixture(); defer { f.remove() }
        try FileManager.default.createDirectory(at: f.cache, withIntermediateDirectories: true)
        do {
            let queue = try DatabaseQueue(path: f.cache.appendingPathComponent("index.sqlite").path)
            var migrator = DatabaseMigrator()
            migrator.registerMigration("analysis-v1") { db in
                try db.execute(sql: "CREATE TABLE roots (path BLOB PRIMARY KEY NOT NULL, anchor BLOB NOT NULL, version TEXT NOT NULL, updated REAL NOT NULL)")
                try db.execute(sql: "CREATE TABLE entries (root BLOB NOT NULL REFERENCES roots(path) ON DELETE CASCADE, path BLOB NOT NULL, fingerprint BLOB NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(root, path))")
                try db.execute(sql: "INSERT INTO roots VALUES (?, ?, 'v1', 0)", arguments: [Data(f.root.path.utf8), Data()])
                try db.execute(sql: "INSERT INTO entries VALUES (?, ?, ?, ?)", arguments: [Data(f.root.path.utf8), Data("old".utf8), Data(), Data()])
            }
            try migrator.migrate(queue)
        }
        let session = try f.store().begin(root: f.root, version: "fixture")
        #expect(session.entries.isEmpty)
        _ = try StorageIndex.scan(root: f.root, cache: session)
        #expect(try session.finish())
    }

    @Test func unsafeDatabaseLinkCannotReadOrClearExternalData() throws {
        let f = try IndexFixture(); defer { f.remove() }
        let protected = try f.file("personal")
        try FileManager.default.createDirectory(at: f.cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.cache.appendingPathComponent("index.sqlite"), withDestinationURL: protected)
        #expect(throws: (any Error).self) { try f.store().begin(root: f.root, version: "fixture") }
        #expect(throws: (any Error).self) { try f.store().clear() }
        #expect(try String(contentsOf: protected, encoding: .utf8) == "same fixture data")
    }

    @Test func newerSchemaIsRejectedWithoutAttemptingDowngrade() throws {
        let f = try IndexFixture(); defer { f.remove() }
        _ = try f.file("personal")
        try FileManager.default.createDirectory(at: f.cache, withIntermediateDirectories: true)
        do {
            let queue = try DatabaseQueue(path: f.cache.appendingPathComponent("index.sqlite").path)
            try queue.write { db in
                try db.execute(sql: "CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('future-schema')")
            }
        }
        let store = f.store()
        #expect(throws: (any Error).self) { try store.begin(root: f.root, version: "fixture") }
        try store.clear()
        #expect(try store.begin(root: f.root, version: "fixture").entries.isEmpty)
        #expect(try String(contentsOf: f.root.appendingPathComponent("personal"), encoding: .utf8) == "same fixture data")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMA_INDEX_BENCHMARK"] == "1"))
    func benchmark() throws {
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/index-benchmark-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<600 {
            let directory = root.appendingPathComponent("folder-\(index / 30)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: UInt8(index % 251), count: 64).write(to: directory.appendingPathComponent("file-\(index)"))
        }
        let content = Data(repeating: 42, count: 8 * 1024 * 1024)
        for index in 0..<16 { try content.write(to: root.appendingPathComponent("copy-\(index)")) }
        for run in 0..<2 {
            let start = Date()
            let storage = try StorageIndex.scan(root: root)
            let storageTime = Date().timeIntervalSince(start)
            let hashStart = Date()
            let duplicates = try DuplicateScanner(root: root).scanResult()
            print("INDEX_BASELINE run=\(run) nodes=\(storage.nodes.count) storage=\(storageTime) duplicates=\(Date().timeIntervalSince(hashStart)) groups=\(duplicates.duplicates.count)")
        }
        let store = AnalysisIndex(directory: home.appendingPathComponent("Cache"), monitorEvents: false)
        for run in 0..<2 {
            let storageCache = try store.begin(root: root, version: "benchmark")
            let start = Date()
            let storage = try StorageIndex.scan(root: root, cache: storageCache)
            _ = try storageCache.finish()
            let storageTime = Date().timeIntervalSince(start)
            let hashes = try store.begin(root: root, version: "benchmark")
            let hashStart = Date()
            let duplicates = try DuplicateScanner(root: root).scanResult(cache: hashes)
            _ = try hashes.finish()
            print("INDEX_CACHED run=\(run) nodes=\(storage.nodes.count) storage=\(storageTime) metadataHits=\(storageCache.reusedMetadata) duplicates=\(Date().timeIntervalSince(hashStart)) hashHits=\(hashes.reusedHashes) groups=\(duplicates.duplicates.count)")
            if run == 1 { #expect(hashes.reusedHashes == 1232) }
        }
    }
}
