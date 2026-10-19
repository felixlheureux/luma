#if DEBUG
import SwiftUI
import LumaCore

private final class FeedbackMoveGate: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false
    var started: Bool { lock.withLock { entered } }
    func wait() {
        lock.withLock { entered = true }
        _ = release.wait(timeout: .now() + 20)
    }
}

extension LumaAppDelegate {
    func checkCleanupFeedback(output: String) {
        Task { @MainActor in
            let model = AppModel.shared, oldRunner = AppModel.shared.scanRunner
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/cleanup-feedback-\(UUID())")
            let trash = home.appendingPathComponent(".Trash"), apps = home.appendingPathComponent("Applications")
            let gate = FeedbackMoveGate()
            var checkedWindow: NSWindow?
            var originalFrame: NSRect?
            defer {
                if let checkedWindow, let originalFrame {
                    checkedWindow.setFrame(originalFrame, display: true)
                    if !checkedWindow.frameAutosaveName.isEmpty { checkedWindow.saveFrame(usingName: checkedWindow.frameAutosaveName) }
                }
                gate.release.signal(); model.residueDiscovery.cancel(); model.scanRunner = oldRunner; try? FileManager.default.removeItem(at: home); NSApp.terminate(nil) }
            var report: [String: Any] = ["realTrashInvoked": false, "personalFoldersScanned": false]
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(35)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard predicate() else { throw LumaError.rejected("Cleanup feedback check timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                func write(_ path: String, _ data: Data) throws {
                    let url = home.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url)
                }
                for path in ["Library/Caches/org.lumatest.zeta/data", "Library/Caches/org.lumatest.alpha/data", "Library/Preferences/org.lumatest.alpha.plist"] {
                    try write(path, Data("synthetic leftover".utf8))
                }
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32)
                guard let bitmap, let bytes = bitmap.bitmapData else { throw LumaError.rejected("No fixture icon bitmap") }
                for pixel in 0..<(64 * 64) {
                    bytes[pixel * 4] = 100; bytes[pixel * 4 + 1] = 70; bytes[pixel * 4 + 2] = 220; bytes[pixel * 4 + 3] = 255
                }
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw LumaError.rejected("No fixture icon PNG") }
                let metadata: [String: Any] = ["CFBundleIdentifier": "org.lumatest.installed", "CFBundleName": "Fixture Application", "CFBundleIconFile": "Fixture.png", "CFBundleShortVersionString": "1.0"]
                try write("Applications/Fixture Application.app/Contents/Info.plist", PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0))
                try write("Applications/Fixture Application.app/Contents/Resources/Fixture.png", png)
                let journal = try CleanupJournal(home: home, trashMover: { source in
                    gate.wait()
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: source, to: destination); return destination
                })
                try await model.installFixtureJournal(journal)
                model.uninstallHome = home
                model.residueStore = ResidueObservationStore(home: home)
                model.residueEntered = false; model.residueLoaded = false
                model.scanRunner = { request, emit in
                    if request.target == .leftovers {
                        return ScanResult(report: try await LeftoverScanner(home: home, applicationRoots: [apps], lookup: { _ in false }, emit: emit).scan())
                    }
                    return try await ScanEngine.run(request, home: home, applicationRoots: [apps], emit: emit)
                }
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No feedback window") }
                checkedWindow = window; originalFrame = window.frame
                model.destination = .applications; model.applicationTab = .installed
                model.runScan(.applications)
                try await wait { !model.busy }
                report["installedIconLoaded"] = model.applications.first?.iconPNG != nil
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-icons.png")
                let cold = Date()
                model.applicationTab = .leftovers
                model.ensureResidues()
                try await wait { model.didScanLeftovers && !model.residueDiscovery.isBusy }
                report["coldResultsSeconds"] = Date().timeIntervalSince(cold)
                let originalDate = model.residueSavedAt
                report["threeLeftoversTwoOwners"] = model.leftovers.count == 3 && LeftoverGroup.groups(for: model.leftovers).map(\.id) == ["org.lumatest.alpha", "org.lumatest.zeta"]
                report["initialSelectionEmpty"] = model.residueSelection.isEmpty
                let alpha = LeftoverGroup.groups(for: model.leftovers)[0]
                model.selectResidueGroup(alpha)
                report["wholeGroupSelected"] = model.selectedResidues.count == 2
                let item = alpha.items[0]
                model.selectResidue(item, selected: false)
                report["mixedGroupSelection"] = model.selectedResidues.count == 1
                model.selectResidueGroup(alpha)
                report["mixedSelectsAll"] = model.selectedResidues.count == 2
                let originalRows = model.leftovers
                let newURL = home.appendingPathComponent("Library/Logs/org.lumatest.alpha/new")
                try write("Library/Logs/org.lumatest.alpha/new", Data("new arrival".utf8))
                let arrival = try Filesystem.item(newURL.deletingLastPathComponent(), category: .related, safety: .review, explanation: "Exact owner", consequence: "Logs lost", rule: "application.leftover.exact-identifier", owner: "org.lumatest.alpha")
                model.leftovers.append(arrival)
                report["arrivalNotSelected"] = model.residueSelection[arrival.id] == nil && model.selectedResidues.count == 2
                model.leftovers = originalRows
                try FileManager.default.removeItem(at: newURL.deletingLastPathComponent())
                model.selectResidueGroup(alpha)
                report["groupDeselectsAll"] = model.residueSelection.isEmpty
                model.selectResidue(item, selected: true)
                model.destination = .system
                report["navigationPreservesSelection"] = model.selectedResidues.count == 1
                model.destination = .applications
                window.setContentSize(NSSize(width: 760, height: 650))
                try await Task.sleep(for: .milliseconds(250))
                report["narrowWindow"] = (window.contentView?.bounds.width ?? 9999) < 800
                try saveScanCheckWindow(window, path: output + "-narrow.png")
                if let originalFrame { window.setFrame(originalFrame, display: true) }
                let selectedAt = Date()
                model.trashResidues()
                report["directWithoutReview"] = !model.showingReview && model.residueMoving
                try await wait { gate.started }
                try await Task.sleep(for: .milliseconds(400))
                report["liveMoveDetail"] = model.cleanupSession.detail?.phase == "Moving to macOS Trash"
                report["elapsedClockPresent"] = model.cleanupSession.startedAt != nil
                try saveScanCheckWindow(window, path: output + "-progress.png")
                gate.release.signal()
                try await wait { !model.cleanupSession.isRunning }
                report["selectionToOutcomeSeconds"] = Date().timeIntervalSince(selectedAt)
                report["remainingResultsRetained"] = model.didScanLeftovers && model.leftovers.count == 2 && !model.leftovers.contains(where: { $0.id == item.id })
                report["oldScanTimeRetained"] = model.residueSavedAt == originalDate
                report["selectionCleared"] = model.residueSelection.isEmpty
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-remaining.png")
                let warm = Date()
                let saved = try await model.residueStore.load()
                report["warmLoadSeconds"] = Date().timeIntervalSince(warm)
                report["savedRemainingObservations"] = saved?.items.count == 2
                model.residueEntered = false; model.residueLoaded = false; model.leftovers = []
                model.scanRunner = { request, emit in
                    try await Task.sleep(for: .seconds(1))
                    return ScanResult(report: try await LeftoverScanner(home: home, applicationRoots: [apps], lookup: { _ in false }, emit: emit).scan())
                }
                model.ensureResidues()
                try await wait { !model.leftovers.isEmpty }
                report["relaunchShowsSavedDuringRefresh"] = model.residueDiscovery.isBusy && model.leftovers.count == 2
                try await wait { !model.residueDiscovery.isBusy }
                if let next = model.leftovers.first {
                    model.selectResidue(next, selected: true)
                    gate.release.signal()
                    model.trashResidues()
                    try await wait { !model.cleanupSession.isRunning }
                    report["nextActionWithoutRescan"] = !model.showingReview && model.leftovers.count == 1
                    if let id = model.lastResidueSessionID, let session = model.cleanupSession.sessions.first(where: { $0.id == id }) {
                        model.undo(session)
                        try await wait { !model.cleanupSession.isRunning && !model.residueDiscovery.isBusy && !model.residueLoading }
                        report["undoRefreshesResidue"] = model.leftovers.contains { $0.id == next.id } && model.residueOutcome?.contains("restored") == true
                    }
                }
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            model.showingReview = false; model.error = nil
            try? await Task.sleep(for: .milliseconds(350))
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Cleanup feedback QA report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
