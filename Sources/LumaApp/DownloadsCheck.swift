#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Run the built debug executable from the repository. Only generated fixture
    /// files are read/edited; this check never invokes cleanup or an installer.
    func checkDownloads(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/downloads-ui-\(UUID())")
            defer { model.clearDownloadPreview(); try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            var report: [String: Any] = ["mutationInvoked": false, "installerOrURLLaunched": false]
            do {
                try await Task.sleep(for: .seconds(2))
                try await Task.detached(priority: .utility) {
                    let fixtures = ["Offline.dmg": "installer fixture", "Offline-copy.dmg": "installer fixture", "Archive.zip": "archive fixture", "Setup.pkg": "package fixture", "transfer.crdownload": "incomplete", "notes.txt": "Personal notes. https://example.invalid is displayed as plain text.\n" + String(repeating: "Read locally.\n", count: 8)]
                    for (path, text) in fixtures {
                        let url = root.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(text.utf8).write(to: url)
                    }
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No Downloads window.") }
                model.destination = .downloads; model.downloadsTab = .files
                model.authorizedRoots.append(root)
                model.startScan(.init(.downloads, root: root))
                try await waitForDownloadsCheck { !model.busy }
                guard let inventory = model.downloadsInventory, inventory.report.items.count == 5 else {
                    throw LumaError.rejected("No complete Downloads fixture inventory: \(model.scanSessions.session?.detail ?? model.status)")
                }
                report["filesAndIncompleteDistinct"] = inventory.files.count == 6 && inventory.files.first { $0.kind == .incomplete }?.item == nil
                report["typeTotalsPartition"] = DownloadKind.allCases.reduce(0) { $0 + inventory.bytes(kind: $1) } == inventory.bytes()
                report["allPersonalData"] = inventory.report.items.allSatisfy { $0.safety == .userData }
                report["nothingSelected"] = model.selected.isEmpty
                let notes = inventory.files.first { $0.url.lastPathComponent == "notes.txt" }!
                report["unknownSourceIsUnknown"] = notes.sources.isEmpty
                model.previewDownload(notes)
                try await waitForDownloadsCheck { model.downloadPreview != nil }
                if case .text(let value, _) = model.downloadPreview { report["plainTextPreview"] = value.contains("https://example.invalid") }
                else { report["plainTextPreview"] = false }
                try await Task.sleep(for: .milliseconds(500))
                try saveScanCheckWindow(window, path: output + "-files.png")
                model.clearDownloadPreview(); model.downloadsTab = .duplicates
                try await Task.sleep(for: .milliseconds(300))
                guard let group = inventory.duplicates.first, group.items.count == 2 else { throw LumaError.rejected("No verified Downloads duplicate group.") }
                report["duplicateGroup"] = inventory.duplicates.count == 1
                model.prepareDuplicateKeeper(group: group, keeper: group.items[0], source: .downloads)
                try await waitForDownloadsCheck { !model.busy }
                report["keeperPreviewBeforeSelection"] = model.duplicateChoice != nil && model.selected.isEmpty
                model.applyDuplicateKeeper()
                try await waitForDownloadsCheck { !model.busy }
                report["explicitKeeperSelection"] = model.selected == [group.items[1].id]
                try saveScanCheckWindow(window, path: output + "-duplicates.png")
                model.review(inventory.report.items)
                try await waitForDownloadsCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(300))
                report["reviewPresented"] = model.showingReview && window.attachedSheet != nil && model.reviewPlan?.source == .downloads && model.reviewPlan?.items.count == 1
                try saveScanCheckWindow(window, path: output + "-review.png")
                model.showingReview = false; model.reviewPlan = nil
                try await Task.sleep(for: .milliseconds(250))
                let changed = group.items[1]
                try await Task.detached { try Data("changed download".utf8).write(to: changed.url) }.value
                model.selected = [changed.id]; model.error = nil
                model.review(inventory.report.items)
                try await waitForDownloadsCheck { !model.busy }
                report["staleSelectionRejected"] = model.error != nil && !model.showingReview && model.reviewPlan == nil
                model.error = nil; model.invalidateDownloads()
                report["invalidationClearsEvidence"] = model.downloadsInventory == nil && model.selected.isEmpty && model.downloadPreview == nil && model.completedSnapshots[.downloads] == nil
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Downloads QA failed: %@", error.localizedDescription) }
        }
    }
    private func waitForDownloadsCheck(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard predicate() else { throw LumaError.rejected("Downloads QA timed out.") }
    }
}
#endif
