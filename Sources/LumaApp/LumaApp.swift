import SwiftUI
import LumaCore

@main
struct LumaApp: App {
    @NSApplicationDelegateAdaptor(LumaAppDelegate.self) private var delegate
    @ViewState private var model = AppModel.shared
    @AppStorage("luma.appearance") private var appearance = "system"
    var body: some Scene {
        Window("Luma", id: "main") {
            RootView().environment(model)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task {
                    let args = CommandLine.arguments
                    if let flag = args.firstIndex(of: "--page"), args.indices.contains(flag + 1), let page = Destination(rawValue: args[flag + 1]) { model.destination = page }
                }
        }
        .defaultSize(width: 1200, height: 850)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button(appearance == "dark" ? "Use Light Appearance" : "Use Dark Appearance") {
                    appearance = appearance == "dark" ? "light" : "dark"
                }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                Button("Overview") { model.destination = .overview }.keyboardShortcut("1")
                Button("Clean") { model.destination = .clean }.keyboardShortcut("2")
                Button("Optimizer") { model.destination = .optimizer }.keyboardShortcut("3")
                Button("Applications") { model.destination = .applications }.keyboardShortcut("4")
                Button("Storage") { model.destination = .storage }.keyboardShortcut("5")
                Button("Duplicates") { model.destination = .duplicates }.keyboardShortcut("6")
                Button("Privacy") { model.destination = .privacy }.keyboardShortcut("7")
                Button("System") { model.destination = .system }.keyboardShortcut("8")
                Button("Activity") { model.destination = .history }.keyboardShortcut("9")
            }
        }
        Settings { SettingsView().environment(model).preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil) }
    }

}

@MainActor final class LumaAppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "luma.menuBar")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showMainWindow?() }
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["luma.menuBar": true, "luma.appearance": "system"])
        AppModel.shared.startMonitoring()
        statusController = StatusBarController(model: AppModel.shared)
        NSApplication.shared.setActivationPolicy(.regular)
        if !CommandLine.arguments.contains("--snapshot") { NSApplication.shared.activate() }
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.captureSnapshot() }
        }
        if CommandLine.arguments.contains("--snapshot-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.statusController?.showForPreview()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.captureSnapshot() }
            }
        }
        let arguments = CommandLine.arguments
        #if DEBUG
        if let flag = arguments.firstIndex(of: "--check-storage-browser"), arguments.indices.contains(flag + 1) {
            checkStorageBrowser(output: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--check-scan-sessions"), arguments.indices.contains(flag + 1) {
            checkScanSessions(output: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--check-cleanup-sessions"), arguments.indices.contains(flag + 1) {
            checkCleanupSessions(output: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--check-cleanup-review"), arguments.indices.contains(flag + 1) {
            checkCleanupReview(output: arguments[flag + 1])
        }
        #endif
        if let flag = arguments.firstIndex(of: "--scan-report"), arguments.indices.contains(flag + 1) {
            checkGeneratedScan(output: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--check-window-lifecycle"), arguments.indices.contains(flag + 1) {
            checkWindowLifecycle(output: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--diagnostics"), arguments.indices.contains(flag + 1) {
            let output = arguments[flag + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                let model = AppModel.shared
                let report: [String: Any] = [
                    "menuBar": self.statusController?.diagnostics() ?? [:],
                    "physicalMemory": model.system.physicalMemory, "usedMemory": model.system.usedMemory,
                    "appMemory": model.system.appMemory, "wiredMemory": model.system.wiredMemory,
                    "compressedMemory": model.system.compressedMemory, "cachedMemory": model.system.cachedMemory,
                    "pressure": model.system.pressure, "sampleCount": model.cpuHistory.count,
                    "processGroups": model.system.processGroups.prefix(12).map { ["name": $0.name, "count": $0.processes.count, "memory": $0.memory, "footprint": $0.usesFootprint] as [String: Any] }
                ]
                do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
                catch { FileHandle.standardError.write(Data("Diagnostics could not be saved: \(error.localizedDescription)\n".utf8)) }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    #if DEBUG
    func scanCheckMenuVisible() -> Bool { statusController?.diagnostics()["visible"] as? Bool == true }
    #endif

    // Read-only QA: run the same scan and view used by the Clean page. Nothing
    // is selected, reviewed, or moved by this opt-in diagnostic.
    private func checkGeneratedScan(output: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let model = AppModel.shared
            model.destination = .clean; model.runScan(.clean)
            let deadline = Date().addingTimeInterval(90)
            while model.busy && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
            let report = model.cleanupReport
            let result: [String: Any] = [
                "completed": report != nil && !model.busy,
                "rules": Rules.generated.count, "items": report?.items.count ?? 0,
                "coverage": report?.coverage.count ?? 0,
                "blocked": report?.coverage.filter { $0.state == .blocked }.count ?? 0,
                "skipped": report?.coverage.filter { $0.state == .skipped }.count ?? 0,
                "seconds": report?.duration ?? 0,
                "selected": model.selected.count,
                "foundRuleIDs": Array(Set(report?.items.map(\.ruleID) ?? [])).sorted(),
                "locations": report?.coverage.map { ["rule": $0.ruleID, "state": $0.state.rawValue, "path": $0.path, "detail": $0.detail] } ?? [],
                "error": model.error ?? ""
            ]
            do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
            catch { FileHandle.standardError.write(Data("Scan report failed: \(error.localizedDescription)\n".utf8)) }
            if CommandLine.arguments.contains("--scan-snapshot"), !model.busy {
                try? await Task.sleep(for: .seconds(1)); captureSnapshot()
            } else { model.cancel(); NSApp.terminate(nil) }
        }
    }

    // Exercise the real window and status item without Accessibility permission.
    // This opt-in check writes only its requested report, then explicitly quits.
    private func checkWindowLifecycle(output: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                self.writeLifecycleReport(["error": "Main window unavailable"], output: output)
                return
            }
            let samplesBefore = AppModel.shared.cpuHistory.count
            window.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                let closed = !NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
                let monitoring = AppModel.shared.cpuHistory.count > samplesBefore
                let status = self.statusController?.diagnostics() ?? [:]
                AppModel.shared.showMainWindow?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let reopened = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
                    self.writeLifecycleReport(["windowClosed": closed, "monitoringContinued": monitoring,
                        "windowReopened": reopened, "menuBar": status], output: output)
                }
            }
        }
    }

    private func writeLifecycleReport(_ report: [String: Any], output: String) {
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
        catch { FileHandle.standardError.write(Data("Lifecycle report failed: \(error.localizedDescription)\n".utf8)) }
        NSApp.terminate(nil)
    }

    private func captureSnapshot() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot") ?? args.firstIndex(of: "--snapshot-menu") ?? args.firstIndex(of: "--scan-snapshot"), args.indices.contains(flag + 1) else { return }
        let target = args.contains("--snapshot-menu") ? statusController?.previewWindow : NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        guard let window = target else {
            NSApplication.shared.terminate(nil)
            return
        }
        // Capture only our own window so composited glass and native toolbar
        // controls are represented. Fall back to a view render if unavailable.
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), args[flag + 1]]
        capture.standardOutput = FileHandle.nullDevice; capture.standardError = FileHandle.nullDevice
        if (try? capture.run()) != nil {
            capture.waitUntilExit()
            if capture.terminationStatus == 0 { NSApplication.shared.terminate(nil); return }
        }
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("Snapshot failed: no visible application window.\n".utf8))
            NSApplication.shared.terminate(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // View caching omits the popover's native material. Composite the fallback
        // over its appearance's window color so translucent content stays legible.
        let image = NSImage(size: view.bounds.size, flipped: false) { rect in
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                rect.fill()
                bitmap.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: args[flag + 1]))
        }
        NSApplication.shared.terminate(nil)
    }
}
