#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkStorageVolumes(output: String, rootPath: String) {
        Task { @MainActor in
            let model = AppModel.shared, root = URL(fileURLWithPath: rootPath)
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(30)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
                guard predicate() else { throw LumaError.rejected("Volume native check timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                model.showMainWindow?()
                for existing in NSApp.windows where existing.frame.width > 800 && existing.frame.height > 500 {
                    existing.makeKeyAndOrderFront(nil)
                }
                NSApp.activate()
                try await Task.sleep(for: .milliseconds(500))
                report["mainWindowCallbackAvailable"] = model.showMainWindow != nil
                report["windowStates"] = NSApp.windows.map { ["width": $0.frame.width, "height": $0.frame.height, "visible": $0.isVisible] as [String: Any] }
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.frame.width > 800 && $0.frame.height > 500 }) else { throw LumaError.rejected("No storage volume window") }
                model.destination = .storage
                model.startScan(.init(.storage, root: root))
                try await wait { !model.busy }
                guard let index = model.storageIndex, index.scope.inspectionOnly else { throw LumaError.rejected("Missing inspection-only index: \(model.scanSessions.session?.detail ?? model.status)") }
                report["readOnlyVolume"] = index.scope.volume.isReadOnly
                report["scopeVisible"] = Data(index.scope.root.path.utf8) == Data(root.path.utf8) && !index.scope.volume.identity.uuid.isEmpty
                report["nothingSelected"] = model.selected.isEmpty
                report["logicalBytes"] = index.nodes[root.path]?.bytes ?? -1
                let folder = root.appendingPathComponent("Nested").path
                model.navigateStorage(folder)
                report["listNavigationAvailable"] = model.storageDirectory == folder && index.breadcrumbs(to: folder).count == 2
                if let file = index.children(of: folder).first {
                    report["coreReviewRejected"] = await Task.detached { () -> Bool in
                        do { _ = try index.reviewItems(ids: [file.id], directory: folder); return false }
                        catch { return true }
                    }.value
                    model.selected = [file.id]; model.reviewStorage()
                    report["appReviewRejected"] = model.reviewPlan == nil && !model.showingReview && !model.busy
                    model.selected = []
                }
                try await Task.sleep(for: .milliseconds(500))
                try saveScanCheckWindow(window, path: output + "-analysis.png")
                // The driver unmounts only its own generated read-only fixture.
                try Data().write(to: URL(fileURLWithPath: output + ".ready"))
                try await wait { model.storageIndex == nil && model.storageVolumes.issue != nil }
                report["unmountInvalidated"] = model.snapshot(for: .storage) == nil && !model.completedScans.contains(.storage) && model.selected.isEmpty
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-unmounted.png")
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Volume QA report failed: %@", error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
}
#endif
