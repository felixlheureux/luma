import SwiftUI
import LumaCore

struct MaintenanceEntryView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var approveCaches = false
    @ViewState private var approveTrash = false
    @ViewState private var approvedCaches: [CleanupItem] = []
    @ViewState private var approvedTrash: TrashReview?
    private var items: [CleanupItem] { model.cleanup.filter { !model.isIgnored($0) } }
    private var selected: [CleanupItem] { items.filter { model.selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Local Trash").font(.headline)
                        Spacer()
                        Button("Refresh") { model.refreshMaintenanceTrash() }.disabled(model.maintenanceTrashLoading || model.operationBusy)
                        Button("Open Trash") { model.openLocalTrash() }
                    }
                    Text("Current user's local home Trash only. External-volume and provider bins are excluded.").font(.caption).foregroundStyle(.secondary)
                    if let review = model.maintenanceTrash {
                        Text("\(review.count) supported top-level items · \(formatBytes(review.bytes)) · \(review.excluded) excluded")
                        Text(review.root.path).font(.caption).textSelection(.enabled)
                        Text("Empty Trash permanently removes the reviewed contents. This cannot be undone. New or changed items are preserved.").font(.caption)
                        Button("Empty reviewed Trash…", role: .destructive) { approvedTrash = review; approveTrash = true }
                            .disabled(review.count == 0 || model.mutationUnavailableReason != nil || model.maintenanceTrashLoading)
                            .nativeCheckTarget("maintenance-trash")
                    }
                    Text(model.maintenanceTrashStatus).font(.caption).textSelection(.enabled).frame(height: 54, alignment: .topLeading)
                    if let reason = model.mutationUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    Button("Stop after current entry") { model.cleanupSession.stop() }.disabled(!model.maintenanceEmptying)
                    ForEach(Array(model.maintenanceHistory.suffix(3).reversed())) { session in
                        DisclosureGroup(session.date.formatted() + " · " + session.summary) {
                            ForEach(Array(session.outcomes.enumerated()), id: \.offset) { _, outcome in
                                VStack(alignment: .leading) {
                                    Text(outcome.path.path).textSelection(.enabled)
                                    Text(outcome.state + " · " + outcome.detail)
                                }.font(.caption)
                            }
                        }.font(.caption)
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory").font(.headline)
                    Text(model.system.sampledAt == nil ? "Collecting memory readings…" : model.system.memoryAvailable ? "\(formatMemory(model.system.usedMemory)) used · \(model.system.pressure) pressure" : "Memory reading unavailable")
                    if let date = model.system.sampledAt, Date().timeIntervalSince(date) > 10 {
                        Text("Stale observation · " + date.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(model.system.memoryAvailable && ["normal", "low"].contains(model.system.pressure.lowercased()) ? "No action is needed. macOS reclaims reusable cached files when apps need memory." : "Review resource consumers and quit only applications you no longer need. A normal Quit may ask you to save documents.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Observe pressure after an app exits. A quit request does not guarantee freed RAM.").font(.caption)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Caches and generated data").font(.headline)
                        Spacer()
                        Button(model.scanSessions.isBusy && model.scanTarget == .generatedData ? "Checking…" : "Refresh caches") { model.runScan(.maintenance) }
                            .disabled(!model.canStartScan || (model.scanSessions.isBusy && model.scanTarget == .generatedData))
                    }
                    Text("Supported user caches, logs and developer units. Close owning apps/tools before cleanup; regenerated caches may temporarily slow their next launch.").font(.caption).foregroundStyle(.secondary)
                    Text("\(items.count) actionable locations · \(formatBytes(model.generatedBytes(items))) · \(model.cleanup.count - items.count) ignored")
                    if let report = model.cleanupReport { ScanSummaryCard(report: report) }
                    if items.isEmpty {
                        Text(model.cleanup.isEmpty ? (model.cleanupReport == nil ? "Check supported locations to choose what to remove." : "No supported generated data found. Coverage shows empty, missing and unreadable locations.") : "All observed locations are ignored. Change your ignore choices in Settings to include them.").font(.caption)
                    } else { GeneratedDataGroupsView(items: items) }
                    HStack {
                        Text("\(selected.count) selected · \(formatBytes(model.generatedBytes(selected)))").font(.caption)
                        Spacer()
                        Button("Move selected to Trash…") { approvedCaches = selected; approveCaches = true }
                            .disabled(selected.isEmpty || model.mutationUnavailableReason != nil || (model.scanSessions.isBusy && model.scanTarget == .generatedData))
                            .nativeCheckTarget("maintenance-cache")
                    }
                    Text((model.scanSessions.isBusy && model.scanTarget == .generatedData ? model.scanSessions.statusText + ". " : "") + model.maintenanceCacheStatus).font(.caption).textSelection(.enabled).frame(height: 54, alignment: .topLeading)
                    Button("Stop after current item") { model.cleanupSession.stop() }.disabled(!model.maintenanceCleaning)
                }
            }
            ProcessList()
        }
        .task { if !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) { model.refreshMaintenanceTrash(); if model.cleanupReport == nil { model.runScan(.maintenance) } } }
        .alert("Move selected generated data to Trash?", isPresented: $approveCaches) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { model.trashMaintenanceCaches(approvedCaches) }
        } message: { Text("\(approvedCaches.count) locations · \(formatBytes(model.generatedBytes(approvedCaches))). Caches and generated files must be recreated by their owning apps. Restore is available in Activity while the contents remain unchanged in Trash.") }
        .alert("Permanently empty reviewed Trash?", isPresented: $approveTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Permanently remove", role: .destructive) { if let approvedTrash { model.emptyMaintenanceTrash(approvedTrash) } }
        } message: { Text("\(approvedTrash?.count ?? 0) supported items in your local home Trash. Permanent deletion cannot be undone. Excluded bins and changed contents remain.") }
    }
}
