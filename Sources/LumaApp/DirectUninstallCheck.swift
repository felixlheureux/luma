#if DEBUG
import SwiftUI
import LumaCore

private final class UninstallMoveGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didEnter = false
    let release = DispatchSemaphore(value: 0)
    var entered: Bool { lock.withLock { didEnter } }
    func enter() {
        let first = lock.withLock { let first = !didEnter; didEnter = true; return first }
        if first { _ = release.wait(timeout: .now() + 10) }
    }
}

extension LumaAppDelegate {
    func checkDirectUninstall(output: String) {
        Task { @MainActor in
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/direct-\(UUID())")
            let model = AppModel.shared
            let oldRunner = model.scanRunner
            let gate = UninstallMoveGate()
            var report: [String: Any] = ["realTrashInvoked": false]
            var checkedWindow: NSWindow?
            var originalFrame: NSRect?
            defer {
                if let checkedWindow, let originalFrame {
                    checkedWindow.setFrame(originalFrame, display: true)
                    if !checkedWindow.frameAutosaveName.isEmpty { checkedWindow.saveFrame(usingName: checkedWindow.frameAutosaveName) }
                }
                gate.release.signal(); model.scanRunner = oldRunner
                model.scanSessions.cancel(); model.applicationInventory.cancel()
                try? FileManager.default.removeItem(at: home)
                NSApp.terminate(nil)
            }
            do {
                try await Task.sleep(for: .seconds(2))
                func file(_ path: String, _ content: String) throws {
                    let url = home.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(content.utf8).write(to: url)
                }
                let id = "org.direct"
                try file("Applications/Vendor/Fixture.app/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(id)</string><key>CFBundleIconFile</key><string>Fixture.png</string></dict></plist>")
                let icon = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32)!
                for x in 0..<64 { for y in 0..<64 { icon.setColor(NSColor(deviceRed: 0.4, green: 0.2, blue: 0.8, alpha: 1), atX: x, y: y) } }
                let iconURL = home.appendingPathComponent("Applications/Vendor/Fixture.app/Contents/Resources/Fixture.png")
                try FileManager.default.createDirectory(at: iconURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try icon.representation(using: .png, properties: [:])!.write(to: iconURL)
                try file("Library/Caches/\(id)/cache", "cache")
                try file("Library/Preferences/\(id).plist", "settings")
                try file("Library/Application Support/\(id)/document", "keep this document")
                try file("Downloads/unrelated", "unrelated selection")
                let trash = home.appendingPathComponent(".Trash")
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let journal = try CleanupJournal(home: home, trashMover: { source in
                    gate.enter()
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: source, to: destination)
                    return destination
                })
                try await model.installFixtureJournal(journal)
                model.uninstallHome = home
                model.ignored = []
                model.completedScans.remove(.applications); model.applications = []
                model.scanRunner = { request, emit in
                    if request.target == .applications {
                        let inventory = try ApplicationScanner.inventory(home: home, roots: [home.appendingPathComponent("Applications")], emit: emit)
                        try await Task.sleep(for: .seconds(2))
                        return inventory
                    }
                    try await Task.sleep(for: .seconds(8))
                    return ScanResult(report: ScanReport())
                }
                model.destination = .storage; model.selected = ["storage-choice"]
                model.destination = .applications
                model.ensureApplicationInventory()
                try await waitDirectUninstall { !model.visibleApplications.isEmpty }
                let app = model.visibleApplications[0]
                report["vendorInventoryAndIcon"] = app.url.path.contains("/Vendor/") && app.iconPNG != nil
                let metadataOnly = ApplicationRecord(url: app.url, name: app.name, bundleID: app.bundleID, version: app.version, bytes: app.bytes)
                model.mergeApplicationInventory(ScanResult(report: ScanReport(), applications: [metadataOnly]))
                report["metadataMergeKeepsIcon"] = model.visibleApplications.first { $0.id == app.id }?.iconPNG == app.iconPNG && app.iconPNG != nil
                let oldRow = ApplicationRecord(url: home.appendingPathComponent("Applications/Unavailable.app"), name: "Unavailable", bundleID: "org.unavailable", version: "1", bytes: 0)
                model.applications.append(oldRow)
                var partial = ScanReport(); partial.isComplete = false
                partial.coverage = [.init(ruleID: "inventory", title: "Unavailable", path: oldRow.url.path, category: .applications, state: .blocked, bytes: 0, detail: "Injected denied metadata")]
                model.mergeApplicationInventory(ScanResult(report: partial, applications: [metadataOnly]))
                report["partialInventoryRetainsUnavailableRow"] = model.visibleApplications.count == 2
                partial.coverage = [.init(ruleID: "inventory.size", title: app.name, path: app.url.path, category: .applications, state: .blocked, bytes: 0, detail: "Injected denied sizing")]
                model.mergeApplicationInventory(ScanResult(report: partial, applications: [metadataOnly]))
                report["sizeFailureDoesNotKeepDeletedRows"] = model.visibleApplications.count == 1
                report["twoComponentEligible"] = model.uninstallUnavailableReason(app) == nil
                report["automaticProgressiveInventory"] = model.applicationInventory.isBusy && !model.visibleApplications.isEmpty
                report["noScanOrDetailsRequired"] = model.inspectedApp == nil && model.reviewPlan == nil && !model.showingReview
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No main window") }
                checkedWindow = window
                if ProcessInfo.processInfo.environment["LUMA_QA_RESTORE_WINDOW_SIZE"] == "1" {
                    window.setContentSize(NSSize(width: 1200, height: 850))
                    window.center()
                }
                originalFrame = window.frame
                window.setContentSize(NSSize(width: 720, height: 700))
                try await Task.sleep(for: .milliseconds(250))
                try saveScanCheckWindow(window, path: output + "-rows.png")
                report["narrowWindow"] = window.contentView?.bounds.width ?? 9999 < 800
                if let originalFrame { window.setFrame(originalFrame, display: true) }
                report["windowSizeRestored"] = originalFrame == window.frame
                model.startScan(.init(.applications))
                model.startScan(.init(.duplicates))
                report["unrelatedScanAllowsUninstall"] = model.scanSessions.isBusy && model.uninstallUnavailableReason(app) == nil
                let started = Date()
                model.uninstall(app)
                report["promptFeedback"] = model.cleanupSession.isRunning && model.uninstallingApp == app.id
                try await waitDirectUninstall { gate.entered }
                report["bundleRetainedUntilConfirmedMove"] = model.visibleApplications.contains { $0.id == app.id }
                report["unrelatedQueuedScanPreserved"] = model.scanSessions.isBusy && model.scanTarget == .duplicates
                model.destination = .system
                try await Task.sleep(for: .milliseconds(200))
                report["navigationKeepsMutation"] = model.cleanupSession.isRunning
                gate.release.signal()
                try await waitDirectUninstall { !model.cleanupSession.isRunning }
                report["seconds"] = Date().timeIntervalSince(started)
                report["completedWithoutSheets"] = model.cleanupSession.sessions.last?.phase == .completed && !model.showingReview && model.inspectedApp == nil && window.attachedSheet == nil
                report["onlyConfirmedBundleRemoved"] = !model.visibleApplications.contains { $0.id == app.id }
                report["retainedDocuments"] = FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/\(id)/document").path)
                model.destination = .storage
                report["selectionPreserved"] = model.selected == ["storage-choice"]
                model.destination = .applications
                let session = model.cleanupSession.sessions.last!
                model.ensureApplicationInventory(refresh: true)
                try await waitDirectUninstall { model.applicationInventory.isBusy }
                model.undo(session)
                try await waitDirectUninstall { !model.cleanupSession.isRunning }
                report["directUndoWithoutSheet"] = window.attachedSheet == nil && model.history.allSatisfy(\.restored)
                try await Task.sleep(for: .milliseconds(2200))
                report["restoredIcon"] = model.visibleApplications.first { $0.id == app.id }?.iconPNG == app.iconPNG && app.iconPNG != nil
                report["bundleOnlyRetainsOptionalData"] = FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/\(id)/cache").path)
                report["restoredRowReturns"] = model.visibleApplications.contains { $0.id == app.id }
                report["staleInventoryCannotHideRestore"] = !model.applicationInventory.isBusy && model.visibleApplications.contains { $0.id == app.id }
                report["restoredOutcome"] = model.cleanupSession.undoAttempts.last?.phase == .completed && model.status.contains("restored")
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-restored.png")
                model.recoveryLoading = true
                report["journalLoadingDisablesAction"] = model.uninstallUnavailableReason(app) != nil
                model.recoveryLoading = false
                model.journalError = "Injected Activity read error"
                report["journalErrorExplainsAction"] = model.uninstallUnavailableReason(app)?.contains("Activity") == true
                model.journalError = nil
                model.ignored.insert(app.url.appendingPathComponent("Contents/Info.plist").path)
                model.uninstall(app)
                try await waitDirectUninstall { !model.cleanupSession.isRunning }
                report["blockedRowRemainsInline"] = model.visibleApplications.contains { $0.id == app.id }
                    && model.uninstallMessages[app.id]?.contains("ignored") == true && model.status.contains("Failed") && !model.showingReview
                model.ignored = []
                model.scanSessions.cancel()
                try await waitDirectUninstall { !model.scanSessions.isBusy }
                try file("Downloads/copy-one", "duplicate contents")
                try file("Downloads/copy-two", "duplicate contents")
                let result = try DuplicateScanner(root: home.appendingPathComponent("Downloads")).scanResult()
                model.scanRunner = { _, _ in result }
                model.destination = .duplicates
                model.startScan(.init(.duplicates, root: home.appendingPathComponent("Downloads")))
                try await waitDirectUninstall { !model.scanSessions.isBusy }
                try await Task.sleep(for: .milliseconds(100))
                guard let group = result.duplicates.first, let keeper = group.items.first else { throw LumaError.rejected("Missing duplicate fixture") }
                model.prepareDuplicateKeeper(group: group, keeper: keeper, source: .duplicates)
                model.destination = .system; model.selected = ["system-choice"]
                try await waitDirectUninstall { !model.operationBusy }
                report["lateKeeperCannotReopenOrSelect"] = model.selected == ["system-choice"] && model.duplicateChoice == nil && !model.showingReview
                // The same shared drain boundary used by applicationShouldTerminate.
                let drainGate = UninstallMoveGate()
                var drained = false
                model.cleanupSession.run {
                    _ = await Task.detached { drainGate.enter() }.value
                }
                try await waitDirectUninstall { drainGate.entered }
                model.cleanupSession.onDrained = { drained = true }
                model.cleanupSession.stop()
                report["quitWaitsForDrain"] = !drained && model.cleanupSession.isRunning
                drainGate.release.signal()
                try await waitDirectUninstall { drained }
                report["quitDrainsBeforeReply"] = !model.cleanupSession.isRunning
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
            catch { NSLog("Direct uninstall QA report: %@", error.localizedDescription) }
        }
    }

    private func waitDirectUninstall(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard predicate() else { throw LumaError.rejected("Direct uninstall QA timed out") }
    }
}
#endif
