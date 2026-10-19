import SwiftUI
import LumaCore

func formatNetworkRate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0, let bytes = Int64(exactly: value.rounded(.towardZero)) else { return "—" }
    return formatBytes(bytes) + "/s"
}

struct NetworkDetailsView: View {
    @Environment(AppModel.self) private var model
    private var activity: NetworkActivity { model.system.network }
    private var interfaces: [NetworkInterfaceSample] { model.system.networkObservation?.interfaces ?? [] }
    var body: some View {
        @Bindable var model = model
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Network activity", detail: activity.state.rawValue)
                Picker("Interface", selection: $model.networkInterface) {
                    Text("Automatic · system primary (IPv4, then IPv6)").tag(String?.none)
                    ForEach(interfaces) { interface in
                        Text("\(interface.name) · \(interface.kind)\(interface.active ? "" : " · inactive")").tag(Optional(interface.name))
                    }
                    if let selected = model.networkInterface, !interfaces.contains(where: { $0.name == selected }) { Text("\(selected) · unavailable").tag(Optional(selected)) }
                }.font(.system(size: 12))
                HStack(spacing: 30) {
                    metric("Download", formatNetworkRate(activity.downloadRate))
                    metric("Upload", formatNetworkRate(activity.uploadRate))
                    metric("Session received", activity.totalsAvailable ? formatBytes(Int64(clamping: activity.downloaded)) : "Unavailable")
                    metric("Session sent", activity.totalsAvailable ? formatBytes(Int64(clamping: activity.uploaded)) : "Unavailable")
                }
                if let interface = activity.interface {
                    Text("\(interface.name) · \(interface.kind)").font(.system(size: 12, weight: .medium))
                    DisclosureGroup("Local addresses · visible only on this Mac") {
                        if interface.addresses.isEmpty { Text("Local address metadata unavailable.") }
                        ForEach(interface.addresses, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                        Text("Wi-Fi names, browsing history and application traffic are not collected.").foregroundStyle(.secondary)
                    }.font(.system(size: 11))
                }
                if let detail = activity.detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text("One interface at a time. Physical and VPN/tunnel counters are never added together. Session totals include only measured intervals while Luma runs; switches, resets and sleep gaps are omitted. Activity is not an internet speed or connection-quality test.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.networkInterface) { _, value in
            model.networkTracker.resetBaseline()
            if let observation = model.system.networkObservation { model.system.network = model.networkTracker.consume(observation, selectedInterface: value) }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 10)).foregroundStyle(.secondary); Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatteryDetailsView: View {
    @Environment(AppModel.self) private var model
    private var battery: BatteryDetails { model.system.batteryDetails }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeading(title: "Battery", detail: battery.state)
                    Spacer()
                    if battery.presence != .notPresent {
                        Button("Refresh") { Task { await model.refreshBatteryReport(force: true) } }.disabled(model.batteryReportLoading)
                        Button("Battery settings") { model.openSettings("com.apple.preference.battery") }.buttonStyle(.glass)
                    }
                }
                if battery.presence == .available {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
                        metric("Current charge", battery.charge.map { "\($0)%" } ?? "Unavailable")
                        metric(battery.estimatingFullCharge ? "Estimated time until full" : "Estimated time remaining", battery.estimateText)
                        if let condition = model.batteryReport?.condition ?? battery.condition ?? battery.health { metric("Reported condition", condition) }
                        if let capacity = model.batteryReport?.maximumCapacityPercent { metric("Maximum capacity", String(format: "%.0f%%", capacity)) }
                        if let cycles = model.batteryReport?.cycles ?? battery.cycles { metric("Charge cycles", String(cycles)) }
                    }
                    if model.batteryReportLoading { Text("Refreshing battery details…").font(.caption).foregroundStyle(.secondary) }
                    if let report = model.batteryReport {
                        Text("System Power report · \(report.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.batteryReport?.condition == nil || model.batteryReport?.cycles == nil || model.batteryReport?.maximumCapacityPercent == nil {
                        Text("Some battery details are unavailable. Battery Settings and System Information may provide more information.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("System Information") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app")) }.buttonStyle(.link)
                    if let issue = model.batteryReportIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                }
                if let issue = battery.issue { Text(issue).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
        .task(id: battery.sourceIdentity) { await model.refreshBatteryReport() }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 10)).foregroundStyle(.secondary); Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
            .nativeCheckTarget("battery-" + label)
    }
}
