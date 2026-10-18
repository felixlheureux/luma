#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkSmartCheck(output: String) {
        Task { @MainActor in
            let model = AppModel.shared, oldRunner = AppModel.shared.scanRunner
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/smart-ui-\(UUID())")
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            defer { model.scanRunner = oldRunner; try? FileManager.default.removeItem(at: home); NSApp.terminate(nil) }
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(30)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard predicate() else { throw LumaError.rejected("Smart Check fixture timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                let project = home.appendingPathComponent("Projects"), downloads = home.appendingPathComponent("Downloads")
                try await Task.detached {
                    for (path, value) in ["Library/Caches/Firefox/Profiles/abcdefgh.default/cache2/entry": "generated fixture",
                                          "Projects/package.json": "{}", "Projects/node_modules/pkg/index.js": "fixture dependency",
                                          "Downloads/notes.txt": "personal fixture"] {
                        let url = home.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(value.utf8).write(to: url)
                    }
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No Smart Check window") }
                model.destination = .overview
                model.smartScopes = [.developerProjects: project, .downloads: downloads]
                model.scanRunner = { request, emit in
                    try await SmartCheck.run(request, emit: emit) { child, output in
                        if child.target == .downloads { try await Task.sleep(for: .milliseconds(900)) }
                        if [.generatedData, .developerProjects, .downloads].contains(child.target) {
                            return try await ScanEngine.run(child, home: home, applicationRoots: [], emit: output)
                        }
                        if child.target == .leftovers { throw LumaError.rejected("Synthetic denied ownership check") }
                        return ScanResult()
                    }
                }
                model.runScan(.overview)
                try await wait { model.smartSnapshots[.generatedData] != nil }
                report["progressiveBeforeDeepCheck"] = model.busy && model.smartSnapshots[.downloads] == nil
                report["nothingSelectedDuringScan"] = model.selected.isEmpty && model.reviewPlan == nil
                try await wait { !model.busy }
                report["allFiveChecksRecorded"] = model.smartSnapshots.count == 5
                report["failedCheckDistinct"] = model.smartSnapshots[.leftovers]?.result.smartCheckFailure != nil
                report["laterCheckSurvivesFailure"] = model.downloadsInventory?.files.count == 1
                report["authorizedScopeRetained"] = model.smartSnapshots[.downloads]?.request.root == downloads
                report["generatedResultCommitted"] = model.cleanup.count == 1
                report["noAggregateCandidates"] = model.snapshot(for: .overview)?.result.report.items.isEmpty == true
                report["nothingSelectedAfterScan"] = model.selected.isEmpty && model.reviewPlan == nil
                report["measurementCaptured"] = model.smartMeasurement?.sampledAt != nil
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-overview.png")
                var navigation = true
                for (target, destination) in [(ScanTarget.generatedData, Destination.clean), (.applications, .applications), (.developerProjects, .projects), (.downloads, .downloads)] {
                    let time = model.smartSnapshots[target]?.finishedAt
                    model.openSmartResult(target)
                    navigation = navigation && model.destination == destination && model.snapshot(for: target)?.finishedAt == time
                    try await Task.sleep(for: .milliseconds(80))
                }
                report["exactNavigationAndTime"] = navigation
                model.openSmartResult(.generatedData)
                model.selected = Set(model.cleanup.map(\.id))
                model.review(model.cleanup, source: .generatedData)
                try await wait { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["normalReviewPresented"] = model.showingReview && model.reviewPlan?.items.count == 1 && window.attachedSheet != nil
                try saveScanCheckWindow(window, path: output + "-review.png")
                model.showingReview = false; model.reviewPlan = nil; model.selected = []
                try await Task.sleep(for: .milliseconds(350))
                model.invalidateGeneratedFindings()
                model.destination = .overview
                model.openSmartResult(.generatedData)
                report["invalidatedRecommendationCannotOpen"] = model.destination == .overview
                model.smartMeasurement = SystemSample()
                report["unavailableMeasurementRetained"] = model.smartMeasurement?.sampledAt == nil && model.smartMeasurement?.pressure == "Unavailable"
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
                window.makeFirstResponder(window.contentView)
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) {
                    window.sendEvent(event)
                }
                report["keyboardEventHandled"] = window.firstResponder != nil
            } catch { report["error"] = error.localizedDescription }
            model.showingReview = false; model.error = nil
            try? await Task.sleep(for: .milliseconds(350))
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Smart Check QA report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
