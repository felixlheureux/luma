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
                StatusPill(text: "Live")
                Button {
                    dismiss(); model.showSettingsWindow?()
                } label: {
                    Image(systemName: "gearshape").frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.glass).help("Luma Settings").accessibilityLabel("Luma Settings")
            }

            HStack(spacing: 12) {
                tile {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("CPU", systemImage: "cpu").foregroundStyle(.secondary)
                        Text(model.cpuHistory.isEmpty ? "—" : "\(Int(model.system.cpu))%")
                            .font(.system(size: 28, weight: .semibold)).tracking(-0.8).monospacedDigit()
                        Sparkline(values: model.cpuHistory, tint: Palette.blue).frame(height: 28)
                    }
                }
                tile {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.system.battery == nil ? "Thermals" : "Battery", systemImage: model.system.battery == nil ? "thermometer.medium" : model.system.onExternalPower ? "battery.100percent.bolt" : "battery.75percent")
                            .foregroundStyle(.secondary)
                        Text(model.system.battery.map { "\($0)%" } ?? model.system.thermal)
                            .font(.system(size: 28, weight: .semibold)).tracking(-0.8).monospacedDigit()
                        Text(model.system.battery == nil ? "System thermal state" : model.system.charging ? "Charging" : model.system.onExternalPower ? "Connected to power" : "On battery power")
                            .font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 28, alignment: .bottom)
                    }
                }
            }

            tile {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Memory", systemImage: "memorychip").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.system.memoryUsagePercent))% used").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(formatMemory(model.system.usedMemory)).font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                        Text("/ \(formatMemory(model.system.physicalMemory))").foregroundStyle(.secondary)
                    }.monospacedDigit()
                    memoryBar
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
                        Text("Swap \(formatMemory(model.system.swap))").foregroundStyle(.secondary).monospacedDigit()
                    }.font(.system(size: 11, weight: .medium))
                    Text("Pressure measures how easily macOS can supply RAM, not how much is used.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }

            tile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Storage", systemImage: "internaldrive").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatBytes(model.system.availableDisk)) free").fontWeight(.medium).monospacedDigit()
                    }
                    ProgressView(value: Double(max(0, model.system.totalDisk - model.system.availableDisk)), total: Double(max(1, model.system.totalDisk)))
                        .tint(Palette.accent).accessibilityLabel("Storage used")
                }
            }

            HStack(spacing: 10) {
                Button { show(.system) } label: {
                    Label("Open monitor", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity).padding(.vertical, 5).foregroundStyle(.white)
                }.buttonStyle(.glassProminent).tint(Palette.accent)
                Button { show(.clean) } label: {
                    Label("Clean", systemImage: "sparkles").padding(.horizontal, 8).padding(.vertical, 5).foregroundStyle(.primary)
                }.buttonStyle(.glass)
            }.font(.system(size: 12, weight: .semibold))
            HStack {
                Text("Updates every 2 seconds").foregroundStyle(.secondary)
                Spacer()
                Button("Quit Luma") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.system(size: 10))
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
        dismiss(); model.destination = destination
        model.showMainWindow?()
    }
}
