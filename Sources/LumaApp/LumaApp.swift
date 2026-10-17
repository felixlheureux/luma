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
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["luma.menuBar": true, "luma.appearance": "system"])
        AppModel.shared.startMonitoring()
        statusController = StatusBarController(model: AppModel.shared)
        NSApplication.shared.setActivationPolicy(.regular)
        if !CommandLine.arguments.contains("--snapshot") { NSApplication.shared.activate() }
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.captureSnapshot() }
        }
        let arguments = CommandLine.arguments
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

    private func captureSnapshot() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return }
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
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
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: args[flag + 1]))
        }
        NSApplication.shared.terminate(nil)
    }
}

struct MenuCompanion: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { LumaMark().frame(width: 27, height: 27); Text("Luma").font(.system(size: 17, weight: .semibold)); Spacer(); StatusPill(text: "Live · 2s") }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("CPU", systemImage: "cpu").foregroundStyle(.secondary)
                    Spacer(); Text("\(Int(model.system.cpu))%").font(.system(size: 24, weight: .semibold)).monospacedDigit()
                }
                Sparkline(values: model.cpuHistory, tint: Palette.blue).frame(height: 44)
            }
            Divider()
            VStack(spacing: 12) {
                HStack { Label("Memory pressure", systemImage: "memorychip"); Spacer(); Text(model.system.pressure).foregroundStyle(model.system.pressure == "Low" ? Palette.mint : Palette.peach) }
                LabeledContent("Memory used", value: "\(formatMemory(model.system.usedMemory)) / \(formatMemory(model.system.physicalMemory))")
                LabeledContent("Swap", value: formatMemory(model.system.swap))
                LabeledContent("Available space", value: formatBytes(model.system.availableDisk))
                LabeledContent("Thermals", value: model.system.thermal)
                if let battery = model.system.battery {
                    LabeledContent(model.system.charging ? "Battery · charging" : "Battery", value: "\(battery)%")
                }
            }.font(.system(size: 11))
            Divider()
            HStack(spacing: 8) {
                Button { show(.system) } label: { Label("Monitor", systemImage: "waveform.path.ecg") }
                Button { show(.clean) } label: { Label("Clean", systemImage: "sparkles") }
                Spacer()
                Menu {
                    Button("Open Luma") { show(.overview) }
                    Button("Settings…") { model.showSettingsWindow?() }
                    Divider()
                    Button("Quit Luma") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
            }.buttonStyle(.glass).controlSize(.small)
        }.font(.system(size: 12)).padding(22).frame(width: 320)
    }
    private func show(_ destination: Destination) {
        model.destination = destination
        model.showMainWindow?(); NSApplication.shared.activate()
    }
}
