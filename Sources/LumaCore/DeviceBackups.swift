import Foundation
import CryptoKit
import Darwin

public enum DeviceBackupActivity: String, Sendable {
    case unknown = "Backup activity unknown"
    case toolsDetected = "Backup-related tools detected"
    public static func classify(_ paths: [String]?) -> Self {
        guard let paths else { return .unknown }
        let tools: Set<String> = ["ampdevicesagent", "ampdevicediscoveryagent", "applemobiledevicehelper", "itunes", "mobilebackup", "mobilebackup2", "idevicebackup", "idevicebackup2", "backupagent2"]
        return paths.contains { tools.contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased()) } ? .toolsDetected : .unknown
    }
    public static func collect() -> Self { classify(CleanupActivity.processPaths()) }
}

public enum DeviceBackupState: String, Sendable {
    case reportedFinished = "Metadata reports finished"
    case incomplete = "Incomplete or missing metadata"
    case unsupported = "Unrecognized or corrupt metadata"
    case empty = "Empty folder"
    case unreadable = "Inspection unavailable"
    case changed = "Changed during inspection"
    case ignored = "Ignored"
}

/// Observations only. There is deliberately no CleanupItem or removal flag that
/// an activity provider or finished marker can turn into cleanup authority.
public struct DeviceBackup: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let ordinal: Int
    public let deviceName: String?
    public let backupDate: Date?
    public let encrypted: Bool?
    public let bytes: Int64?
    public let state: DeviceBackupState
    public let detail: String
    public var title: String { deviceName ?? "Backup \(ordinal)" }
    public var safety: SafetyLevel { .userData }
}

public struct DeviceBackupInventory: Sendable {
    public let root: URL
    public let backups: [DeviceBackup]
    public let locationState: CoverageState
    public let activity: DeviceBackupActivity
    public let report: ScanReport
    public var knownBytes: Int64? {
        var total: Int64 = 0
        for backup in backups {
            let sum = total.addingReportingOverflow(backup.bytes ?? 0)
            guard !sum.overflow else { return nil }; total = sum.partialValue
        }
        return total
    }
}

public enum DeviceBackups {
    @TaskLocal static var metadataReadObserver: (@Sendable (URL) -> Void)?
    public static let removalExplanation = "Local device backups are inspection-only in Luma. Use Finder’s Manage Backups after checking which copies you need."
    public static func location(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
    }

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, ignoredPaths: Set<String> = [],
                            activity: @Sendable () -> DeviceBackupActivity = { .collect() },
                            entryLimit: Int = 200_000, emit: @escaping ScanEmitter = { _ in }) throws -> DeviceBackupInventory {
        try NonMaterializingIO.perform {
            let started = Date(), root = location(home: home), activity = activity()
            var report = ScanReport(), backups: [DeviceBackup] = []
            var visited = 0
            func ignored(_ url: URL) -> Bool { ignoredPaths.contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) } }
            func coverage(_ title: String, url: URL, state: CoverageState, detail: String, capability: FilesystemCapability? = nil) {
                let row = ScanCoverage(ruleID: "backups.inspection-only", title: title, path: url.path,
                    category: .storage, state: state, bytes: 0, detail: detail, accessCapability: capability)
                report.coverage.append(row); emit(.coverage(row))
                if state == .blocked || state == .skipped { report.isComplete = false; report.notices.append("\(title): \(detail)") }
            }
            func inventory(_ state: CoverageState) -> DeviceBackupInventory {
                report.visited = visited; report.duration = Date().timeIntervalSince(started)
                return .init(root: root, backups: backups, locationState: state, activity: activity, report: report)
            }
            try Task.checkCancellation()
            if ignored(root) {
                coverage("Local backups", url: root, state: .skipped, detail: "This location is ignored. No backup contents were inspected.")
                return inventory(.skipped)
            }
            let rootPin: PinnedPath
            do {
                rootPin = try PinnedPath(root)
                guard rootPin.value.st_mode & S_IFMT == S_IFDIR, rootPin.value.st_uid == getuid() else { throw BackupReadError.unavailable }
            } catch is CancellationError { throw CancellationError() }
            catch {
                let state = GeneratedDataScanner.failureState(error)
                let detail = state == .missing ? "The standard local backup folder is not present. This does not describe iCloud or relocated backups." : "The standard local backup folder could not be inspected. Review access or open it in Finder."
                coverage("Local backups", url: root, state: state, detail: detail, capability: (error as? FilesystemAccessError)?.capability)
                return inventory(state)
            }
            let names: [String]
            do { names = try PinnedPath.names(in: rootPin.descriptor, limit: 100).filter { !$0.hasPrefix(".") } }
            catch is CancellationError { throw CancellationError() }
            catch {
                coverage("Local backups", url: root, state: GeneratedDataScanner.failureState(error), detail: "Backup folders could not be listed, or the 100-entry location limit was reached.")
                return inventory(.skipped)
            }
            // Metadata-only sizing: no database, payload file or backup content
            // is opened for reading. The budget is shared by every backup.
            func measure(_ folder: URL) throws -> Int64 {
                func visit(_ url: URL, depth: Int) throws -> Int64 {
                    try Task.checkCancellation()
                    guard !ignored(url), visited < entryLimit, depth <= 64 else { throw BackupReadError.unavailable }
                    visited += 1
                    let pin = try PinnedPath(url)
                    guard pin.value.st_uid == getuid(), pin.value.st_dev == rootPin.value.st_dev else { throw BackupReadError.unavailable }
                    var size: Int64 = 0
                    if pin.value.st_mode & S_IFMT == S_IFREG {
                        guard pin.value.st_nlink == 1 else { throw BackupReadError.unavailable }
                        size = pin.value.st_size
                    } else if pin.value.st_mode & S_IFMT == S_IFDIR {
                        for name in try PinnedPath.names(in: pin.descriptor, limit: max(0, entryLimit - visited)) {
                            let amount = try visit(url.exactAppendingPathComponent(name), depth: depth + 1)
                            let sum = size.addingReportingOverflow(amount)
                            guard !sum.overflow else { throw BackupReadError.unavailable }; size = sum.partialValue
                        }
                    } else { throw BackupReadError.unavailable }
                    try pin.revalidate()
                    if visited % 128 == 0 { emit(.progress(.init("Sizing backup folders without opening payloads", entries: visited))) }
                    return size
                }
                return try visit(folder, depth: 0)
            }
            for (index, name) in names.enumerated() {
                try Task.checkCancellation()
                let url = root.exactAppendingPathComponent(name), ordinal = index + 1, label = "Backup \(ordinal)"
                emit(.progress(.init("Reading local backup metadata", current: label, completed: index, total: names.count, entries: visited)))
                if ignored(url) {
                    backups.append(.init(url: url, ordinal: ordinal, deviceName: nil, backupDate: nil, encrypted: nil, bytes: nil, state: .ignored, detail: "Ignored. No metadata or size was read."))
                    coverage(label, url: url, state: .skipped, detail: "Ignored backup folder."); continue
                }
                var deviceName: String?, date: Date?, encrypted: Bool?, bytes: Int64?
                var readFailure: CoverageState?
                var accessCapability: FilesystemCapability?
                var state = DeviceBackupState.unsupported
                var detail = "Unrecognized backup folder. Use Finder to inspect this location."
                do {
                    let pin = try PinnedPath(url)
                    guard pin.value.st_mode & S_IFMT == S_IFDIR, pin.value.st_uid == getuid(), pin.value.st_dev == rootPin.value.st_dev else { throw BackupReadError.unavailable }
                    let children = try PinnedPath.names(in: pin.descriptor, limit: max(0, entryLimit - visited))
                    if children.isEmpty { state = .empty; bytes = 0; detail = "The folder was empty at inspection time. It is not offered for removal." }
                    else {
                        let recognizableName = name.range(of: "^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{8}-[a-fA-F0-9]{16})(?:-[0-9]{8}-[0-9]{6})?$", options: .regularExpression) != nil
                        var proofs: [String: MetadataProof] = [:]
                        var missing = false, malformed = false
                        for filename in ["Info.plist", "Manifest.plist", "Status.plist"] where recognizableName {
                            guard children.contains(filename) else { missing = true; continue }
                            guard !ignored(url.exactAppendingPathComponent(filename)) else { throw BackupReadError.unavailable }
                            do { proofs[filename] = try readMetadata(url.exactAppendingPathComponent(filename)) }
                            catch BackupReadError.malformed { malformed = true }
                            catch is CancellationError { throw CancellationError() }
                            catch { throw error }
                        }
                        if let info = proofs["Info.plist"]?.dictionary {
                            deviceName = displayName(info["Device Name"] ?? info["Display Name"])
                            date = info["Last Backup Date"] as? Date
                            if info["Last Backup Date"] != nil && date == nil { malformed = true }
                        }
                        if let manifest = proofs["Manifest.plist"]?.dictionary {
                            encrypted = boolean(manifest["IsEncrypted"])
                            if encrypted == nil { malformed = true }
                        }
                        let status = proofs["Status.plist"]?.dictionary
                        if date == nil { date = status?["Date"] as? Date }
                        if let status, status["Date"] != nil && status["Date"] as? Date == nil { malformed = true }
                        if let status, status["SnapshotState"] != nil && status["SnapshotState"] as? String == nil { malformed = true }
                        let versionKnown = (status?["Version"] as? String) == "3.3" && (proofs["Manifest.plist"]?.dictionary["Version"] as? String) == "9.1"
                        let snapshot = status?["SnapshotState"] as? String
                        var manifestPresent = false
                        if children.contains("Manifest.db") {
                            guard !ignored(url.exactAppendingPathComponent("Manifest.db")) else { throw BackupReadError.unavailable }
                            let database = try PinnedPath(url.exactAppendingPathComponent("Manifest.db"))
                            manifestPresent = database.value.st_mode & S_IFMT == S_IFREG && database.value.st_size > 0 && database.value.st_nlink == 1
                            try database.revalidate()
                        }
                        if malformed || !recognizableName || (!missing && !versionKnown) || (snapshot.map { !["finished", "in-progress"].contains($0) } ?? false) {
                            state = .unsupported; detail = "Metadata is malformed or outside the recognized inspection layout. This is not evidence that the backup is empty or disposable."
                        } else if missing || !manifestPresent || snapshot != "finished" {
                            state = .incomplete; detail = "Required metadata/database is missing, or the snapshot does not report finished. Backup/restore activity and recoverability are unknown."
                        } else {
                            state = .reportedFinished; detail = "Metadata reports a finished snapshot. File contents, database integrity and restorability are not verified. This may be your only copy."
                        }
                        bytes = try measure(url)
                        for (filename, proof) in proofs {
                            let after = try readMetadata(url.exactAppendingPathComponent(filename))
                            guard after.identity == proof.identity, after.identity.location == proof.identity.location, after.digest == proof.digest else { throw BackupReadError.changed }
                        }
                    }
                    try pin.revalidate()
                } catch is CancellationError { throw CancellationError() }
                catch BackupReadError.changed { state = .changed; bytes = nil; detail = "Backup metadata changed during inspection. Retry after backup/restore work finishes." }
                catch { readFailure = GeneratedDataScanner.failureState(error); accessCapability = (error as? FilesystemAccessError)?.capability; state = .unreadable; bytes = nil; detail = "Inspection was incomplete: access, ignored contents, links, shared files, provider/volume/owner changes or the scan limit prevented a complete local read." }
                backups.append(.init(url: url, ordinal: ordinal, deviceName: deviceName, backupDate: date, encrypted: encrypted, bytes: bytes, state: state, detail: detail))
                if state != .reportedFinished && state != .empty { coverage(label, url: url, state: readFailure == .blocked ? .blocked : .skipped, detail: detail, capability: accessCapability) }
            }
            try rootPin.revalidate()
            return inventory(names.isEmpty ? .empty : .found)
        }
    }

    private enum BackupReadError: Error { case unavailable, malformed, changed }
    private struct MetadataProof {
        let dictionary: [String: Any]
        let identity: FileIdentity
        let digest: Data
    }
    private static func readMetadata(_ url: URL) throws -> MetadataProof {
        let pin = try PinnedPath(url)
        guard pin.value.st_mode & S_IFMT == S_IFREG, pin.value.st_uid == getuid(), pin.value.st_nlink == 1 else { throw BackupReadError.unavailable }
        guard pin.value.st_size > 0, pin.value.st_size <= 1_048_576 else { throw BackupReadError.malformed }
        let before = try Filesystem.inspect(url, limit: 1).1
        metadataReadObserver?(url)
        let bytes = try Filesystem.readMetadata(url, limit: 1_048_576)
        let dictionary: [String: Any]
        do {
            guard let value = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else { throw BackupReadError.malformed }
            dictionary = value
        } catch { throw BackupReadError.malformed }
        try pin.revalidate(expected: before.location)
        guard try Filesystem.inspect(url, limit: 1).1 == before else { throw BackupReadError.changed }
        return .init(dictionary: dictionary, identity: before, digest: Data(SHA256.hash(data: bytes)))
    }
    private static func displayName(_ value: Any?) -> String? {
        guard let name = value as? String, !name.isEmpty, name.utf8.count <= 256 else { return nil }
        let result = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return result.isEmpty ? nil : result
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
