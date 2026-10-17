import SwiftUI
import Charts
import LumaCore

struct SystemView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                graphCard(title: "CPU", value: "\(Int(model.system.cpu))%", detail: "\(ProcessInfo.processInfo.activeProcessorCount) active cores", values: model.cpuHistory, tint: Palette.blue)
                graphCard(title: "Memory pressure", value: model.system.pressure, detail: "\(formatMemory(model.system.usedMemory)) / \(formatMemory(model.system.physicalMemory))", values: model.memoryHistory, tint: Palette.mint)
            }
            Surface {
                HStack(spacing: 30) {
                    readout("SWAP", value: formatMemory(model.system.swap), symbol: "arrow.left.arrow.right")
                    readout("COMPRESSED", value: formatMemory(model.system.compressedMemory), symbol: "arrow.down.right.and.arrow.up.left")
                    readout("THERMAL STATE", value: model.system.thermal, symbol: "thermometer.medium")
                    readout("UPTIME", value: uptime, symbol: "clock")
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "Memory breakdown", detail: "Used = app + wired + compressed")
                    HStack(spacing: 22) {
                        readout("APP MEMORY", value: formatMemory(model.system.appMemory), symbol: "app")
                        readout("WIRED", value: formatMemory(model.system.wiredMemory), symbol: "lock")
                        readout("CACHED FILES", value: formatMemory(model.system.cachedMemory), symbol: "doc.on.doc")
                        readout("AVAILABLE", value: formatMemory(model.system.availableMemory), symbol: "memorychip")
                    }
                    Text("Reusable file cache is shown separately from used memory. macOS can reclaim it when applications need RAM.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let battery = model.system.battery {
                Surface {
                    HStack(spacing: 15) {
                        SymbolTile(symbol: model.system.charging ? "battery.100percent.bolt" : "battery.75percent", tint: Palette.mint)
                        VStack(alignment: .leading, spacing: 5) { Text("Battery").font(.system(size: 14, weight: .semibold)); Text(model.system.charging ? "Connected to power · charging" : "Current charge · health is available in System Settings").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer(); Text("\(battery)%").font(.system(size: 25, weight: .semibold))
                        Button("Battery settings") { model.openSettings("com.apple.preference.battery") }.buttonStyle(.glass)
                    }
                }
            }
            ProcessList()
        }
    }
    private var uptime: String {
        let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h"
    }
    private func graphCard(title: String, value: String, detail: String, values: [Double], tint: Color) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text(title).font(.system(size: 13, weight: .semibold)); Spacer(); StatusPill(text: "Live", tint: tint) }
                Text(value).font(.system(size: 34, weight: .semibold)).tracking(-1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                Sparkline(values: values, tint: tint).frame(height: 90)
                Text("Last \(values.count * 2) seconds · sampled every 2s").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
    private func readout(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); Label(value, systemImage: symbol).font(.system(size: 13, weight: .medium)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProcessList: View {
    @Environment(AppModel.self) private var model
    @ViewState private var sortCPU = false
    @ViewState private var expanded: Set<String> = []
    @ViewState private var appToQuit: NSRunningApplication?
    private var groups: [ProcessGroup] {
        Array((sortCPU ? model.system.processGroups.sorted { $0.cpu > $1.cpu } : model.system.processGroups).prefix(12))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Resource consumers", detail: "Grouped by app · expand to inspect helpers")
            Surface(padding: 18) {
                VStack(spacing: 0) {
                    HStack {
                        Text("APPLICATION / PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                        Button("CPU ↓") { sortCPU = true }.buttonStyle(.plain).frame(width: 65, alignment: .trailing)
                        Button("MEMORY ↓") { sortCPU = false }.buttonStyle(.plain).frame(width: 100, alignment: .trailing)
                        Spacer().frame(width: 62)
                    }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 12)
                    if groups.isEmpty { Text("Collecting application data…").font(.system(size: 12)).foregroundStyle(.secondary).padding(25) }
                    ForEach(groups) { group in
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(group.id) }, set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } })) {
                            ForEach(group.processes) { process in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(process.name).font(.system(size: 10, weight: .medium))
                                        Text("PID \(String(process.pid))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.1f%%", process.cpu)).frame(width: 65, alignment: .trailing)
                                    Text(formatMemory(process.memory)).frame(width: 100, alignment: .trailing)
                                        .help(process.usesFootprint ? "Native physical memory footprint" : "Resident memory; footprint unavailable for this process")
                                    Spacer().frame(width: 62)
                                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.vertical, 6).padding(.leading, 16)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if let bundle = group.bundleURL {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: bundle.path)).resizable().frame(width: 28, height: 28)
                                } else { Image(systemName: "gearshape.2").frame(width: 28).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.system(size: 12, weight: .medium))
                                    Text("\(group.processes.count) \(group.processes.count == 1 ? "process" : "processes")").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.1f%%", group.cpu)).frame(width: 65, alignment: .trailing)
                                Text(formatMemory(group.memory)).frame(width: 100, alignment: .trailing)
                                if let pid = group.mainPID, let app = NSRunningApplication(processIdentifier: pid),
                                   app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                                   !["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow"].contains(app.bundleIdentifier ?? "") {
                                    Button("Quit") { appToQuit = app }.buttonStyle(.bordered).controlSize(.mini).frame(width: 62)
                                } else { Spacer().frame(width: 62) }
                            }.font(.system(size: 11, design: .monospaced)).padding(.vertical, 9)
                        }
                        if group.id != groups.last?.id { Divider() }
                    }
                }
            }
            Text("Memory combines app processes using native physical footprint where available, with resident memory as a fallback. CPU can exceed 100% across cores.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .alert("Quit \(appToQuit?.localizedName ?? "application")?", isPresented: Binding(get: { appToQuit != nil }, set: { if !$0 { appToQuit = nil } })) {
            Button("Cancel", role: .cancel) { appToQuit = nil }
            Button("Quit application") { appToQuit?.terminate(); appToQuit = nil }
        } message: { Text("The app will receive a normal quit request and may ask you to save open documents.") }
    }
}

struct OptimizerView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                HStack(spacing: 22) {
                    SymbolTile(symbol: "memorychip", tint: Palette.mint, size: 64)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Memory pressure is \(model.system.pressure.lowercased())").font(.system(size: 20, weight: .semibold)); Spacer() }
                        Text("macOS uses spare memory for useful caches. Freeing RAM is not a goal on its own. If your Mac feels slow, review the applications using resources below.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                    }
                }
            }
            Surface(padding: 12) {
                VStack(spacing: 0) {
                    InsightRow(symbol: "power", tint: Palette.accent, title: "Login & background items", subtitle: "Review which apps start at login using macOS controls.", value: "System Settings") { model.openSettings("com.apple.LoginItems-Settings.extension") }
                    Divider().padding(.leading, 56)
                    InsightRow(symbol: "magnifyingglass", tint: Palette.blue, title: "Spotlight search", subtitle: "Manage indexed locations when search results are incomplete.", value: "System Settings") { model.openSettings("com.apple.Spotlight-Settings.extension") }
                    Divider().padding(.leading, 56)
                    InsightRow(symbol: "clock.arrow.circlepath", tint: Palette.mint, title: "Time Machine", subtitle: "macOS manages local snapshots and reclaims space as needed.", value: "System Settings") { model.openSettings("com.apple.Time-Machine-Settings.extension") }
                }.padding(.horizontal, 8)
            }
            ProcessList()
        }
    }
}
