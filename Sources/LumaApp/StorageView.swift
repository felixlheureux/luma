import SwiftUI
import AppKit
import LumaCore

struct StorageView: View {
    @Environment(AppModel.self) private var model
    private var filter: String { model.storageFilter }
    @ViewState private var sort = "Size"
    private var showHidden: Bool { model.storageShowHidden }
    @ViewState private var displayLimit = 200
    @ViewState private var showOther = false
    @FocusState private var keyboardRow: String?
    @ViewState private var pinnedOrder: [String] = []
    @ViewState private var pointerInList = false
    private var index: StorageIndex? { model.storageIndex }
    private var current: StorageNode? { model.storageDirectory.flatMap { index?.nodes[$0] } }
    @ViewState private var visible: [StorageNode] = []
    @ViewState private var mapEntries: [StorageMapEntry] = []
    private struct ListingKey: Equatable {
        let revision: UInt64
        let query: StorageListingQuery
    }
    private var listingKey: ListingKey {
        ListingKey(revision: model.storageRevision, query: StorageListingQuery(
            largestFiles: model.storageMode == "Largest files", directory: model.storageDirectory,
            filter: filter, showHidden: showHidden, search: model.storageSearch,
            location: model.storageLocation, sort: sort,
            selection: filter == "Selected" ? model.storageSelection : [],
            pinnedOrder: pointerInList || keyboardRow != nil ? pinnedOrder : []))
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Browse", selection: $model.storageMode) {
                    Text("Largest files").tag("Largest files"); Text("Explore").tag("Explore")
                }.pickerStyle(.segmented).frame(maxWidth: 280)
                Spacer()
                if model.storageDiscovery.isBusy { Button("Stop discovery") { model.storageDiscovery.cancel() } }
                else { Button(index == nil ? "Scan accessible Mac" : "Scan again") { model.ensureStorage(refresh: true) }.disabled(model.operationBusy || model.storageLoading) }
                Menu {
                    Button("Scan accessible Mac storage") { model.ensureStorage(refresh: true) }
                    Button("Custom location…") { model.chooseFolder(for: .storage) }
                    Button("Compare exact duplicates…") { model.chooseFolder(for: .duplicates) }
                    ForEach(model.storageVolumes.volumes) { volume in
                        Button(volume.name) { model.startScan(.init(.storage, root: URL(fileURLWithPath: volume.identity.mountPath), storageVolumeIdentity: volume.identity)) }
                    }
                } label: { Label("Locations", systemImage: "externaldrive") }.disabled(model.operationBusy || model.storageLoading)
            }
            Text(model.storageStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(model.storageStatus).frame(height: 20, alignment: .leading)
            if let index {
                if !index.isDiscovery { Text("Published location: \(index.scope.root.path) · \(index.scope.inspectionOnly ? "Inspection only" : "Local files")").font(.caption).textSelection(.enabled) }
                controls(index)
                if index.isDiscovery {
                    Text("iCloud metadata is partial and read-only. Online-only files are never downloaded; cloud logical sizes are excluded from local totals. Missing metadata may mean offline, signed out or unavailable access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.storageMode == "Explore", let current {
                    navigation(index, current)
                    Text("\(current.url.isFileURL ? current.url.path : "Accessible Mac storage") · \(formatBytes(current.bytes)) observed unique logical bytes").font(.caption).textSelection(.enabled)
                    if visible.isEmpty {
                        list.frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                StorageBubbleMap(entries: mapEntries, focused: model.storageFocus, focus: { model.storageFocus = $0 }, activate: activate)
                                    .frame(width: 310, height: 330)
                                list.frame(width: 380)
                            }
                            VStack(alignment: .leading) {
                                list
                                DisclosureGroup("Space map") {
                                    StorageBubbleMap(entries: mapEntries, focused: model.storageFocus, focus: { model.storageFocus = $0 }, activate: activate).frame(height: 260)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .center)
                    }
                } else { list.frame(maxWidth: .infinity, alignment: .center) }
                if let issue = current?.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Coverage and size accounting") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("File rows show per-path logical size. Folder and selected totals count hard-linked file objects once; linked names may appear in different folders. Allocated space and guaranteed APFS savings are not measured. Unknown/skipped contents are absent from totals. Packages and other users’ private data are not traversed by automatic discovery.")
                        Text("Automatic discovery is bounded and prioritizes common personal folders. Remaining contents have unknown size.")
                        Button("Continue bounded discovery") { model.storageLimit = min(200_000, model.storageLimit * 2); model.ensureStorage(refresh: true) }.disabled(model.storageLimit >= 200_000 || model.storageDiscovery.isBusy || model.operationBusy)
                        ForEach(index.scopes, id: \.root.path) { scope in Text(scope.root.path) }
                        Text("Reported volume capacity: \(index.scope.volume.capacity.map(formatBytes) ?? "Unavailable") · Filesystem free: \(index.scope.volume.free.map(formatBytes) ?? "Unavailable")")
                        Text("Available for important usage: \(index.scope.volume.availableForImportantUsage.map(formatBytes) ?? "Unavailable"). This is a system estimate, separate from observed file bytes; APFS volumes may share capacity.")
                        Text("If locations are inaccessible, grant Full Disk Access to Luma in System Settings, then Refresh. Readable locations remain available.")
                        Button("Full Disk Access Settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) } }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(model.storageDiscovery.isBusy ? "Discovering local storage" : "Explore your storage", systemImage: "internaldrive",
                    description: Text(model.storageDiscovery.isBusy ? "Readable locations appear as they are discovered. You can keep using Luma while the scan runs." : "Start a scan of accessible Mac storage, or choose a folder from Locations. Nothing is scanned until you ask."))
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
            }
        }
        .task {
            model.storageVolumes.refresh()
            model.loadSavedStorage()
        }
        .task(id: listingKey) {
            let captured = index, query = listingKey.query
            let worker = Task.detached(priority: .userInitiated) {
                let rows = try captured?.listing(query) ?? []
                return (rows: rows, map: query.largestFiles ? [] : StorageMapEntry.entries(for: rows))
            }
            let result = await withTaskCancellationHandler {
                try? await worker.value
            } onCancel: { worker.cancel() }
            if !Task.isCancelled, let result { visible = result.rows; mapEntries = result.map }
        }
        .onChange(of: filter) { _, _ in displayLimit = 200; pinnedOrder = [] }
        .onChange(of: keyboardRow) { _, id in
            if let id { model.storageFocus = id; if pinnedOrder.isEmpty { pinnedOrder = visible.map(\.id) } }
        }
        .onChange(of: model.storageDirectory) { _, _ in displayLimit = 200; pinnedOrder = [] }
    }

    private func controls(_ index: StorageIndex) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Search discovered paths", text: $model.storageSearch).textFieldStyle(.roundedBorder)
            ViewThatFits(in: .horizontal) {
                HStack { filters(index); Toggle("Hidden", isOn: Binding(get: { model.storageShowHidden }, set: { model.storageShowHidden = $0 })) }
                VStack(alignment: .leading) { filters(index); Toggle("Hidden", isOn: Binding(get: { model.storageShowHidden }, set: { model.storageShowHidden = $0 })) }
            }
        }.font(.caption)
    }
    private func filters(_ index: StorageIndex) -> some View {
        @Bindable var model = model
        return HStack {
            Picker("Show", selection: Binding(get: { model.storageFilter }, set: { model.storageFilter = $0 })) { ForEach(["All items", "Selected", "Over 100 MB", "Older than a year", "Installers"], id: \.self) { Text($0) } }
            Picker("Sort", selection: $sort) { ForEach(["Size", "Name", "Modified"], id: \.self) { Text($0) } }
            Picker("Location", selection: $model.storageLocation) {
                Text("All locations").tag("All locations")
                ForEach(index.scopes, id: \.root.path) { Text($0.root.path).tag($0.root.path) }
                ForEach(["Downloads", "Documents", "Desktop", "Projects"], id: \.self) { name in Text(name).tag(model.uninstallHome.appendingPathComponent(name).path) }
            }
        }
    }
    private var list: some View {
        Surface(padding: 12) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if visible.isEmpty {
                    ContentUnavailableView("No matching results", systemImage: "magnifyingglass",
                        description: Text("Try different filters. Some locations may still be unindexed or unavailable."))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                }
                ForEach(Array(visible.prefix(model.storageMode == "Explore" ? 12 : displayLimit))) { node in row(node); Divider() }
                if model.storageMode == "Explore", visible.count > 12 {
                    DisclosureGroup("Other items (\(visible.count - 12))", isExpanded: $showOther) {
                        ForEach(Array(visible.dropFirst(12).prefix(max(0, displayLimit - 12)))) { node in row(node); Divider() }
                    }.padding(.vertical, 8)
                }
                if visible.count > displayLimit { Button("Other items · show 200 more") { displayLimit += 200 }.padding() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .center).onHover { inside in
            if inside { pinnedOrder = visible.map(\.id) }
            pointerInList = inside
        }
    }
    private func navigation(_ index: StorageIndex, _ current: StorageNode) -> some View {
        HStack {
            Button { model.storageHistory(back: true) } label: { Image(systemName: "chevron.left") }.disabled(model.storageBack.isEmpty).help("Back")
            Button { model.storageHistory(back: false) } label: { Image(systemName: "chevron.right") }.disabled(model.storageForward.isEmpty).help("Forward")
            Button { if let id = current.parentID { model.navigateStorage(id) } } label: { Image(systemName: "arrow.up") }.disabled(current.parentID == nil).help("Up")
            ScrollView(.horizontal) {
                HStack {
                    ForEach(index.breadcrumbs(to: current.id)) { node in
                        Button(node.url.isFileURL ? node.url.lastPathComponent : "Mac") { model.navigateStorage(node.id) }
                        if node.id != current.id { Image(systemName: "chevron.right") }
                    }
                }.font(.caption)
            }
        }.buttonStyle(.borderless)
    }
    private func activate(_ id: String) {
        if id == "storage-remainder" { showOther = true; return }
        if index?.nodes[id]?.canNavigate == true { model.navigateStorage(id) }
        else { model.storageFocus = id }
    }
    private func row(_ node: StorageNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("Select \(node.url.lastPathComponent)", isOn: Binding(get: { model.storageSelection.contains(node.id) }, set: { model.selectStorage(node, selected: $0) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(!model.storageSelection.contains(node.id) && (!model.storageEligible(node) || model.storageMoving))
                Button { model.storageFocus = node.id } label: {
                    HStack {
                        Image(systemName: node.isDirectory ? "folder" : "doc")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.id == "luma://icloud-metadata" ? "iCloud metadata" : node.url.lastPathComponent).lineLimit(1)
                            Text(node.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            if let date = node.modified { Text(date, style: .date).font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(node.cloud.map { $0.logicalBytes.map { formatBytes($0) + " logical" } ?? "Logical size unknown" } ?? (node.issue != nil && node.bytes == 0 ? "Unknown" : "\(node.issue == nil ? "" : "≥ ")\(formatBytes(node.bytes))")).monospacedDigit()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).focused($keyboardRow, equals: node.id)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { activate(node.id) })
                    .onKeyPress(.return) { activate(node.id); return .handled }
                    .onHover { if $0 { model.storageFocus = node.id } }
                if node.canNavigate { Button { model.navigateStorage(node.id) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).help("Open folder") }
            }
            if let cloud = node.cloud {
                HStack {
                    Text(cloud.state == .local ? "Downloaded" : cloud.state == .onlineOnly ? "Online-only" : "Cloud state unknown")
                    Text(cloud.allocatedBytes.map { formatBytes($0) + " locally allocated" } ?? "Local allocation unknown")
                    Spacer()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                }.font(.caption).foregroundStyle(.secondary)
                Text("\(Date().timeIntervalSince(cloud.observedAt) >= 1800 ? "Stale · " : "")\(cloud.source == .index ? "Provisional index" : "Filesystem metadata") · \(cloud.observedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.url.path).textSelection(.enabled)
                    Text(node.issue ?? "Complete local observation. Personal data is never automatically junk.")
                    if !model.storageEligible(node) { Text("Read-only, incomplete, protected or ignored location.") }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                }.font(.caption).foregroundStyle(.secondary)
            }.font(.system(size: 10))
        }.font(.system(size: 12)).padding(10)
            .background(model.storageFocus == node.id ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StorageBubbleMap: View {
    let entries: [StorageMapEntry]
    let focused: String?
    let focus: (String) -> Void
    let activate: (String) -> Void
    @FocusState private var keyboardBubble: String?
    private let colors: [Color] = [Palette.accent, Palette.blue, Palette.mint, Palette.peach]
    var body: some View {
        GeometryReader { geometry in
            let values = entries
            let boxes = partition(values.map { Double($0.bytes) }, CGRect(origin: .zero, size: geometry.size))
            let scale: CGFloat = bubbleScale(values, boxes)
            ForEach(Array(values.enumerated()), id: \.element.id) { i, entry in
                let diameter: CGFloat = 2 * CGFloat(sqrt(Double(entry.bytes))) * scale
                Button { activate(entry.id) } label: {
                    Circle().fill((entry.isRemainder ? Color.gray : colors[i % colors.count]).gradient)
                        .overlay(Circle().strokeBorder(.primary.opacity(focused == entry.id ? 0.9 : 0), lineWidth: 3))
                        .overlay { if diameter > 70 { VStack { Text(entry.name).lineLimit(2); Text(formatBytes(entry.bytes)) }.font(.system(size: 10)).foregroundStyle(.white).padding(8) } }
                        .frame(width: diameter, height: diameter)
                }.buttonStyle(.plain).focused($keyboardBubble, equals: entry.id).position(x: boxes[i].midX, y: boxes[i].midY)
                    .onHover { if $0 { focus(entry.id) } }
                    .accessibilityLabel("\(entry.name), \(formatBytes(entry.bytes))")
                    .help("\(entry.name) · \(formatBytes(entry.bytes)) · \(entry.isRemainder ? "Other items remain in the list" : "Open folder or focus file")")
            }
        }.onChange(of: keyboardBubble) { _, id in if let id { focus(id) } }
    }
    private func bubbleScale(_ values: [StorageMapEntry], _ boxes: [CGRect]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.indices.reduce(CGFloat.greatestFiniteMagnitude) { result, i in
            Swift.min(result, Swift.min(boxes[i].width, boxes[i].height) / Swift.max(1, 2 * CGFloat(sqrt(Double(values[i].bytes)))))
        }
    }
    private func partition(_ weights: [Double], _ rect: CGRect) -> [CGRect] {
        guard weights.count > 1 else { return weights.isEmpty ? [] : [rect] }
        let total = weights.reduce(0, +)
        var split = 1, sum = weights[0]
        while split < weights.count - 1 && sum + weights[split] / 2 < total / 2 { sum += weights[split]; split += 1 }
        let ratio = sum / max(1, total)
        let horizontal = rect.width >= rect.height
        let first = CGRect(x: rect.minX, y: rect.minY, width: horizontal ? rect.width * ratio : rect.width, height: horizontal ? rect.height : rect.height * ratio)
        let second = CGRect(x: horizontal ? first.maxX : rect.minX, y: horizontal ? rect.minY : first.maxY, width: horizontal ? rect.width - first.width : rect.width, height: horizontal ? rect.height : rect.height - first.height)
        return partition(Array(weights[..<split]), first) + partition(Array(weights[split...]), second)
    }
}

struct StorageActionBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(model.storageSelection.count) selected · \(formatBytes(model.storageIndex?.selectedBytes(model.storageSelection) ?? 0)) unique logical bytes").font(.caption)
                Spacer()
                Button("Deselect all") { model.storageSelection = [] }.disabled(model.storageSelection.isEmpty)
                if model.storageMoving { Button("Stop") { model.cleanupSession.stop() }.disabled(model.cleanupSession.stopping) }
                else { Button("Move to Trash", systemImage: "trash") { model.trashStorage() }.disabled(model.storageUnavailableReason != nil) }
            }
            Text(model.storageOutcome ?? " ").font(.caption).lineLimit(2).help(model.storageOutcome ?? "")
                .textSelection(.enabled).frame(height: 28, alignment: .leading)
            Text(model.storageMoving ? "Stop ends before the next item; completed moves remain in Activity." : model.storageUnavailableReason ?? "Only selected local items will move to Trash.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 26, alignment: .leading)
            HStack {
                Button("Activity") { model.destination = .history }
                if let id = model.lastStorageSessionID, let session = model.cleanupSession.sessions.first(where: { $0.id == id }), model.canUndo(session) {
                    Button("Undo") { model.undo(session) }.disabled(model.mutationUnavailableReason != nil)
                }
            }.font(.caption)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
}
