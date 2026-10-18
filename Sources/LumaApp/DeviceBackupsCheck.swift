#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Synthetic MobileSync layout only. The injected scan runner never reads
    /// the real backup location, opens a device or invokes Trash/Finder actions.
    func checkDeviceBackups(output: String) {
        Task { @MainActor in
            let model = AppModel.shared, oldRunner = AppModel.shared.scanRunner
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/backup-ui-\(UUID())")
            let root = DeviceBackups.location(home: home)
            defer { model.scanRunner = oldRunner; try? FileManager.default.removeItem(at: home); NSApp.terminate(nil) }
            var report: [String: Any] = ["mutationInvoked": false, "realBackupsInspected": false, "finderOrDeviceOpened": false]
            do {
                try await Task.sleep(for: .seconds(2))
                try await Task.detached(priority: .utility) {
                    func write(_ backup: URL, _ name: String, _ data: Data) throws {
                        let url = backup.appendingPathComponent(name)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: url)
                    }
                    func plist(_ backup: URL, _ name: String, _ value: [String: Any]) throws {
                        try write(backup, name, PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0))
                    }
                    for (index, key) in ["a", "b", "c", "d", "e"].enumerated() {
                        let backup = root.appendingPathComponent(String(repeating: key, count: 40))
                        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                        if key == "e" { continue }
                        try plist(backup, "Info.plist", ["Device Name": index == 0 ? "Fixture iPhone" : "Fixture iPad", "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000), "Serial Number": "PRIVATE-FIXTURE-ID"])
                        try plist(backup, "Manifest.plist", ["Version": "9.1", "IsEncrypted": key == "b"])
                        if key != "c" { try plist(backup, "Status.plist", ["Version": "3.3", "SnapshotState": "finished"]) }
                        if key == "d" { try write(backup, "Status.plist", Data("corrupt fixture".utf8)) }
                        try write(backup, "Manifest.db", Data("opaque database fixture; never opened".utf8))
                        try write(backup, "00/payload", Data("irreplaceable fixture data".utf8))
                    }
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No Backups window.") }
                let before = try await Task.detached { try Filesystem.inspect(root).1 }.value
                model.destination = .backups
                model.scanRunner = { request, emit in
                    if request.target == .deviceBackups {
                        let inventory = try DeviceBackups.scan(home: home, ignoredPaths: request.ignoredPaths, activity: { .unknown }, emit: emit)
                        var result = ScanResult(report: inventory.report); result.deviceBackups = inventory; return result
                    }
                    return try await oldRunner(request, emit)
                }
                model.runScan(.backups)
                let deadline = Date().addingTimeInterval(30)
                while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard let inventory = model.deviceBackups else { throw LumaError.rejected("No completed backup fixture inventory.") }
                report["fiveBackupFolders"] = inventory.backups.count == 5
                report["metadataStatesDistinct"] = inventory.backups.filter { $0.state == .reportedFinished }.count == 2
                    && inventory.backups.contains { $0.state == .incomplete }
                    && inventory.backups.contains { $0.state == .unsupported }
                    && inventory.backups.contains { $0.state == .empty && $0.bytes == 0 }
                report["encryptedMetadataVisible"] = inventory.backups.contains { $0.encrypted == true }
                report["recordedDateAndName"] = inventory.backups.first?.deviceName == "Fixture iPhone" && inventory.backups.first?.backupDate == Date(timeIntervalSince1970: 1_700_000_000)
                report["allPersonalData"] = inventory.backups.allSatisfy { $0.safety == .userData }
                report["noCleanupCandidatesOrSelection"] = inventory.report.items.isEmpty && model.selected.isEmpty && model.reviewPlan == nil && !model.showingReview
                report["unknownActivityNeverIdle"] = inventory.activity == .unknown
                let after = try await Task.detached { try Filesystem.inspect(root).1 }.value
                report["fixtureTreeUnchanged"] = before == after
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-backups.png")
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Backup QA failed: %@", error.localizedDescription) }
        }
    }
}
#endif
