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
                } else { Surface(padding: 18) { ItemList(items: visible) } }
                SelectionBar(items: visible)
                Label("Close the owning app before cleaning. Caches may improve performance and will grow back naturally.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func filterButton(_ title: String, category: ItemCategory?) -> some View {
        Button { filter = category } label: { Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8).background(filter == category ? Palette.accent : .clear, in: Capsule()).foregroundStyle(filter == category ? Color.white : .secondary) }.buttonStyle(.plain)
    }
}

extension ItemCategory: Identifiable { public var id: String { rawValue } }

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var mode = "All items"
    private var visible: [CleanupItem] {
        model.storage.filter { item in
            switch mode {
            case "Over 100 MB": item.bytes > 100_000_000
            case "Older than a year": item.identity.modified < Calendar.current.date(byAdding: .year, value: -1, to: Date())!
            case "Installers": ["dmg", "pkg", "iso"].contains(item.url.pathExtension.lowercased())
            default: true
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.completedScans.contains(.storage) {
                EmptyState(symbol: "internaldrive", title: "Follow the space.", message: "Choose a folder to see what’s inside, sized and sorted. Large files and old downloads are your data, and are never treated as junk.", actionTitle: "Choose a folder") { model.chooseFolder(for: .storage) }.disabled(!model.canStartScan)
            } else {
                HStack {
                    Label(model.snapshot(for: .storage)?.request.root?.path ?? "Selected folder", systemImage: "folder").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose another folder") { model.chooseFolder(for: .storage) }.buttonStyle(.glass).disabled(!model.canStartScan)
                }
                if !model.storage.isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(title: "Largest \(min(12, model.storage.count)) items", detail: "\(formatBytes(model.storage.reduce(0) { $0 + $1.bytes })) in scanned items")
                            TreemapView(items: Array(model.storage.prefix(12)))
                                .frame(height: 230)
                            HStack(spacing: 14) {
                                ForEach(Array(model.storage.prefix(4).enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 5) { Circle().fill(TreemapView.colors[index % TreemapView.colors.count]).frame(width: 6, height: 6); Text(item.name).lineLimit(1) }.font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Picker("Show", selection: $mode) { ForEach(["All items", "Over 100 MB", "Older than a year", "Installers"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(maxWidth: 450)
                    Spacer()
                    Text("\(visible.count) items").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Surface(padding: 18) {
                    if visible.isEmpty { Text("No files match this filter.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20) }
                    else { ItemList(items: visible) }
                }
                SelectionBar(items: visible)
                Text("Sizes are logical bytes, not guaranteed reclaimed disk space. APFS clones, compression, and snapshots can affect actual savings.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct TreemapView: View {
    let items: [CleanupItem]
    static let colors: [Color] = [Palette.accent, Palette.blue, Palette.mint, Color(red: 0.65, green: 0.54, blue: 0.79), Palette.peach]
    var body: some View {
        GeometryReader { geometry in
            let boxes = layout(items.map { Double($0.bytes) }, rect: CGRect(origin: .zero, size: geometry.size))
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let box = boxes[index]
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        if box.width > 80 && box.height > 45 {
                            Text(item.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                            Text(formatBytes(item.bytes)).font(.system(size: 10)).opacity(0.75)
                        }
                    }.padding(12).frame(width: max(0, box.width - 3), height: max(0, box.height - 3), alignment: .topLeading)
                        .background(Self.colors[index % Self.colors.count].gradient, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
                        .clipped()
                }.buttonStyle(.plain).offset(x: box.minX, y: box.minY).help("\(item.name) · \(formatBytes(item.bytes)) · Reveal in Finder")
            }
        }
    }

    // Balanced recursive partition: deterministic, native, and proportional to size.
    private func layout(_ weights: [Double], rect: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        guard weights.count > 1 else { return [rect] }
        let total = weights.reduce(0, +)
        guard total > 0 else { return Array(repeating: .zero, count: weights.count) }
        var split = 1; var subtotal = weights[0]
        while split < weights.count - 1 && subtotal + weights[split] / 2 < total / 2 { subtotal += weights[split]; split += 1 }
        let ratio = subtotal / total
        if rect.width >= rect.height {
            let width = rect.width * ratio
            return layout(Array(weights[..<split]), rect: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)) + layout(Array(weights[split...]), rect: CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height))
        }
        let height = rect.height * ratio
        return layout(Array(weights[..<split]), rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)) + layout(Array(weights[split...]), rect: CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height))
    }
}

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var displayLimit = 100
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
                            Text("Potential savings if you keep one copy per group.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose another folder") { model.chooseFolder(for: .duplicates) }.buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                }
                if model.duplicates.isEmpty {
                    ContentUnavailableView("No exact duplicates found", systemImage: "checkmark.square", description: Text("Packages, hidden files, cloud items, and hard-linked copies are excluded."))
                }
                ForEach(Array(model.duplicates.prefix(displayLimit))) { group in
                    Surface(padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(group.items.count) identical copies").font(.system(size: 13, weight: .semibold))
                                Spacer(); StatusPill(text: "SHA-256 verified", tint: Palette.mint)
                            }
                            ItemList(items: group.items)
                            if group.items.allSatisfy({ model.selected.contains($0.id) }) {
                                Label("Keep at least one copy in this group.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.peach)
                            }
                        }
                    }
                }
                if model.duplicates.count > displayLimit { Button("Show 100 more groups") { displayLimit += 100 }.buttonStyle(.glass) }
                SelectionBar(items: model.duplicates.flatMap(\.items))
                    .disabled(model.duplicates.contains { $0.items.allSatisfy { model.selected.contains($0.id) } })
                Text("Files are revalidated before moving. Packages, links, cloud placeholders, hidden files and external volumes are excluded.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
