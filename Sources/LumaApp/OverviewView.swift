import SwiftUI
import LumaCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            hero
            LiveOverviewMetrics()
            if let progress = model.scanProgress { ScanProgressCard(progress: progress) }
            else if let report = model.cleanupReport { ScanSummaryCard(report: report) }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "A good place to start", detail: "You’re in control")
                Surface(padding: 10) {
                    VStack(spacing: 0) {
                        InsightRow(symbol: "sparkles", tint: Palette.accent, title: model.cleanup.isEmpty ? "Find room in the everyday" : "Generated data, ready to review",
                                   subtitle: "Known app caches and developer build files. Every rule explained.",
                                   value: model.completedScans.contains(.clean) ? formatBytes(model.cleanupBytes) : "Run a check") {
                            model.destination = .clean
                            if !model.completedScans.contains(.clean) { model.runScan(.clean) }
                        }
                        Divider().padding(.leading, 56)
                        InsightRow(symbol: "square.stack.3d.up", tint: Palette.blue, title: "Apps have a bigger footprint than you think",
                                   subtitle: "Inspect application bundles and their related data.", value: "Explore") {
                            model.destination = .applications
                            if !model.completedScans.contains(.applications) { model.runScan(.applications) }
                        }
                        Divider().padding(.leading, 56)
                        InsightRow(symbol: "square.on.square", tint: Palette.peach, title: "One copy might be enough",
                                   subtitle: "Find exact duplicates with content verification, not guesswork.", value: "Choose folder") { model.chooseFolder(for: .duplicates) }
                    }.padding(.horizontal, 10)
                }
            }
            HStack(spacing: 9) {
                Image(systemName: "arrow.uturn.backward.circle").font(.system(size: 15)).foregroundStyle(Palette.mint)
                Text("Review first. Trash by default. Always your decision.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("LUMA / \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "DEV")").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 3)
        }
    }

    private var hero: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) { Circle().fill(Palette.mint).frame(width: 6, height: 6); Eyebrow(text: "Your Mac, in focus") }
                Text("More space.\nLess guesswork.").font(.system(size: 35, weight: .semibold)).tracking(-1.3).lineSpacing(0)
                Text("Understand what’s taking up space.\nMake changes with a little more confidence.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                PrimaryButton(title: model.completedScans.contains(.clean) ? "Review \(formatBytes(model.cleanupBytes))" : "Find reclaimable space", symbol: "arrow.right") {
                    model.destination = .clean
                    if !model.completedScans.contains(.clean) { model.runScan(.clean) }
                }.disabled(model.busy).padding(.top, 2)
            }
            Spacer(minLength: 0)
            LiveStorageOrbit()
                .frame(width: 245, height: 245)
        }
        .padding(.horizontal, 30).padding(.vertical, 25).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(Palette.surface.opacity(0.78))
            RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Palette.accent.opacity(0.025), Palette.accent.opacity(0.09), Palette.blue.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(scheme == .dark ? 0.07 : 0.5)))
    }

}

struct StorageOrbit: View {
    let total: Int64
    let available: Int64
    private var fraction: Double { min(1, max(0, 1 - Double(available) / Double(max(1, total)))) }
    var body: some View {
        ZStack {
            Circle().stroke(Palette.accent.opacity(0.035), lineWidth: 1).padding(2)
            Circle().stroke(Palette.accent.opacity(0.055), lineWidth: 1).padding(16)
            Circle().stroke(Palette.accent.opacity(0.085), lineWidth: 16).padding(34)
            Circle().trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [Palette.blue.opacity(0.55), Palette.accent.opacity(0.5), Palette.accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(34)
            VStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Palette.accent)
                Text(formatBytes(total - available)).font(.system(size: 25, weight: .semibold)).tracking(-1)
                Text("of \(formatBytes(total)) in use").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Circle().fill(Palette.mint).frame(width: 9, height: 9).overlay(Circle().stroke(.background, lineWidth: 3)).offset(x: 101, y: 58)
        }.accessibilityElement(children: .combine).accessibilityLabel("Storage: \(formatBytes(total - available)) used of \(formatBytes(total))")
    }
}

private struct LiveOverviewMetrics: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 14) {
                metric("MEMORY USED", value: formatMemory(model.system.usedMemory), detail: "of \(formatMemory(model.system.physicalMemory)) · \(model.system.pressure.lowercased()) pressure", symbol: "memorychip", tint: Palette.accent, history: model.memoryHistory)
                metric("CPU USAGE", value: model.cpuHistory.isEmpty ? "Sampling…" : "\(Int(model.system.cpu))%", detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores · \(model.system.thermal.lowercased()) thermals", symbol: "cpu", tint: Palette.blue, history: model.cpuHistory)
                metric("AVAILABLE SPACE", value: formatBytes(model.system.availableDisk), detail: "Available for important usage", symbol: "internaldrive", tint: Palette.accent, history: nil)
            }
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String, tint: Color, history: [Double]?) -> some View {
        Surface(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Eyebrow(text: title); Spacer(); Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint) }
                HStack(alignment: .firstTextBaseline) {
                    Text(value).font(.system(size: 24, weight: .semibold)).tracking(-0.7)
                    Spacer(minLength: 0)
                    if let history { Sparkline(values: history, tint: tint).frame(width: 65, height: 28) }
                }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

private struct LiveStorageOrbit: View {
    @Environment(AppModel.self) private var model
    var body: some View { StorageOrbit(total: model.system.totalDisk, available: model.system.availableDisk) }
}
