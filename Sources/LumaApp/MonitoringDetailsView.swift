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
                        Button("Battery settings") { model.openSettings("com.apple.preference.battery") }.buttonStyle(.glass)
                    }
                }
                if battery.presence == .available {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 16) {
                        metric("Current charge", battery.charge.map { "\($0)%" } ?? "Unavailable")
                        metric("Reported health", battery.health ?? "Unavailable")
                        metric("Reported condition", battery.condition ?? "Unavailable")
                        metric("Maximum capacity estimate", battery.maximumCapacityPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
                        metric("Charge cycles", battery.cycles.map(String.init) ?? "Unavailable")
                        metric(battery.estimatingFullCharge ? "Estimated time until full" : "Estimated time remaining", battery.estimateMinutes.map { "\($0) min" } ?? "Unavailable")
                    }
                    Text("Estimates come from your Mac and can change with workload or charging limits. Maximum capacity compares reported full charge and original capacities; current charge is separate. Missing fields remain unavailable. Battery settings may provide more detail.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let issue = battery.issue { Text(issue).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 10)).foregroundStyle(.secondary); Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
    }
}
