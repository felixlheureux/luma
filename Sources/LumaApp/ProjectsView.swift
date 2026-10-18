import SwiftUI
import LumaCore

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var displayLimit = 30
    private var items: [CleanupItem] { model.projectInventory?.report.items ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Chosen projects only")
                            Text("Room for the next build.").font(.system(size: 25, weight: .semibold))
                            Text("Review Node dependencies, Rust target folders and Swift build products. Source and other data stay put.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose project folder") { model.chooseFolder(for: .projects) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                    if let root = model.projectRoot {
                        Text(root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Scan this folder again") { model.runScan(.projects) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                    Text("Nothing selected automatically. Dependencies may contain local edits. Luma never runs build or install commands.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let inventory = model.projectInventory {
                if inventory.projects.isEmpty {
                    ContentUnavailableView("No supported projects found", systemImage: "curlybraces", description: Text("Choose a folder containing package.json, Cargo.toml or Package.swift. Discovery checks up to six levels; ignored, linked and shared stores are excluded."))
                }
                ForEach(Array(inventory.projects.prefix(displayLimit))) { project in
                    Surface(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(project.url.lastPathComponent).font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }.buttonStyle(.glass)
                            }
                            Text(project.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(project.ecosystems.map(\.title).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                            if !project.items.isEmpty { ItemList(items: project.items) }
                            else { Text("No project data is available for cleanup.").font(.system(size: 12)).foregroundStyle(.secondary) }
                            DisclosureGroup("Source, configuration and other data kept") {
                                ForEach(project.entries.filter { $0.item == nil }) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.url.lastPathComponent).lineLimit(1)
                                            Spacer()
                                            Text(entry.kind.rawValue).foregroundStyle(.secondary)
                                            Text(entry.bytes.map(formatBytes) ?? "Not inspected").monospacedDigit()
                                        }
                                        Text(entry.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.padding(.vertical, 5)
                                }
                            }.font(.system(size: 11))
                        }
                    }
                }
                if inventory.projects.count > displayLimit { Button("Show more projects") { displayLimit += 30 }.buttonStyle(.glass) }
                SelectionBar(items: items)
                if !inventory.report.notices.isEmpty {
                    DisclosureGroup("Skipped locations and coverage (\(inventory.report.notices.count))") {
                        ForEach(Array(inventory.report.notices.enumerated()), id: \.offset) { _, notice in
                            Text(notice).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Label("Stop builds and package managers before cleanup. Restore moved folders through Activity; existing destinations are never overwritten.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
