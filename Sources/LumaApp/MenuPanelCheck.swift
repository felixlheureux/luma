#if DEBUG
import AppKit
import LumaCore

extension LumaAppDelegate {
    func checkMenuPanel(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let originalCollector = model.monitoringCollector
            let originalMenuPreference = UserDefaults.standard.bool(forKey: "luma.menuBar")
            UserDefaults.standard.set(true, forKey: "luma.menuBar")
            defer { model.monitoringCollector = originalCollector; UserDefaults.standard.set(originalMenuPreference, forKey: "luma.menuBar") }
            var report: [String: Any] = ["mutationInvoked": false]
            func require(_ condition: Bool, _ message: String) throws {
                guard condition else { throw LumaError.rejected(message) }
                report[message] = true
            }
            func pause() async throws { try await Task.sleep(for: .milliseconds(300)) }
            @MainActor func click(_ window: NSWindow, at point: NSPoint) throws {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw LumaError.rejected("Mouse event unavailable") }
                    NSApp.postEvent(event, atStart: false)
                }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                model.openMain(.system)
                try await pause()
                guard let main = model.mainWindow else { throw LumaError.rejected("Main window unavailable") }
                try require(main.isVisible, "mainInitiallyVisible")
                main.close()
                try await pause()
                try require(!model.processDetailsVisible, "hiddenMainSkipsProcesses")
                for appearance in ["light", "dark", "system"] {
                    NSApp.deactivate()
                    try await pause()
                    UserDefaults.standard.set(appearance, forKey: "luma.appearance")
                    guard let panel = showMonitoringMenuForCheck() else { throw LumaError.rejected("Panel unavailable") }
                    try await pause()
                    report["\(appearance)OpeningState"] = ["visible": panel.isVisible, "key": panel.isKeyWindow, "active": NSApp.isActive, "frame": NSStringFromRect(panel.frame)]
                    try require(panel.isVisible && panel.isKeyWindow, "\(appearance)OpeningKey")
                    try require(!main.isVisible, "\(appearance)NoMainFlash")
                    try require(panel.styleMask.contains(.nonactivatingPanel) && !panel.styleMask.contains(.titled) && !panel.canBecomeMain, "\(appearance)Arrowless")
                    try require(panel.screen?.visibleFrame.contains(panel.frame) == true, "\(appearance)FitsScreen")
                    try require(panel.contentView is NSGlassEffectView, "\(appearance)NativeLiquidGlass")
                    try require(panel.frame.maxY == panel.screen?.visibleFrame.maxY, "\(appearance)NoMenuBarGap")
                    let openingAppearance = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                    try click(panel, at: NSPoint(x: 90, y: panel.frame.height - 100))
                    try await pause()
                    try require(panel.isKeyWindow && openingAppearance == panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) && !main.isVisible, "\(appearance)InteriorClickKeepsAppearance")
                    if appearance != "system" {
                        try require(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (appearance == "dark" ? .darkAqua : .aqua), "\(appearance)AppliedBeforeShow")
                    }
                    try saveScanCheckWindow(panel, path: output + "-\(appearance).png")
                    // Footer center points are in the real hosted view; exercise first-click delivery.
                    try click(panel, at: NSPoint(x: 265, y: 40))
                    try await pause()
                    try require(model.destination == .maintenance && main.isVisible && !panel.isVisible, "\(appearance)FirstClickMaintenance")
                    main.close()
                    _ = showMonitoringMenuForCheck()
                    try await pause()
                    try click(panel, at: NSPoint(x: 95, y: 40))
                    try await pause()
                    try require(main.isVisible && model.destination == .maintenance && !panel.isVisible, "\(appearance)FirstClickOpenRetainsPage")
                    main.close()
                    _ = showMonitoringMenuForCheck()
                    try await pause()
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) { NSApp.sendEvent(event) }
                    try await pause()
                    try require(!panel.isVisible, "\(appearance)EscapeDismisses")
                }
                // Negative-origin, right edge and short display fixtures exercise the production clamp.
                let screens = [NSRect(x: -1440, y: -200, width: 1440, height: 878), NSRect(x: 0, y: 0, width: 900, height: 420)]
                for screen in screens {
                    for x in [screen.minX, screen.maxX] {
                        let frame = StatusBarController.frame(anchor: NSRect(x: x, y: screen.maxY, width: 24, height: 24), contentSize: NSSize(width: 370, height: 600), visible: screen)
                        try require(frame.maxY == screen.maxY, "flushTop\(Int(screen.minX))Edge\(Int(x))")
                        try require(screen.contains(frame), "clamp\(Int(screen.minX))Edge\(Int(x))")
                    }
                }
                model.openMain(.storage)
                try await pause()
                try require(main.isVisible && model.destination == .storage, "navigateReopensAtRequestedPage")
                main.close()
                let history = model.cpuHistory.count
                try await Task.sleep(for: .milliseconds(2300))
                try require(model.cpuHistory.count > history, "menuOnlyMonitoringContinues")
                guard let panel = showMonitoringMenuForCheck() else { throw LumaError.rejected("Panel unavailable") }
                model.openMain()
                try await pause()
                try click(main, at: NSPoint(x: main.frame.width - 20, y: 30))
                try await pause()
                try require(!panel.isVisible, "outsideClickDismisses")
                try require(monitoringMenuDiagnosticsForCheck()["dismissalObservers"] as? Int == 0, "dismissalObserversRemoved")
                main.close()
                toggleMonitoringMenuForCheck()
                try await pause()
                try require(panel.isVisible, "iconClickOpens")
                toggleMonitoringMenuForCheck()
                try await pause()
                try require(!panel.isVisible, "iconClickCloses")
                model.openMain()
                try await pause()
                _ = showMonitoringMenuForCheck()
                UserDefaults.standard.set(false, forKey: "luma.menuBar")
                // The existing status/preference refresh runs every two seconds.
                try await Task.sleep(for: .milliseconds(2200))
                report["preferenceDisableState"] = monitoringMenuDiagnosticsForCheck()
                try require(!panel.isVisible && monitoringMenuDiagnosticsForCheck()["created"] as? Bool == false, "preferenceDisablesPanelAndIcon")
                try require(monitoringMenuDiagnosticsForCheck()["dismissalObservers"] as? Int == 0, "preferenceRemovesObservers")
                UserDefaults.standard.set(true, forKey: "luma.menuBar")
                try await Task.sleep(for: .milliseconds(2200))
                main.close()
                model.showSettingsWindow?()
                try await pause()
                try require(!main.isVisible, "settingsOnlyBeforeDockReopen")
                _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
                try await pause()
                try require(main.isVisible, "dockReopensWithSettingsVisible")
                var missing = SystemSample()
                let collecting = missing
                model.monitoringCollector = { _, _ in collecting }
                model.system = missing
                _ = showMonitoringMenuForCheck()
                try await pause()
                try saveScanCheckWindow(panel, path: output + "-collecting.png")
                hideMonitoringMenuForCheck()
                missing.sampledAt = Date().addingTimeInterval(-60)
                missing.batteryDetails = .init(presence: .available, input: .init(externalPower: false))
                let stale = missing
                model.monitoringCollector = { _, _ in stale }
                model.system = stale
                _ = showMonitoringMenuForCheck()
                try await pause()
                try saveScanCheckWindow(panel, path: output + "-unavailable-stale.png")
                report["displayCount"] = NSScreen.screens.count
            } catch { report["error"] = error.localizedDescription }
            hideMonitoringMenuForCheck()
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Menu panel QA failed: %@", error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
}
#endif
