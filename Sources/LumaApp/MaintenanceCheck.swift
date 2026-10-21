#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkMaintenance(output: String) {
        Task { @MainActor in
            if let flag = CommandLine.arguments.firstIndex(of: "--maintenance-workspace"), CommandLine.arguments.indices.contains(flag + 1) {
                _ = FileManager.default.changeCurrentDirectoryPath(CommandLine.arguments[flag + 1])
            }
            let model = AppModel.shared
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/maintenance-\(UUID())")
            let trash = home.appendingPathComponent(".Trash")
            let oldReader = model.maintenanceTrashReader, oldRunner = model.scanRunner
            var checkedWindow: NSWindow?
            var originalFrame: NSRect?
            let oldIgnored = model.ignored
            let oldSavedIgnored = UserDefaults.standard.stringArray(forKey: "luma.ignoredPaths")
            var report: [String: Any] = ["personalTrashEmptied": false, "personalAppsQuit": false, "personalFoldersScanned": false]
            defer {
                if let checkedWindow, let originalFrame { checkedWindow.setFrame(originalFrame, display: true) }
                model.ignored = oldIgnored
                if let oldSavedIgnored { UserDefaults.standard.set(oldSavedIgnored, forKey: "luma.ignoredPaths") }
                else { UserDefaults.standard.removeObject(forKey: "luma.ignoredPaths") }
                model.maintenanceTrashReader = oldReader; model.scanRunner = oldRunner
                try? FileManager.default.removeItem(at: home); NSApp.terminate(nil)
            }
            @MainActor func require(_ value: Bool, _ key: String) throws {
                report[key] = value
                if !value { throw LumaError.rejected(key) }
            }
            @MainActor func pause() async throws { try await Task.sleep(for: .milliseconds(250)) }
            @MainActor func wait(_ condition: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(20)
                while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                if !condition() { throw LumaError.rejected("Maintenance wait timed out") }
            }
            @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
            @MainActor func click(_ window: NSWindow, _ name: String) throws {
                guard let view = window.contentView.flatMap({ descendants($0).first { $0.identifier?.rawValue == "luma-check-" + name } }) else { throw LumaError.rejected("Missing control " + name) }
                let frame = view.convert(view.bounds, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: frame.midX, y: frame.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw LumaError.rejected("No click") }
                    NSApp.postEvent(event, atStart: false)
                }
            }
            @MainActor func alertButton(_ title: String, window: NSWindow) throws {
                guard let sheet = window.sheets.first,
                      let button = sheet.contentView.flatMap({ descendants($0).compactMap { $0 as? NSButton }.first { $0.title == title } }) else { throw LumaError.rejected("No approval button " + title) }
                button.performClick(nil)
            }
            do {
                try await Task.sleep(for: .seconds(2))
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let cache = home.appendingPathComponent("Library/Caches/Google/Chrome")
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try Data("generated cache fixture".utf8).write(to: cache.appendingPathComponent("data"))
                try Data("trash fixture".utf8).write(to: trash.appendingPathComponent("existing"))
                let journal = try CleanupJournal(home: home, trashMover: { source in
                    let destination = trash.appendingPathComponent("cache-\(UUID())")
                    try FileManager.default.moveItem(at: source, to: destination); return destination
                })
                try await model.installFixtureJournal(journal)
                model.uninstallHome = home
                model.maintenanceTrashReader = { try TrashReview.generatedFixture(root: trash) }
                model.scanRunner = { request, emit in try await ScanEngine.run(request, home: home, applicationRoots: [home.appendingPathComponent("Applications")], emit: emit) }
                model.openMain(.maintenance)
                let firstResults = Date()
                model.refreshMaintenanceTrash(); model.runScan(.maintenance)
                try await wait { !model.busy && !model.maintenanceTrashLoading }
                report["firstResultsSeconds"] = Date().timeIntervalSince(firstResults)
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No Maintenance window") }
                checkedWindow = window; originalFrame = window.frame
                window.setContentSize(NSSize(width: 1050, height: 900)); window.makeKeyAndOrderFront(nil); NSRunningApplication.current.activate(options: [.activateAllWindows])
                try await pause()
                try require(model.selected.isEmpty && model.cleanup.count == 1, "emptyInitialSelection")
                try require(model.maintenanceTrash?.count == 1, "independentTrashObservation")
                window.contentView?.display()
                try await pause()
                try saveScanCheckWindow(window, path: output + "-initial.png")
                window.setContentSize(NSSize(width: 760, height: 650)); try await pause()
                try click(window, "maintenance-trash"); try await pause()
                try saveScanCheckWindow(window, path: output + "-approval.png")
                report["approvalWindows"] = NSApp.windows.filter(\.isVisible).map { "\($0.className):\($0.title):sheets=\($0.sheets.count)" }
                report["active"] = NSApp.isActive; report["key"] = window.isKeyWindow
                try require(window.sheets.count == 1, "oneTrashApproval")
                try alertButton("Cancel", window: window); try await pause()
                try require(FileManager.default.fileExists(atPath: trash.appendingPathComponent("existing").path), "cancelPreservesTrash")
                try click(window, "maintenance-trash"); try await pause()
                let emptyStarted = Date()
                try alertButton("Permanently remove", window: window)
                try await wait { !model.cleanupSession.isRunning }
                report["emptyFixtureSeconds"] = Date().timeIntervalSince(emptyStarted)
                try require(!FileManager.default.fileExists(atPath: trash.appendingPathComponent("existing").path), "approvedFixturePermanentlyRemoved")
                try require(await journal.trashRemovalHistory().last?.finished == true, "permanentOutcomePersisted")
                window.setContentSize(NSSize(width: 1050, height: 900)); try await pause()
                let item = try requireItem(model.cleanup.first)
                model.ignore(item)
                try require(model.cleanupBytes == 0 && model.cleanup.filter { !model.isIgnored($0) }.isEmpty, "ignoredLastResultHasZeroActionableTotal")
                model.unignore(item.id); model.selected = [item.id]
                // Put the cache footer in the native scroll viewport before clicking.
                if let marker = window.contentView.flatMap({ descendants($0).first { $0.identifier?.rawValue == "luma-check-maintenance-cache" } }) { marker.scrollToVisible(marker.bounds) }
                try await pause()
                try click(window, "maintenance-cache"); try await pause()
                try require(window.sheets.count == 1 && !model.showingReview, "oneCacheApprovalWithoutReviewSheet")
                try alertButton("Cancel", window: window); try await pause()
                try require(FileManager.default.fileExists(atPath: cache.path), "cancelPreservesCache")
                try click(window, "maintenance-cache"); try await pause()
                let cacheStarted = Date()
                try alertButton("Move to Trash", window: window)
                try await wait { !model.cleanupSession.isRunning }
                report["cacheTrashSeconds"] = Date().timeIntervalSince(cacheStarted)
                try require(!FileManager.default.fileExists(atPath: cache.path) && model.history.count == 1, "cacheUsesJournal")
                try require(model.cleanup.isEmpty && model.cleanupBytes == 0 && model.cleanupReport?.items.isEmpty == true, "postMutationTotalsAgree")
                if let record = model.history.first {
                    model.restore(record); try await wait { !model.operationBusy }
                    try require(FileManager.default.fileExists(atPath: cache.path), "cacheRestoreVerified")
                }
                model.openCore(.maintenance)
                let samples = model.cpuHistory.count
                try await Task.sleep(for: .seconds(3))
                try require(model.cpuHistory.count > samples, "monitoringContinues")
                window.setContentSize(NSSize(width: 760, height: 650)); try await pause()
                try saveScanCheckWindow(window, path: output + "-narrow.png")
                report["narrowWindow"] = window.contentLayoutRect.width <= 760
                report["finalCacheOutcome"] = model.maintenanceCacheStatus
                report["finalTrashOutcome"] = model.maintenanceTrashStatus
            } catch { report["error"] = error.localizedDescription }
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
    private func requireItem(_ item: CleanupItem?) throws -> CleanupItem {
        guard let item else { throw LumaError.rejected("No cache fixture") }; return item
    }
}
#endif
