import SwiftUI
import LumaCore

struct CleanView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var filter: ItemCategory?
    private var visible: [CleanupItem] { model.cleanup.filter { (filter == nil || $0.category == filter) && !model.isIgnored($0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.journalError != nil || !model.recoveryNotices.isEmpty {
                Surface(padding: 16) {
                    HStack {
                        Label("Review Activity before starting another cleanup.", systemImage: "info.circle").font(.system(size: 12))
                        Spacer()
                        Button("Open Activity") { model.destination = .history }.buttonStyle(.glass)
                    }
                }
            }
            if !model.completedScans.contains(.clean) {
                if !model.scanSessions.isBusy || (model.scanTarget != .generatedData && model.scanTarget != .overview) {
                    EmptyState(symbol: "sparkles", title: "Make a little room.", message: "Check browser caches, package downloads, developer files, and simulator diagnostics. Every location and removal consequence is explained.", actionTitle: model.scanSessions.isBusy ? "Queue new check" : "Scan generated data") { model.runScan(.clean) }.disabled(!model.canStartScan)
                }
            } else {
                if let report = model.cleanupReport { ScanSummaryCard(report: report) }
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 9) {
                            Eyebrow(text: "Potentially reclaimable")
                            Text(formatBytes(model.cleanupBytes)).font(.system(size: 40, weight: .semibold)).tracking(-1.4)
                            Text("Caches, diagnostics, and generated files. Review the trade-offs first.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(); SymbolTile(symbol: "sparkles", size: 65)
                    }
                }
                HStack(spacing: 8) {
                    filterButton("All", category: nil)
                    ForEach([ItemCategory.caches, .developer, .logs]) { category in filterButton(category.rawValue, category: category) }
                    Spacer()
                    Text("Nothing selected by default").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if visible.isEmpty {
                    ContentUnavailableView("No matching data", systemImage: "checkmark.circle", description: Text("No supported generated data was found in this category. See scan coverage for skipped items."))
                } else { GeneratedDataGroupsView(items: visible) }
                SelectionBar(items: visible, logicalBytes: model.generatedBytes)
                Label("Close the owning app before cleaning. Caches may improve performance and will grow back naturally.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func filterButton(_ title: String, category: ItemCategory?) -> some View {
        Button { filter = category } label: { Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8).background(filter == category ? Palette.accent : .clear, in: Capsule()).foregroundStyle(filter == category ? Color.white : .secondary) }.buttonStyle(.plain)
    }
}

extension ItemCategory: Identifiable { public var id: String { rawValue } }

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.completedScans.contains(.duplicates) {
                EmptyState(symbol: "square.on.square", title: "Same content. Clear choices.", message: "Choose a folder. Luma groups by size, checks partial hashes, then verifies full SHA-256 content. Nothing is selected automatically.", actionTitle: "Find exact duplicates") { model.chooseFolder(for: .duplicates) }.disabled(!model.canStartScan)
            } else {
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "\(model.duplicates.count) verified groups")
                            Text(formatBytes(model.duplicates.reduce(0) { $0 + $1.recoverable })).font(.system(size: 36, weight: .semibold))
                            Text("Potential logical savings if one independent copy stays per group.").font(.system(size: 12)).foregroundStyle(.secondary)
                            if let root = model.duplicateRoot { Text(root.path).font(.caption).textSelection(.enabled) }
                        }
                        Spacer()
                        Button("Scan again") { model.runScan(.duplicates) }.buttonStyle(.glass).disabled(!model.canStartScan)
                        Button("Choose folder") { model.chooseFolder(for: .duplicates) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                }
                DuplicateGroupsView(groups: model.duplicates, source: .duplicates)
                SelectionBar(items: model.duplicates.flatMap(\.items))
                    .disabled(model.duplicates.contains { $0.items.allSatisfy { model.selected.contains($0.id) } })
                Text("Files are checked again before Trash. Hard links count once. Packages, provider-managed files, hidden files and other volumes are excluded. Space is reclaimed after emptying Trash in Finder.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
