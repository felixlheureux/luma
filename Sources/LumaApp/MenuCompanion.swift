import SwiftUI
import LumaCore

struct MenuCompanion: View {
    @Environment(AppModel.self) private var model
    var dismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                LumaMark().frame(width: 30, height: 30)
                Text("Luma").font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    Text(model.system.sampledAt.map { context.date.timeIntervalSince($0) > 10 ? "Updated " + $0.formatted(date: .omitted, time: .shortened) : "Recent sample" } ?? "Collecting")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Menu {
                    Button("Settings…") { dismiss(); model.showSettingsWindow?() }
                    Divider()
                    Button("Quit Luma") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 24, height: 24)
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Luma menu")
            }

            HStack(spacing: 12) {
                tile {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("CPU", systemImage: "cpu").foregroundStyle(.secondary)
                        Text(model.system.cpuAvailable == false ? (model.system.sampledAt == nil ? "Collecting" : "Unavailable") : "\(Int(model.system.cpu))%")
                            .font(.system(size: 24, weight: .semibold)).tracking(-0.8).monospacedDigit()
                        Sparkline(values: model.cpuHistory, tint: Palette.blue).frame(height: 28)
                    }
                }
                tile {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.system.batteryDetails.presence == .notPresent ? "Thermals" : "Battery", systemImage: model.system.batteryDetails.presence == .notPresent ? "thermometer.medium" : model.system.onExternalPower ? "battery.100percent.bolt" : "battery.75percent")
                            .foregroundStyle(.secondary)
                        Text(model.system.batteryDetails.presence == .notPresent ? model.system.thermal : model.system.battery.map { "\($0)%" } ?? "Unavailable")
                            .font(.system(size: 24, weight: .semibold)).tracking(-0.8).monospacedDigit()
                        Text(model.system.batteryDetails.presence == .notPresent ? "System thermal state" : model.system.batteryDetails.state)
                            .font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 28, alignment: .bottom)
                    }
                }
            }

            Button {
                model.monitoringFocus = nil; show(.system)
                DispatchQueue.main.async { model.monitoringFocus = "network-details" }
            } label: {
                HStack {
                    Label("Network", systemImage: "network")
                    Spacer()
                    Text(model.system.network.state == .measuring ? "↓ \(formatNetworkRate(model.system.network.downloadRate))  ↑ \(formatNetworkRate(model.system.network.uploadRate))" : model.system.network.state.rawValue).monospacedDigit()
                }.font(.system(size: 11)).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Network activity. \(model.system.network.state.rawValue). Download \(formatNetworkRate(model.system.network.downloadRate)), upload \(formatNetworkRate(model.system.network.uploadRate)). Open details.")
                .help(model.system.network.state.rawValue)

            tile {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Memory", systemImage: "memorychip").foregroundStyle(.secondary)
                        Spacer()
                        Text(model.system.memoryAvailable ? "\(Int(model.system.memoryUsagePercent))% used" : "Unavailable").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(model.system.memoryAvailable ? formatMemory(model.system.usedMemory) : "Unavailable").font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                        Text("/ \(formatMemory(model.system.physicalMemory))").foregroundStyle(.secondary)
                    }.monospacedDigit()
                    if model.system.memoryAvailable { memoryBar }
                    HStack(spacing: 12) {
                        legend("App", tint: Palette.accent)
                        legend("Wired", tint: Palette.blue)
                        legend("Compressed", tint: Palette.peach)
                    }
                    Divider()
                    HStack {
                        Label("\(model.system.pressure) pressure", systemImage: "waveform.path.ecg")
                            .foregroundStyle(model.system.pressureTint)
                        Spacer()
                        Text(model.system.swapAvailable ? "Swap \(formatMemory(model.system.swap))" : "Swap unavailable").foregroundStyle(.secondary).monospacedDigit()
                    }.font(.system(size: 11, weight: .medium))
                }
            }

            tile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Storage", systemImage: "internaldrive").foregroundStyle(.secondary)
                        Spacer()
                        Text(model.system.diskAvailable ? "\(formatBytes(model.system.availableDisk)) available" : "Unavailable").fontWeight(.medium).monospacedDigit()
                    }
                    if model.system.diskAvailable { ProgressView(value: Double(max(0, model.system.totalDisk - model.system.availableDisk)), total: Double(max(1, model.system.totalDisk)))
                        .tint(Palette.accent).accessibilityLabel("Storage used") }
                }
            }

            HStack(spacing: 10) {
                Button { dismiss(); model.openMain() } label: {
                    Label("Open Luma", systemImage: "macwindow").frame(maxWidth: .infinity)
                }.buttonStyle(.glass)
                Button { show(.maintenance) } label: {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity)
                }.buttonStyle(.glass)
            }.controlSize(.large)

        }
        .font(.system(size: 12))
        .padding(20).frame(width: 370).tint(Palette.accent)
    }

    private var memoryBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(zip([model.system.appMemory, model.system.wiredMemory, model.system.compressedMemory], [Palette.accent, Palette.blue, Palette.peach]).enumerated()), id: \.offset) { _, segment in
                    segment.1.frame(width: geometry.size.width * CGFloat(segment.0) / CGFloat(max(1, model.system.physicalMemory)))
                }
                Spacer(minLength: 0)
            }.background(.primary.opacity(0.07)).clipShape(Capsule())
        }.frame(height: 7)
            .accessibilityLabel("Memory used \(Int(model.system.memoryUsagePercent)) percent")
    }

    private func legend(_ title: String, tint: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(tint).frame(width: 5, height: 5); Text(title) }
            .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.055)))
    }

    private func show(_ destination: Destination) {
        dismiss(); model.openMain(destination)
    }
}
