import SwiftUI
import AppKit
import LumaCore

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var filter = "All items"
    @ViewState private var sort = "Size"
    @ViewState private var showHidden = false
    @ViewState private var displayLimit = 200

    private var index: StorageIndex? { model.storageIndex }
    private var current: StorageNode? { model.storageDirectory.flatMap { index?.nodes[$0] } }
    private var visible: [StorageNode] {
        guard let index, let current else { return [] }
        return index.children(of: current.id, showHidden: showHidden).filter { node in
            switch filter {
            case "Over 100 MB": node.bytes > 100_000_000
            case "Older than a year": node.modified.map { $0 < Date().addingTimeInterval(-365 * 86400) } ?? false
            case "Installers": !node.isDirectory && ["dmg", "pkg", "iso"].contains(node.url.pathExtension.lowercased())
            default: true
            }
        }.sorted {
            if sort == "Size", $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
    private var focused: StorageNode? { model.storageFocus.flatMap { index?.nodes[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StorageVolumePicker()
            if let index, let current {
                StorageVolumeSummary(scope: index.scope)
                navigation(index, current)
                HStack {
                    Picker("Show", selection: $filter) {
                        ForEach(["All items", "Over 100 MB", "Older than a year", "Installers"], id: \.self) { Text($0) }
                    }.frame(maxWidth: 220)
                    Picker("Sort", selection: $sort) { Text("Size").tag("Size"); Text("Name").tag("Name") }.frame(width: 140)
                    Toggle("Show hidden items", isOn: $showHidden)
                    Spacer()
                }.font(.system(size: 11))
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: current.url.lastPathComponent, detail: "\(current.isComplete ? "" : "At least ")\(formatBytes(current.bytes)) · \(visible.count) matching items")
                        if let issue = current.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Palette.peach) }
                        if !visible.isEmpty {
                            StorageMapView(nodes: visible, focused: model.storageFocus) { model.storageFocus = $0 }
                                .frame(height: 220).accessibilityHidden(true)
                            Text("Map shows the same filtered items as the list. Other matching items combines entries beyond the largest 12. Zero and unknown sizes appear in the list.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                if visible.isEmpty {
                    ContentUnavailableView("No matching items", systemImage: "folder", description: Text(current.issue == nil ? "This folder is empty or no items match the current filters." : "Some contents could not be inspected. Try a fresh scan or review this folder in Finder."))
                } else {
                    Surface(padding: 16) {
                        VStack(spacing: 0) {
                            ForEach(Array(visible.prefix(displayLimit))) { node in
                                row(node)
                                Divider()
                            }
                            if visible.count > displayLimit { Button("Show 200 more items") { displayLimit += 200 }.padding() }
                        }
                    }
                }
                if let focused { details(focused).id("storage-details") }
                HStack {
                    Text("\(model.selected.count) selected").font(.system(size: 12)).foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    Spacer()
                    Button("Deselect all") { model.selected = [] }.buttonStyle(StorageActionStyle()).disabled(model.selected.isEmpty)
                    PrimaryButton(title: "Review selection", symbol: "arrow.right") { model.reviewStorage() }
                        .disabled(model.selected.isEmpty || model.busy || index.scope.inspectionOnly)
                }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 16))
                Text("Logical bytes count each hard-linked file once at its first path in the scanned tree, including hidden content. Filters can hide those bytes. Skipped bytes are unknown; sizes are not promised disk savings. Packages are navigation leaves. Nothing is selected automatically.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                EmptyState(symbol: "internaldrive", title: "Follow the space.", message: "Choose a folder to explore its hierarchy. Large and old files are your data, never automatically junk.", actionTitle: "Choose a folder") { model.chooseFolder(for: .storage) }.disabled(!model.canStartScan)
            }
        }
        .onChange(of: filter) { _, _ in clearSelection() }
        .onChange(of: showHidden) { _, _ in clearSelection() }
        .onChange(of: model.storageDirectory) { _, _ in displayLimit = 200 }
    }

    private func clearSelection() { model.selected = []; model.storageFocus = nil; displayLimit = 200 }

    private func navigation(_ index: StorageIndex, _ current: StorageNode) -> some View {
        HStack {
            Button { if let parent = current.parentID { model.navigateStorage(parent) } } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(current.parentID == nil || model.busy)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(index.breadcrumbs(to: current.id)) { node in
                        Button(node.url.lastPathComponent) { model.navigateStorage(node.id) }.disabled(model.busy)
                        if node.id != current.id { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    }
                }.font(.system(size: 11))
            }
            Button("Scan again") { model.runScan(.storage) }.disabled(!model.canStartScan)
            Button("Choose another folder") { model.chooseFolder(for: .storage) }.disabled(!model.canStartScan)
        }.buttonStyle(StorageActionStyle())
    }

    private func row(_ node: StorageNode) -> some View {
        HStack(spacing: 12) {
            Toggle("Select \(node.url.lastPathComponent) for removal review", isOn: Binding(get: { model.selected.contains(node.id) }, set: {
                if $0 { model.selected.insert(node.id) } else { model.selected.remove(node.id) }
            })).toggleStyle(.checkbox).labelsHidden().disabled(index?.scope.inspectionOnly != false || !node.isComplete || model.busy || !SafetyEngine(ignoredPaths: model.ignored).permitsManualSelection(at: node.url, authorizedRoots: model.authorizedRoots))
            Button {
                if node.canNavigate { model.navigateStorage(node.id) } else { model.storageFocus = node.id }
            } label: {
                HStack {
                    Image(systemName: node.isDirectory ? (node.isPackage ? "shippingbox" : "folder") : "doc")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.url.lastPathComponent).lineLimit(1)
                        if let issue = node.issue { Text(issue).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer()
                    Text("\(node.isComplete ? "" : "At least ")\(formatBytes(node.bytes))").monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy).accessibilityLabel("\(node.url.lastPathComponent), \(node.isDirectory ? "folder" : "file"), \(node.isComplete ? "" : "partial size, at least ")\(formatBytes(node.bytes)). \(node.canNavigate ? "Open folder" : "Show details")")
            Button { model.storageFocus = node.id } label: { Image(systemName: "info.circle").frame(width: 28, height: 28) }
                .buttonStyle(StorageActionStyle()).accessibilityLabel("Show details for \(node.url.lastPathComponent)")
        }.font(.system(size: 12)).padding(12)
            .background(model.storageFocus == node.id ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contextMenu {
                if node.canNavigate { Button("Open folder") { model.navigateStorage(node.id) }.disabled(model.busy) }
                Button("Show details") { model.storageFocus = node.id }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            }
    }

    private func details(_ node: StorageNode) -> some View {
        Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(node.url.lastPathComponent).font(.headline)
                Text(node.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("Type: \(node.isPackage ? "Package" : node.isDirectory ? "Folder" : "File") · Logical size: \(node.isComplete ? "" : "at least ")\(formatBytes(node.bytes))")
                if let modified = node.modified { Text("Modified: \(modified.formatted())") }
                if let created = node.created { Text("Created: \(created.formatted())") }
                Text("Coverage: \(node.issue ?? "Complete within this scan’s local filesystem scope")")
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.url.path, forType: .string) }
                    if node.canNavigate { Button("Open folder") { model.navigateStorage(node.id) }.disabled(model.busy) }
                }.buttonStyle(StorageActionStyle())
            }.font(.system(size: 11))
        }
    }
}

private struct StorageMapView: View {
    let nodes: [StorageNode]
    let focused: String?
    let focus: (String) -> Void
    private static let colors: [Color] = [Palette.accent, Palette.blue, Palette.mint, Palette.peach]
    private var entries: [StorageMapEntry] { StorageMapEntry.entries(for: nodes) }
    var body: some View {
        GeometryReader { geometry in
            let values = entries
            let boxes = layout(values.map { Double($0.bytes) }, rect: CGRect(origin: .zero, size: geometry.size))
            ForEach(Array(values.enumerated()), id: \.element.id) { i, entry in
                let box = boxes[i]
                Button { if !entry.isRemainder { focus(entry.id) } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if box.width > 70 && box.height > 40 {
                            Text(entry.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                            Text(formatBytes(entry.bytes)).font(.system(size: 10))
                        }
                    }.padding(10).frame(width: max(0, box.width - 3), height: max(0, box.height - 3), alignment: .topLeading)
                        .background((entry.isRemainder ? Color.gray : Self.colors[i % Self.colors.count]).gradient, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: focused == entry.id ? 3 : 0))
                        .foregroundStyle(.white).clipped()
                }.buttonStyle(.plain).offset(x: box.minX, y: box.minY)
                    .help("\(entry.name) · \(formatBytes(entry.bytes))\(entry.isRemainder ? " · Combined entries in the list" : " · Show details")")
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

private struct StorageActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background((scheme == .dark ? Color.white : Color.black).opacity(configuration.isPressed ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.4)
    }
}
