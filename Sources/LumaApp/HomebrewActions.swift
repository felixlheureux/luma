import SwiftUI
import LumaCore

extension AppModel {
    func refreshHomebrew() {
        guard !homebrewLoading else { return }
        homebrewLoading = true
        let reader = homebrewReader
        homebrewTask = Task { @MainActor [self] in
            let worker = Task.detached(priority: .utility) { try reader() }
            let result = await withTaskCancellationHandler { await worker.result } onCancel: { worker.cancel() }
            homebrewLoading = false
            if Task.isCancelled { homebrewStatus = "Stopped. Previous Homebrew observations may be stale."; return }
            switch result {
            case .success(let inventory):
                homebrewInventory = inventory
                homebrewStatus = inventory.issues.isEmpty ? "Read-only observations · " + inventory.observedAt.formatted() : inventory.issues.joined(separator: "\n")
            case .failure(let error):
                homebrewInventory = nil
                homebrewStatus = "Homebrew unavailable: " + error.localizedDescription
            }
        }
    }
    func homebrewCask(_ app: ApplicationRecord) -> String? { homebrewInventory?.cask(for: app.url) }
}

struct HomebrewMaintenanceSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Homebrew").font(.headline)
                    Spacer()
                    if model.homebrewLoading {
                        ProgressView().controlSize(.small)
                        Button("Stop") { model.homebrewTask?.cancel() }
                    }
                    Button("Refresh Homebrew") { model.refreshHomebrew() }.disabled(model.homebrewLoading)
                        .nativeCheckTarget("homebrew-refresh")
                }
                Text("Read-only suggestions. Brew's dependency graph cannot identify every script or service that uses a package. Review removals with Homebrew; they are permanent and have no Luma Trash Undo.")
                    .font(.caption).foregroundStyle(.secondary)
                if let inventory = model.homebrewInventory {
                    rows("Unneeded dependencies", values: inventory.unneededDependencies, empty: "Brew reports no unneeded dependencies.")
                    rows("Stale downloads and versions", values: inventory.cleanupSuggestions, empty: "Brew reports no stale downloads or versions.")
                    rows("Manual formulae and installed casks · usage unknown", values: inventory.manualPackages, empty: "No manually installed formulae or installed casks reported.")
                    Text("Cask installation intent and last-used dates are unavailable. Package and reclaimable sizes are unavailable. Cache suggestions can overlap Caches and Storage; no combined byte total is calculated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(model.homebrewStatus).font(.caption).textSelection(.enabled)
            }
        }.nativeCheckTarget("homebrew-section")
    }
    private func rows(_ title: String, values: [String]?, empty: String) -> some View {
        DisclosureGroup(title + (values.map { " (\($0.count))" } ?? " · unavailable")) {
            if let values {
                if values.isEmpty { Text(empty).font(.caption) }
                // Bounded UI; the provider's complete observation remains separate from any selection.
                ForEach(Array(values.prefix(200).enumerated()), id: \.offset) { _, value in Text(value).font(.caption).textSelection(.enabled) }
                if values.count > 200 { Text("Showing the first 200 observations. Review the full output with Homebrew.").font(.caption) }
            } else { Text("The dry-run could not be verified. Refresh to retry.").font(.caption) }
        }
    }
}
