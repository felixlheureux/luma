import Foundation
import Testing
@testable import LumaCore

private struct BackupFixture: Sendable {
    let home: URL
    var root: URL { DeviceBackups.location(home: home) }
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    init(createRoot: Bool = true) throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/device-backups-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if createRoot { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    }
    func url(_ key: String) -> URL { root.appendingPathComponent(String(repeating: key, count: 40)) }
    @discardableResult func data(_ backup: URL, _ path: String, _ data: Data = Data("opaque fixture".utf8)) throws -> URL {
        let url = backup.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func plist(_ backup: URL, _ filename: String, _ object: [String: Any]) throws {
        try data(backup, filename, PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
    }
    @discardableResult func complete(_ key: String = "a", encrypted: Bool = false, name: String = "Fixture iPhone") throws -> URL {
        let backup = url(key)
        try plist(backup, "Info.plist", ["Device Name": name, "Last Backup Date": Self.date, "Serial Number": "PRIVATE-SERIAL", "IMEI": "PRIVATE-IMEI", "Target Identifier": "PRIVATE-ID"])
        try plist(backup, "Manifest.plist", ["IsEncrypted": encrypted, "Version": "9.1"])
        try plist(backup, "Status.plist", ["SnapshotState": "finished", "Version": "3.3", "Date": Self.date])
        try data(backup, "Manifest.db", Data("not an opened SQLite database".utf8))
        try data(backup, "00/0000000000000000000000000000000000000000", Data("irreplaceable opaque data".utf8))
        return backup
    }
    func scan(activity: DeviceBackupActivity = .unknown, ignored: Set<String> = [], limit: Int = 200_000) throws -> DeviceBackupInventory {
        try DeviceBackups.scan(home: home, ignoredPaths: ignored, activity: { activity }, entryLimit: limit)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
private final class BackupOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

private final class BackupReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func record(_ url: URL) { lock.lock(); defer { lock.unlock() }; paths.append(url.lastPathComponent) }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
}

@Suite("Local device backup inspection") struct DeviceBackupTests {
    @Test func recognizedMetadataShowsNamesDatesEncryptionAndLogicalSize() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let first = try f.complete()
        try f.complete("b", encrypted: true, name: "Fixture iPad")
        let inventory = try f.scan()
        #expect(inventory.backups.count == 2)
        #expect(inventory.backups[0].deviceName == "Fixture iPhone")
        #expect(inventory.backups[0].backupDate == BackupFixture.date)
        #expect(inventory.backups[0].encrypted == false && inventory.backups[1].encrypted == true)
        #expect(inventory.backups.allSatisfy { $0.state == .reportedFinished && $0.safety == .userData })
        #expect(inventory.backups[0].bytes == (try Filesystem.inspect(first).0))
        #expect(inventory.report.items.isEmpty)
        #expect(inventory.knownBytes == inventory.backups.reduce(0) { $0 + ($1.bytes ?? 0) })
    }

    @Test func missingLocationEmptyLocationEmptyBackupAndPartialAreDistinct() throws {
        let absent = try BackupFixture(createRoot: false); defer { absent.remove() }
        #expect(try absent.scan().locationState == .missing)
        let f = try BackupFixture(); defer { f.remove() }
        #expect(try f.scan().locationState == .empty)
        try FileManager.default.createDirectory(at: f.url("a"), withIntermediateDirectories: true)
        try f.data(f.url("b"), "opaque-data")
        let inventory = try f.scan()
        #expect(inventory.backups[0].state == .empty && inventory.backups[0].bytes == 0)
        #expect(inventory.backups[1].state == .incomplete && inventory.backups[1].bytes != nil)
        #expect(inventory.backups[1].deviceName == nil && inventory.backups[1].backupDate == nil)
    }

    @Test func corruptWrongTypeUnknownVersionAndInProgressMetadataStayExplicit() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let corrupt = try f.complete("a"), wrong = try f.complete("b"), future = try f.complete("c"), partial = try f.complete("d")
        try f.data(corrupt, "Status.plist", Data("not a plist".utf8))
        try f.plist(wrong, "Manifest.plist", ["IsEncrypted": "true", "Version": "9.1"])
        try f.plist(future, "Manifest.plist", ["IsEncrypted": false, "Version": "100.0"])
        try f.plist(partial, "Status.plist", ["SnapshotState": "in-progress", "Version": "3.3", "Date": BackupFixture.date])
        let records = try f.scan().backups
        #expect(records.prefix(3).allSatisfy { $0.state == .unsupported })
        #expect(records[3].state == .incomplete)
        #expect(records.allSatisfy { $0.bytes != nil })
    }

    @Test func missingDatabaseNeverBecomesAReportedFinishedBackup() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        try FileManager.default.removeItem(at: backup.appendingPathComponent("Manifest.db"))
        #expect(try f.scan().backups.first?.state == .incomplete)
    }

    @Test func unknownNamesAndExcessiveMetadataCannotCreateRecognizedState() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        try FileManager.default.moveItem(at: backup, to: f.root.appendingPathComponent("Unrecognized"))
        let large = try f.complete("b")
        try f.data(large, "Info.plist", Data(repeating: 97, count: 1_048_577))
        #expect(try f.scan().backups.allSatisfy { $0.state == .unsupported })
    }

    @Test func onlyThreeSummaryPlistsAreReadAndDeniedPayloadCapabilitiesFailClosed() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete(encrypted: true)
        let reads = BackupReadLog()
        let initial = try DeviceBackups.$metadataReadObserver.withValue({ reads.record($0) }) { try f.scan() }
        #expect(initial.backups[0].state == .reportedFinished)
        #expect(Set(reads.snapshot()) == ["Info.plist", "Manifest.plist", "Status.plist"])
        for path in ["Manifest.db", "00/0000000000000000000000000000000000000000"] {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: backup.appendingPathComponent(path).path)
        }
        let inventory = try f.scan()
        #expect(inventory.backups[0].state == .unreadable)
        #expect(inventory.backups[0].bytes == nil)
        #expect(inventory.report.items.isEmpty)
    }

    @Test func deniedMetadataIsUnavailableRatherThanEmptyOrComplete() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: backup.appendingPathComponent("Info.plist").path)
        let inventory = try f.scan()
        #expect(inventory.backups[0].state == .unreadable && inventory.backups[0].bytes == nil)
        #expect(inventory.report.coverage.contains { $0.state == .blocked })
    }

    @Test func linksSharedFilesAndProviderChangesPreventCompleteInspection() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let linked = try f.complete("a"), shared = try f.complete("b"), provider = try f.complete("c")
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("link"), withDestinationURL: shared)
        try FileManager.default.linkItem(at: shared.appendingPathComponent("Manifest.db"), to: shared.appendingPathComponent("shared"))
        try FilesystemAccess.$restriction.withValue({ url in Filesystem.isWithin(url, root: provider) ? .providerManaged : .local }) { () throws -> Void in
            let inventory = try f.scan()
            #expect(inventory.backups.allSatisfy { $0.state == .unreadable && $0.bytes == nil })
            #expect(inventory.report.items.isEmpty)
        }
    }

    @Test func ignoresApplyToRootWholeBackupsAndInternalFiles() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        #expect(try f.scan(ignored: [f.root.path]).locationState == .skipped)
        #expect(try f.scan(ignored: [backup.path]).backups.first?.state == .ignored)
        #expect(try f.scan(ignored: [backup.appendingPathComponent("00").path]).backups.first?.state == .unreadable)
        let reads = BackupReadLog()
        let ignoredSummary = backup.appendingPathComponent("Status.plist")
        let inventory = try DeviceBackups.$metadataReadObserver.withValue({ reads.record($0) }) { try f.scan(ignored: [ignoredSummary.path]) }
        #expect(inventory.backups.first?.state == .unreadable)
        #expect(!reads.snapshot().contains("Status.plist"))
    }

    @Test func metadataChangesDuringSizingInvalidateRecordedState() throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        for index in 0..<130 { try f.data(backup, "01/\(index)") }
        let once = BackupOnce()
        let inventory = try DeviceBackups.scan(home: f.home, activity: { .unknown }, emit: { event in
            if case .progress(let pulse) = event, pulse.entries >= 128, once.take() {
                try? f.plist(backup, "Info.plist", ["Device Name": "Changed", "Last Backup Date": BackupFixture.date])
            }
        })
        #expect(inventory.backups[0].state == .changed && inventory.backups[0].bytes == nil)
    }

    @Test func namesAreSanitizedAndUnnecessaryDeviceIdentifiersAreNotDisplayed() throws {
        let f = try BackupFixture(); defer { f.remove() }
        try f.complete(name: "Fixture\niPhone")
        let inventory = try f.scan()
        #expect(inventory.backups[0].title == "FixtureiPhone")
        let displayed = inventory.backups.map { $0.title + $0.detail }.joined() + inventory.report.notices.joined()
        #expect(!displayed.contains("PRIVATE-SERIAL") && !displayed.contains("PRIVATE-IMEI") && !displayed.contains("PRIVATE-ID"))
        #expect(!displayed.contains(String(repeating: "a", count: 40)))
    }

    @Test func processAbsenceNeverClaimsIdlenessAndProvidersCannotEnableCleanup() throws {
        #expect(DeviceBackupActivity.classify(nil) == .unknown)
        #expect(DeviceBackupActivity.classify([]) == .unknown)
        #expect(DeviceBackupActivity.classify(["/usr/bin/unknown-backup-tool"]) == .unknown)
        #expect(DeviceBackupActivity.classify(["/usr/libexec/AMPDevicesAgent"]) == .toolsDetected)
        let f = try BackupFixture(); defer { f.remove() }
        try f.complete()
        for state in [DeviceBackupActivity.unknown, .toolsDetected] { #expect(try f.scan(activity: state).report.items.isEmpty) }
    }

    @Test func allBackupPathsRemainBlockedAtTheCoreIncludingForgedRulesAndInternalChunks() async throws {
        let f = try BackupFixture(); defer { f.remove() }
        let backup = try f.complete()
        let engine = SafetyEngine(home: f.home)
        for path in [backup, backup.appendingPathComponent("Info.plist"), backup.appendingPathComponent("00")] {
            #expect(!engine.permitsManualSelection(at: path, authorizedRoots: [f.root, backup]))
            for rule in ["manual.folder-review", "backup.whole.v1", "developer.homebrew.cache"] {
                let item = try Filesystem.item(path, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: rule)
                #expect(throws: (any Error).self) { try engine.validate(item, authorizedRoots: [f.root, backup], activity: CleanupActivity(tools: [])) }
                let journal = try CleanupJournal(home: f.home, trashMover: { _ in throw LumaError.rejected("Mover must never run") })
                let plan = try CleanupPlan(items: [item], authorizedRoots: [f.root, backup])
                await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext() }) }
                #expect(await journal.snapshot().records.isEmpty)
                #expect(await journal.snapshot().unresolved.isEmpty)
                #expect(FileManager.default.fileExists(atPath: path.path))
            }
        }
    }

    @Test func limitsCancellationAndScanEnginePreserveReadOnlyEvidence() async throws {
        let f = try BackupFixture(); defer { f.remove() }
        try f.complete()
        #expect(try f.scan(limit: 1).backups[0].state == .unreadable)
        let result = try await ScanEngine.run(.init(.deviceBackups), home: f.home)
        #expect(result.deviceBackups?.backups.count == 1 && result.report.items.isEmpty)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try f.scan() }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
