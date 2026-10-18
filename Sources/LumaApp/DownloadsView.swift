import SwiftUI
import LumaCore

enum DownloadsTab: String, CaseIterable { case files = "Files", duplicates = "Exact duplicates" }

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var kind: DownloadKind?
    @ViewState private var age = DownloadAge.any
    @ViewState private var minimumBytes: Int64 = 0
    @ViewState private var displayLimit = 100
    private var inventory: DownloadsInventory? { model.downloadsInventory }
    private var visible: [DownloadFile] {
        (inventory?.files(matching: .init(kind: kind, minimumBytes: minimumBytes, age: age)) ?? [])
            .filter { file in !model.ignored.contains { Filesystem.isWithin(file.url, root: URL(fileURLWithPath: $0)) } }
            .sorted { ($0.bytes ?? -1) == ($1.bytes ?? -1) ? $0.id < $1.id : ($0.bytes ?? -1) > ($1.bytes ?? -1) }
    }
    private var groups: [DuplicateGroup] { inventory?.duplicates ?? [] }
    private var selectable: [CleanupItem] { model.downloadsTab == .files ? visible.compactMap(\.item) : groups.flatMap(\.items) }
    private var keepOneViolated: Bool { groups.contains { $0.items.allSatisfy { model.selected.contains($0.id) } } }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Eyebrow(text: "Your local files")
                            Text("Keep the downloads you need.").font(.system(size: 25, weight: .semibold))
                            Text("Type, size, age and recorded sources help you review. They never make a file junk.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Downloads folder") { model.chooseFolder(for: .downloads) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                    if let root = model.downloadsRoot {
                        Text(root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Scan this folder again") { model.runScan(.downloads) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                    Text("Actual local files only. Chrome, Safari and Slack download-history records are not read. Installer caches stay in Clean.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let inventory {
                Surface(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(inventory.files.count) observed entries · known logical size \(formatBytes(inventory.bytes()))").font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 12) {
                            ForEach(DownloadKind.allCases, id: \.self) { type in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(formatBytes(inventory.bytes(kind: type))).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                }
                            }
                        }
                        Text("Type totals partition this snapshot. Size, age and duplicate views overlap; do not add them. Excluded sizes are unknown. Space is reclaimed only after emptying Trash in Finder.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Picker("Review", selection: $model.downloadsTab) { ForEach(DownloadsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 350)
                if model.downloadsTab == .files {
                    HStack {
                        Picker("Type", selection: $kind) {
                            Text("All types").tag(DownloadKind?.none)
                            ForEach(DownloadKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }.frame(maxWidth: 235)
                        Picker("Size", selection: $minimumBytes) {
                            Text("Any size").tag(Int64(0)); Text("At least 100 MB").tag(Int64(100_000_000)); Text("At least 1 GB").tag(Int64(1_000_000_000))
                        }.frame(width: 170)
                        Picker("Modified", selection: $age) { ForEach(DownloadAge.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 230)
                    }.font(.system(size: 11))
                    Text("\(visible.count) matching entries. Age uses modification time, not download time. Filter changes clear the selection.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if visible.isEmpty {
                        ContentUnavailableView("No matching local files", systemImage: "tray", description: Text("Try another filter or inspect the scan exclusions. Nothing is selected automatically."))
                    }
                    Surface(padding: 18) {
                        ForEach(Array(visible.prefix(displayLimit))) { file in
                            VStack(alignment: .leading, spacing: 8) {
                                if let item = file.item { ItemList(items: [item]) }
                                else {
                                    HStack { Text(file.url.lastPathComponent).fontWeight(.medium); Spacer(); Text(file.bytes.map(formatBytes) ?? "Unknown size") }
                                        .font(.system(size: 12))
                                }
                                HStack {
                                    Text(file.kind.rawValue)
                                    if let date = file.modified { Text("Modified \(date.formatted(date: .abbreviated, time: .omitted))") }
                                    Spacer()
                                    Button("Details & preview") { model.previewDownload(file) }.buttonStyle(.glass).disabled(model.busy)
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                                if let issue = file.issue { Text(issue).font(.system(size: 11)).foregroundStyle(.secondary) }
                                if model.downloadFocus == file.id { details(file).id("downloads-details") }
                                Divider().padding(.vertical, 7)
                            }
                        }
                        if visible.count > displayLimit { Button("Show 100 more files") { displayLimit += 100 }.buttonStyle(.glass) }
                    }
                } else {
                    DuplicateGroupsView(groups: groups, source: .downloads)
                }
                SelectionBar(items: selectable).disabled(keepOneViolated)
                if keepOneViolated { Label("Keep at least one independent copy in every duplicate group.", systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.peach) }
                Text("Nothing selected by default. Partial-download names, packages, hidden files, links, shared files and provider-managed contents remain excluded. Selection is rechecked before Trash; Restore is available in Activity.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.downloadsTab) { _, _ in clearSelection() }
        .onDisappear { model.clearDownloadPreview() }
        .onChange(of: kind) { _, _ in clearSelection() }
        .onChange(of: age) { _, _ in clearSelection() }
        .onChange(of: minimumBytes) { _, _ in clearSelection() }
    }
    private func clearSelection() { model.selected = []; model.clearDownloadPreview(); displayLimit = 100 }
    private func details(_ file: DownloadFile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(file.url.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            if let created = file.created { Text("Created: \(created.formatted())") }
            if let modified = file.modified { Text("Modified: \(modified.formatted())") }
            Text("Recorded source metadata (unverified)").fontWeight(.medium)
            if file.sources.isEmpty { Text("Unknown. No source metadata is available.").foregroundStyle(.secondary) }
            ForEach(Array(file.sources.enumerated()), id: \.offset) { _, source in Text(verbatim: source).textSelection(.enabled) }
            Text("A recorded URL is not proof of safety or a promise that a file can be downloaded again.").foregroundStyle(.secondary)
            if let preview = model.downloadPreview {
                switch preview {
                case .text(let text, let truncated):
                    ScrollView(.vertical) { Text(verbatim: text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 180)
                    if truncated { Text("Text preview is limited to the first 64 KiB.").foregroundStyle(.secondary) }
                case .png(let data):
                    if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                case .unavailable(let reason): Text(reason).foregroundStyle(.secondary)
                }
            } else { ProgressView().controlSize(.small) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.glass)
        }.font(.system(size: 11)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}
