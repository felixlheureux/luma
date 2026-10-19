import SwiftUI
import Charts
import Darwin
import LumaCore

struct SystemView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                graphCard(title: "CPU", available: model.system.cpuAvailable, value: model.system.cpuAvailable ? "\(Int(model.system.cpu))%" : missingReading, detail: "\(ProcessInfo.processInfo.activeProcessorCount) active cores", values: model.cpuHistory, tint: Palette.blue)
                graphCard(title: "Memory used", available: model.system.memoryAvailable, value: model.system.memoryAvailable ? "\(Int(model.system.memoryUsagePercent))%" : missingReading, detail: model.system.memoryAvailable ? "\(formatMemory(model.system.usedMemory)) / \(formatMemory(model.system.physicalMemory)) · \(model.system.pressure.lowercased()) pressure" : "Memory reading unavailable", values: model.memoryHistory, tint: Palette.accent)
            }
            Surface {
                HStack(spacing: 30) {
                    readout("SWAP", value: model.system.swapAvailable ? formatMemory(model.system.swap) : missingReading, symbol: "arrow.left.arrow.right")
                    readout("COMPRESSED", value: model.system.memoryAvailable ? formatMemory(model.system.compressedMemory) : missingReading, symbol: "arrow.down.right.and.arrow.up.left")
                    readout("THERMAL STATE", value: model.system.thermal, symbol: "thermometer.medium")
                    readout("UPTIME", value: uptime, symbol: "clock")
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "Memory breakdown", detail: "Used = app + wired + compressed")
                    HStack(spacing: 22) {
                        readout("APP MEMORY", value: model.system.memoryAvailable ? formatMemory(model.system.appMemory) : missingReading, symbol: "app")
                        readout("WIRED", value: model.system.memoryAvailable ? formatMemory(model.system.wiredMemory) : missingReading, symbol: "lock")
                        readout("CACHED FILES", value: model.system.memoryAvailable ? formatMemory(model.system.cachedMemory) : missingReading, symbol: "doc.on.doc")
                        readout("AVAILABLE", value: model.system.memoryAvailable ? formatMemory(model.system.availableMemory) : missingReading, symbol: "memorychip")
                    }
                    Text("Reusable file cache is shown separately from used memory. macOS can reclaim it when applications need RAM.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Label("\(model.system.pressure) memory pressure", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(model.system.pressureTint)
                    Text("Pressure reflects how easily macOS can supply RAM. High usage alone does not mean high pressure.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            NetworkDetailsView().id("network-details")
            BatteryDetailsView().id("battery-details")
            ProcessList()
        }
    }
    private var uptime: String {
        let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h"
    }
    private var missingReading: String { model.system.sampledAt == nil ? "Collecting" : "Unavailable" }
    private func graphCard(title: String, available: Bool, value: String, detail: String, values: [Double], tint: Color) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text(title).font(.system(size: 13, weight: .semibold)); Spacer(); TimelineView(.periodic(from: .now, by: 2)) { context in
                    StatusPill(text: model.system.sampledAt.map { sampled in
                        context.date.timeIntervalSince(sampled) > 10 ? "Updated " + sampled.formatted(date: .omitted, time: .shortened) : available ? "Recent sample" : "Unavailable"
                    } ?? "Collecting", tint: tint)
                } }
                Text(value).font(.system(size: 34, weight: .semibold)).tracking(-1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                Sparkline(values: values, tint: tint).accessibilityLabel("\(title) history").frame(height: 90)
                Text("\(values.count) measured samples · every 2s while available").font(.system(size: 10)).foregroundStyle(.tertiary)
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
    @ViewState private var frozenGroups: [ProcessGroup] = []
    @ViewState private var quitMessages: [String: String] = [:]
    @ViewState private var quitApps: [String: NSRunningApplication] = [:]
    private var groups: [ProcessGroup] {
        Array((sortCPU ? frozenGroups.sorted { $0.cpu > $1.cpu } : frozenGroups).prefix(12))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Resource consumers", detail: "Snapshot · refresh explicitly to keep Quit targets stable")
                Button("Refresh consumers") { frozenGroups = model.system.processGroups; quitMessages = [:]; quitApps = [:] }
            }
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
                                if group.bundleURL != nil {
                                    Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.secondary).frame(width: 28, height: 28)
                                } else { Image(systemName: "gearshape.2").frame(width: 28).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.system(size: 12, weight: .medium))
                                    Text("\(group.processes.count) \(group.processes.count == 1 ? "process" : "processes")").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.1f%%", group.cpu)).frame(width: 65, alignment: .trailing)
                                Text(formatMemory(group.memory)).frame(width: 100, alignment: .trailing)
                                Spacer().frame(width: 62)
                            }.font(.system(size: 11, design: .monospaced)).padding(.vertical, 9)
                        }
                        .overlay(alignment: .topTrailing) {
                            // Keep this separate from the disclosure button so
                            // requesting Quit never also toggles the group.
                            if let pid = group.mainPID, let app = NSRunningApplication(processIdentifier: pid),
                               app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                               !["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow"].contains(app.bundleIdentifier ?? "") {
                                Button("Quit") { requestQuit(group) }.buttonStyle(.bordered).controlSize(.mini)
                                    .frame(width: 62).padding(.top, 16)
                            }
                        }
                        if let message = quitMessages[group.id] {
                            TimelineView(.periodic(from: .now, by: 2)) { _ in
                                Text(quitApps[group.id]?.isTerminated == true ? "Exited · observe current memory pressure above." : message)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if group.id != groups.last?.id { Divider() }
                    }
                }
            }
            Text("Memory combines app processes using native physical footprint where available, with resident memory as a fallback. CPU can exceed 100% across cores.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .task { frozenGroups = model.system.processGroups }
        .onChange(of: model.system.processGroups.isEmpty) { _, empty in
            if !empty && frozenGroups.isEmpty { frozenGroups = model.system.processGroups }
        }
    }
    private func requestQuit(_ group: ProcessGroup) {
        guard let pid = group.mainPID, let sampled = group.processes.first(where: { $0.pid == pid }),
              sampled.instance != nil, let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, app.activationPolicy == .regular,
              app.bundleURL == group.bundleURL, app.executableURL?.path == sampled.executable,
              let sampledID = sampled.bundleIdentifier, app.bundleIdentifier == sampledID,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow"].contains(app.bundleIdentifier ?? "") else {
            quitMessages[group.id] = "Quit unavailable: sampled application disappeared or cannot be verified. Refresh consumers."; return
        }
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self))
        }
        let current = status == 0 ? ProcessSample(pid: pid, parentPID: 0, executable: app.executableURL?.path ?? "", cpu: 0, memory: 0,
            instance: usage.ri_proc_start_abstime, bundleIdentifier: app.bundleIdentifier) : nil
        switch sampled.requestNormalQuit(current: current, request: { app.terminate() }) {
        case .unavailable:
            quitMessages[group.id] = "Quit refused: process instance changed or is unavailable. Refresh consumers."
        case .refused:
            quitMessages[group.id] = "Quit refused or unavailable. The app remains running."
        case .requested:
            quitApps[group.id] = app
            quitMessages[group.id] = "Quit requested · awaiting save/exit. No memory savings confirmed."
        }
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
