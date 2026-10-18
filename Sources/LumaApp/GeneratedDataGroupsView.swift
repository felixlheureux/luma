import SwiftUI
import LumaCore

struct GeneratedDataGroupsView: View {
    @Environment(AppModel.self) private var model
    let items: [CleanupItem]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            content(running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        }
    }
    private func content(running: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(GeneratedDataGroup.groups(for: items)) { group in
                Surface(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.appName).font(.system(size: 15, weight: .semibold))
                                Text(group.category.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatBytes(model.generatedBytes(group.items))).monospacedDigit().font(.system(size: 14, weight: .medium))
                        }
                        if let owner = group.owner {
                            let active = running.contains { $0 == owner || $0.hasPrefix(owner + ".") }
                            Label(active ? "App or helper is running · quit before cleaning" : "App activity is checked again before cleanup", systemImage: active ? "pause.circle" : "info.circle")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text("Active tools are checked again before cleanup.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ItemList(items: group.items)
                    }
                }
            }
            Text("Logical bytes count hard links once within each group and the overall total. Groups can share content; their sizes may not add up. Review verifies the exact selection. Physical savings can differ.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
