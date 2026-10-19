#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkAnalysisIndex(output: String) {
        Task { @MainActor in
            let model = AppModel.shared, oldRunner = AppModel.shared.scanRunner, oldIndex = AppModel.shared.analysisIndex
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/index-ui-\(UUID())")
            let root = home.appendingPathComponent("Data"), cacheURL = home.appendingPathComponent("Analysis")
            let index = AnalysisIndex(directory: cacheURL)
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            defer {
                model.scanRunner = oldRunner; model.analysisIndex = oldIndex
                try? FileManager.default.removeItem(at: home); NSApp.terminate(nil)
            }
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(30)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard predicate() else { throw LumaError.rejected("Analysis index native check timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                try await Task.detached {
                    for path in ["nested/a", "nested/b", "other/c", "other/d"] {
                        let url = root.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(repeating: 42, count: 1024 * 1024).write(to: url)
                    }
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No index check window") }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let ignored = model.ignored, history = try encoder.encode(model.history)
                model.analysisIndex = index
                model.storageStore = StorageObservationStore(home: home)
                model.scanRunner = { request, emit in try await ScanEngine.run(request, analysisIndex: index, emit: emit) }
                model.destination = .storage
                model.startScan(.init(.storage, root: root))
                try await wait { !model.busy }
                let coldBytes = model.storageIndex?.nodes[root.path]?.bytes
                if let observed = model.storageIndex { try await model.storageStore.save(observed) }
                let folder = root.appendingPathComponent("nested").path
                model.storageDirectory = folder
                model.startScan(.init(.storage, root: root))
                try await wait { !model.busy }
                report["warmStorageMetadata"] = (model.snapshot(for: .storage)?.result.analysisCache?.reusedMetadata ?? 0) > 0
                report["storageCoverageAndBytesMatch"] = model.storageIndex?.nodes[root.path]?.bytes == coldBytes && model.storageIndex?.nodes[root.path]?.isComplete == true
                report["nestedNavigationAvailable"] = model.storageIndex?.breadcrumbs(to: folder).count == 2 && model.storageDirectory == folder
                report["noSelection"] = model.selected.isEmpty
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-storage.png")
                model.destination = .duplicates
                model.startScan(.init(.duplicates, root: root))
                try await wait { !model.busy }
                let groups = model.duplicates.map(\.id)
                model.runScan(.duplicates)
                try await wait { !model.busy }
                report["warmHashesReused"] = model.snapshot(for: .duplicates)?.result.analysisCache?.reusedHashes == 8
                report["duplicateResultsMatch"] = model.duplicates.map(\.id) == groups && groups.count == 1
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-duplicates.png")
                // The real native FSEvents stream invalidates the entire root.
                try await Task.detached {
                    try Data(repeating: 7, count: 1024 * 1024).write(to: root.appendingPathComponent("nested/b"))
                }.value
                // The daemon batches delivery; metadata checks protect scans
                // started before its advisory notification reaches this process.
                try await Task.sleep(for: .seconds(2))
                model.runScan(.duplicates)
                try await wait { !model.busy }
                report["nativeEventInvalidation"] = model.snapshot(for: .duplicates)?.result.analysisCache?.reusedHashes == 0
                report["changedContentNotInGroup"] = model.duplicates.first?.items.count == 3
                model.clearAnalysisCache()
                try await wait { !model.busy }
                report["cacheClearFinished"] = model.analysisCacheStatus?.hasPrefix("Saved analysis cleared") == true
                report["storageObservationCacheCleared"] = try await model.storageStore.load() == nil
                let afterHistory = try encoder.encode(model.history)
                report["activityAndIgnoresPreserved"] = model.ignored == ignored && afterHistory == history
                model.runScan(.duplicates)
                try await wait { !model.busy }
                report["clearForcesColdHashes"] = model.snapshot(for: .duplicates)?.result.analysisCache?.reusedHashes == 0
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
                let visibleBeforeSettings = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
                model.showSettingsWindow?()
                try await Task.sleep(for: .milliseconds(500))
                if let settings = NSApp.windows.first(where: {
                    $0.isVisible && !visibleBeforeSettings.contains($0.windowNumber)
                        && $0.frame.width >= 400 && $0.frame.height >= 300 && !($0 is NSPanel)
                }) {
                    try saveScanCheckWindow(settings, path: output + "-settings.png")
                    report["settingsPresented"] = true
                    settings.close()
                } else { report["settingsPresented"] = false }
            } catch { report["error"] = error.localizedDescription }
            model.error = nil; model.showingReview = false
            try? await Task.sleep(for: .milliseconds(350))
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Index QA report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
