import SwiftUI
import LumaCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LiveOverviewMetrics()
            Surface(padding: 18) {
                VStack(spacing: 0) {
                    shortcut(.applications, detail: model.visibleApplications.isEmpty ? "Browse installed applications" : "\(model.visibleApplications.count) observed applications")
                    Divider().padding(.vertical, 10)
                    shortcut(.residues, detail: model.residueSavedAt == nil ? "Find potentially unclaimed app data" : "\(model.visibleResidues.count) observed items · refresh on entry")
                    Divider().padding(.vertical, 10)
                    shortcut(.storage, detail: model.storageIndex == nil ? "Scan when you’re ready" : "Saved observations available · scan to update")
                    Divider().padding(.vertical, 10)
                    shortcut(.maintenance, detail: "Choose a maintenance action")
                    Divider().padding(.vertical, 10)
                    shortcut(.system, detail: "Live measurements and running applications")
                }
            }
        }
    }
    private func shortcut(_ page: Destination, detail: String) -> some View {
        Button { model.openCore(page) } label: {
            HStack(spacing: 14) {
                Image(systemName: page.symbol).foregroundStyle(Palette.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.rawValue).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("overview-" + page.id).nativeCheckTarget("overview-" + page.id)
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
    private var missing: String { model.system.sampledAt == nil ? "Collecting…" : "Unavailable" }
    private var stale: Bool { model.system.sampledAt.map { Date().timeIntervalSince($0) > 10 } ?? false }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { metrics(compact: false) }
            Surface(padding: 16) { VStack(spacing: 16) { metrics(compact: true) } }
        }
    }
    @ViewBuilder private func metrics(compact: Bool) -> some View {
        metric("MEMORY USED", value: model.system.memoryAvailable ? formatMemory(model.system.usedMemory) : missing,
               detail: model.system.memoryAvailable ? "of \(formatMemory(model.system.physicalMemory)) · \(model.system.pressure.lowercased()) pressure" : "Memory measurement", symbol: "memorychip", compact: compact)
        metric("CPU USAGE", value: model.system.cpuAvailable ? "\(Int(model.system.cpu))%" : missing,
               detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores", symbol: "cpu", compact: compact)
        metric("AVAILABLE SPACE", value: model.system.diskAvailable ? formatBytes(model.system.availableDisk) : missing,
               detail: "Available for important usage", symbol: "internaldrive", compact: compact)
    }
    @ViewBuilder private func metric(_ title: String, value: String, detail: String, symbol: String, compact: Bool) -> some View {
        if compact {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Palette.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: title)
                    Text(stale ? "Stale · " + detail : detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(value).font(.system(size: 18, weight: .semibold)).fixedSize()
            }
        } else {
            Surface(padding: 17) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Eyebrow(text: title); Spacer(); Image(systemName: symbol).foregroundStyle(Palette.accent) }
                    Text(value).font(.system(size: 24, weight: .semibold)).tracking(-0.7)
                    Text(stale ? "Stale · " + detail : detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(minWidth: 155, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
