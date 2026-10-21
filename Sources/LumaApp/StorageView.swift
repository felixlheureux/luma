import SwiftUI
import AppKit
import LumaCore

struct StorageView: View {
    @Environment(AppModel.self) private var model
    private var filter: String { model.storageFilter }
    private var isExploring: Bool { model.storageMode == "Explore" && (filter != "Selected" || model.storageInspecting) }
    private var sort: String { model.storageSort }
    private var showHidden: Bool { model.storageShowHidden }
    @ViewState private var reveal = StorageListReveal()
    @FocusState private var keyboardRow: String?
    @ViewState private var pinnedOrder: [String] = []
    @ViewState private var pointerInList = false
    private var index: StorageIndex? { model.storageIndex }
    private var current: StorageNode? { model.storageDirectory.flatMap { index?.nodes[$0] } }
    @ViewState private var visible: [StorageNode] = []
    @ViewState private var mapEntries: [StorageMapEntry] = []
    @ViewState private var explore = StorageExploreListing(nodes: [])
    @ViewState private var mapRevealTarget: String?
    @ViewState private var mapRevealRequest = UUID()
    private struct ListingKey: Equatable {
        let revision: UInt64
        let query: StorageListingQuery
    }
    private var listingKey: ListingKey {
        ListingKey(revision: model.storageRevision, query: StorageListingQuery(
            largestFiles: model.storageMode == "Largest files", directory: model.storageDirectory,
            filter: model.storageInspecting ? "All items" : filter, showHidden: showHidden || model.storageInspecting,
            search: model.storageInspecting ? "" : model.storageSearch,
            location: model.storageInspecting ? "All locations" : model.storageLocation, sort: sort,
            selection: filter == "Selected" ? model.storageSelection : [],
            pinnedOrder: pointerInList || keyboardRow != nil ? pinnedOrder : []))
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { browsePicker; Spacer(); scanControls }
                VStack(alignment: .leading, spacing: 8) {
                    browsePicker
                    HStack { scanControls; Spacer() }
                }
            }
            Text(model.storageStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(model.storageStatus).frame(height: 20, alignment: .leading)
            if let index {
                if !index.isDiscovery { Text("Published location: \(index.scope.root.path) · \(index.scope.inspectionOnly ? "Inspection only" : "Local files")").font(.caption).textSelection(.enabled) }
                controls(index)
                if index.isDiscovery {
                    Text("iCloud metadata is partial and read-only. Online-only files are never downloaded; cloud logical sizes are excluded from local totals. Missing metadata may mean offline, signed out or unavailable access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isExploring, let current {
                    navigation(index, current)
                    folderSummary(index, current)
                    if visible.isEmpty {
                        list.frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                StorageBubbleMap(entries: mapEntries, focused: model.storageFocus, focus: focusMap, hover: { model.storageFocus = $0 }, activate: activate)
                                    .frame(minWidth: 280, maxWidth: .infinity).frame(height: 420)
                                list.frame(minWidth: 340, maxWidth: .infinity).nativeCheckTarget("storage-browser-list")
                            }.frame(idealWidth: 660, maxWidth: .infinity).nativeCheckTarget("storage-explore-columns")
                            VStack(alignment: .leading) {
                                list
                                DisclosureGroup("Space map") {
                                    StorageBubbleMap(entries: mapEntries, focused: model.storageFocus, focus: focusMap, hover: { model.storageFocus = $0 }, activate: activate).frame(height: 260)
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
                        if let next = index.largerScanLimit(current: model.storageLimit) {
                            Button("Rescan with larger entry limit (\(next))") { model.rescanStorageWithLargerLimit() }
                                .disabled(model.storageDiscovery.isBusy || model.operationBusy || model.storageLoading)
                                .nativeCheckTarget("storage-larger-scan")
                            Text("Restarts discovery from the beginning with a larger entry limit. Previous results stay visible until it finishes; time bounds stay the same.")
                        } else if index.discoveryBounds?.contains(.time) == true {
                            Text("A time bound was reached. Increasing the entry limit cannot extend that bound; Scan again starts a fresh scan.")
                        }
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
                return (rows: rows, partition: StorageExploreListing(nodes: rows), map: query.largestFiles || query.filter == "Selected" ? [] : StorageMapEntry.entries(for: rows))
            }
            let result = await withTaskCancellationHandler {
                try? await worker.value
            } onCancel: { worker.cancel() }
            if !Task.isCancelled, let result {
                visible = result.rows; explore = result.partition; mapEntries = result.map
                if model.storageInspecting, let id = model.storageFocus { focusMap(id) }
            }
        }
        .onChange(of: filter) { _, _ in reveal = StorageListReveal(); pinnedOrder = [] }
        .onChange(of: sort) { _, _ in pinnedOrder = [] }
        .onChange(of: keyboardRow) { _, id in
            if let id { model.storageFocus = id; if pinnedOrder.isEmpty { pinnedOrder = visible.map(\.id) } }
        }
        .onChange(of: model.storageDirectory) { _, _ in reveal = StorageListReveal(); pinnedOrder = [] }
        .onChange(of: model.storageMode) { _, value in if value == "Largest files" { model.storageInspecting = false } }
        .onChange(of: model.storageRevealRequest) { _, _ in if let id = model.storageFocus { focusMap(id) } }
    }

    private var browsePicker: some View {
        @Bindable var model = model
        return Picker("Browse", selection: $model.storageMode) {
            Text("Largest files").tag("Largest files"); Text("Explore").tag("Explore")
        }.pickerStyle(.segmented).labelsHidden().frame(width: 280, alignment: .leading)
    }
    @ViewBuilder private var scanControls: some View {
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

    private func controls(_ index: StorageIndex) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            if model.storageInspecting {
                HStack {
                    Text("Folder inspection · browsing filters paused for this path")
                    Spacer()
                    Button("Resume filters") { model.storageInspecting = false }
                }.foregroundStyle(.secondary)
            }
            TextField("Search discovered paths", text: $model.storageSearch).textFieldStyle(.roundedBorder)
                .disabled(filter == "Selected" || model.storageInspecting)
            if filter == "Selected" && !model.storageInspecting {
                Text("All selected targets across folders · search, location and hidden filters are paused.").foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { filters(index); Toggle("Hidden", isOn: Binding(get: { model.storageShowHidden }, set: { model.storageShowHidden = $0 })).disabled(filter == "Selected" || model.storageInspecting) }
                VStack(alignment: .leading) { filters(index); Toggle("Hidden", isOn: Binding(get: { model.storageShowHidden }, set: { model.storageShowHidden = $0 })).disabled(filter == "Selected" || model.storageInspecting) }
            }
        }.font(.caption)
    }
    private func filters(_ index: StorageIndex) -> some View {
        @Bindable var model = model
        return HStack {
            Picker("Show", selection: Binding(get: { model.storageFilter }, set: { model.storageFilter = $0 })) { ForEach(["All items", "Selected", "Over 100 MB", "Older than a year", "Installers"], id: \.self) { Text($0) } }.disabled(model.storageInspecting)
            Picker("Sort", selection: $model.storageSort) { ForEach(["Size", "Name", "Modified"], id: \.self) { Text($0) } }
            Picker("Location", selection: $model.storageLocation) {
                Text("All locations").tag("All locations")
                ForEach(index.scopes, id: \.root.path) { Text($0.root.path).tag($0.root.path) }
                ForEach(["Downloads", "Documents", "Desktop", "Projects"], id: \.self) { name in Text(name).tag(model.uninstallHome.appendingPathComponent(name).path) }
            }.disabled(filter == "Selected" || model.storageInspecting)
        }
    }
    private var list: some View {
        Surface(padding: 12) {
            ScrollViewReader { proxy in
                FittingStorageList(isEmpty: visible.isEmpty) {
                    if visible.count <= 12 {
                        VStack(alignment: .leading, spacing: 0) { listRows }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) { listRows }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onChange(of: mapRevealRequest) { _, _ in
                    let target = mapRevealTarget
                    Task { @MainActor in
                        // Let the disclosure insert its rows before resolving their anchors.
                        try? await Task.sleep(for: .milliseconds(30))
                        guard mapRevealTarget == target else { return }
                        if let target { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .center).onHover { inside in
            if inside { pinnedOrder = visible.map(\.id) }
            pointerInList = inside
        }
    }

    @ViewBuilder private var listRows: some View {
        if visible.isEmpty {
            ContentUnavailableView("No matching results", systemImage: "magnifyingglass",
                description: Text("Try different filters. Some locations may still be unindexed or unavailable."))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        }
        ForEach(isExploring ? explore.primary : Array(visible.prefix(reveal.displayLimit))) { node in row(node).id(node.id); Divider() }
        if isExploring, visible.count > 12 {
            DisclosureGroup("Other items (\(visible.count - 12))", isExpanded: $reveal.showOther) {
                EmptyView()
            }.padding(.vertical, 8).id("storage-remainder")
            // Keep row anchors directly in the lazy stack so map focus
            // can reveal a row before it enters the scroll viewport.
            if reveal.showOther {
                ForEach(Array(explore.remainder.prefix(max(0, reveal.displayLimit - 12)))) { node in
                    row(node).padding(.leading, 12).id(node.id); Divider()
                }
            }
        }
        if visible.count > reveal.displayLimit { Button("Other items · show 200 more") { reveal.displayLimit += 200; reveal.showOther = true }.padding() }
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
                            .help(node.url.isFileURL ? node.url.path : "Accessible Mac storage")
                        if node.id != current.id { Image(systemName: "chevron.right") }
                    }
                }.font(.caption)
            }
        }.buttonStyle(.borderless)
    }
    private func folderSummary(_ index: StorageIndex, _ node: StorageNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.url.isFileURL ? node.url.path : "Accessible Mac storage").textSelection(.enabled)
            Text("\(formatBytes(index.selectedBytes([node.id]))) observed unique logical bytes · \(node.children.count) observed children · \(node.isComplete ? "complete coverage" : "partial coverage; skipped contents unknown")")
                .foregroundStyle(.secondary)
            if node.url.isFileURL && node.cloud == nil {
                ViewThatFits(in: .horizontal) {
                    HStack { folderActions(node); Spacer() }
                    VStack(alignment: .leading) { folderActions(node) }
                }
                if let reason = model.storageSelectionIssue(node) { Text(reason).foregroundStyle(.secondary) }
            }
        }.font(.caption)
    }
    @ViewBuilder private func folderActions(_ node: StorageNode) -> some View {
        if !node.isComplete || node.requiresVerification == true || Date().timeIntervalSince(node.observedAt) >= 1800 {
            Button("Analyze this folder") { model.analyzeStorageFolder(node) }
                .disabled(model.storageDiscovery.isBusy || model.storageLoading || model.operationBusy || (model.scanSessions.isBusy && model.scanTarget == .storage))
                .nativeCheckTarget("storage-analyze-folder")
            Text("This folder only · up to 40,000 entries · bounded time").foregroundStyle(.secondary)
        } else {
            Button("Select this folder") { model.selectStorage(node, selected: true) }
                .disabled(!model.storageEligible(node) || model.storageMoving)
                .help(model.storageSelectionIssue(node) ?? "Replace selected descendants with this exact folder")
                .nativeCheckTarget("storage-select-folder")
        }
    }
    private func focusMap(_ id: String) {
        reveal.reveal(id, in: visible)
        model.storageFocus = id
        mapRevealTarget = id == "storage-remainder" ? explore.remainder.first?.id : id
        mapRevealRequest = UUID()
    }
    private func activate(_ id: String) {
        focusMap(id)
        if id == "storage-remainder" { return }
        if index?.nodes[id]?.canNavigate == true { model.navigateStorage(id) }
        else { model.storageFocus = id }
    }
    private func row(_ node: StorageNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("Select \(node.url.lastPathComponent)", isOn: Binding(get: { model.storageSelection.contains(node.id) }, set: { model.selectStorage(node, selected: $0) }))
                    .toggleStyle(.checkbox).labelsHidden().nativeCheckTarget("storage-select-" + node.id)
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
                if model.storageMode == "Largest files", !node.isDirectory, index?.containingFolder(of: node.id) != nil {
                    Button { model.inspectStorageParent(node) } label: { Image(systemName: "folder").frame(width: 24, height: 24) }
                        .buttonStyle(.borderless).help("Inspect containing folder")
                        .accessibilityLabel("Inspect containing folder for \(node.url.lastPathComponent)")
                        .nativeCheckTarget("storage-inspect-" + node.id)
                }
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
            if model.storageSelection.contains(node.id) && !model.storageEligible(node) {
                Text("Unavailable for removal · stale, incomplete, protected, ignored or read-only. Deselect or scan again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.url.path).textSelection(.enabled)
                    Text(node.issue ?? "Complete local observation. Personal data is never automatically junk.")
                    if let reason = model.storageSelectionIssue(node) { Text(reason) }
                    if node.cloud == nil, index?.containingFolder(of: node.id) != nil {
                        Button("Inspect containing folder") { model.inspectStorageParent(node) }
                    }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                }.font(.caption).foregroundStyle(.secondary)
            }.font(.system(size: 10))
        }.font(.system(size: 12)).padding(10).nativeCheckTarget("storage-row-" + node.id)
            .background(model.storageFocus == node.id ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Each responsive alternative measures its own content. Sharing one height
/// between the side-by-side and stacked layouts would couple their geometry.
private struct FittingStorageList<Content: View>: View {
    let isEmpty: Bool
    let content: Content
    @ViewState private var contentHeight: CGFloat = 420
    init(isEmpty: Bool, @ViewBuilder content: () -> Content) {
        self.isEmpty = isEmpty
        self.content = content()
    }
    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in
                contentHeight = height
            }
        }.frame(height: isEmpty ? 220 : min(420, max(1, contentHeight)))
    }
}

private struct StorageBubbleMap: View {
    let entries: [StorageMapEntry]
    let focused: String?
    let focus: (String) -> Void
    let hover: (String) -> Void
    let activate: (String) -> Void
    @FocusState private var keyboardBubble: String?
    private let colors: [Color] = [Palette.accent, Palette.blue, Palette.mint, Palette.peach]
    var body: some View {
        GeometryReader { geometry in
            let circles = StorageBubbleLayout.circles(for: entries, in: geometry.size)
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ForEach(circles) { circle in
                if let entry = byID[circle.id] {
                    let diameter = circle.radius * 2
                    let colorIndex = entry.id.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }
                    Button { focus(entry.id) } label: {
                        Circle().fill((entry.isRemainder ? Color.gray : colors[colorIndex]).gradient)
                            .overlay(Circle().strokeBorder(.primary.opacity(focused == entry.id ? 0.9 : 0), lineWidth: 3))
                            .overlay {
                                if diameter > 70 {
                                    VStack(spacing: 4) { Text(entry.name).lineLimit(2); Text(formatBytes(entry.bytes)) }
                                        .font(.system(size: 10)).foregroundStyle(.white).padding(8)
                                }
                            }
                            .frame(width: diameter, height: diameter).contentShape(Circle())
                    }
                    .nativeCheckTarget("storage-map-" + entry.id).buttonStyle(.plain)
                    .focused($keyboardBubble, equals: entry.id)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { activate(entry.id) })
                    .onKeyPress(.return) { activate(entry.id); return .handled }
                    .position(circle.center)
                    .onHover { if $0 { hover(entry.id) } }
                    .accessibilityLabel("\(entry.name), \(formatBytes(entry.bytes))")
                    .accessibilityHint(entry.isRemainder ? "Show other items in the list" : "Click to focus in the list. Double-click or press Return to open a folder.")
                    .help("\(entry.name) · \(formatBytes(entry.bytes)) · \(entry.isRemainder ? "Show other items in the list" : "Click to focus · Double-click to open folder")")
                }
            }
        }.nativeCheckTarget("storage-map-viewport").onChange(of: keyboardBubble) { _, id in if let id { focus(id) } }
    }
}

struct StorageActionBar: View {
    @Environment(AppModel.self) private var model
    private var feedback: String? {
        if model.storageMoving {
            return (model.cleanupSession.detail?.phase ?? "Preparing and moving to Trash…")
                + " · Stop ends before the next item; completed moves remain in Activity."
        }
        // An empty selection is already explained by the count and disabled action.
        let reason = model.storageSelection.isEmpty ? model.mutationUnavailableReason : model.storageUnavailableReason
        if let outcome = model.storageOutcome {
            return reason.map { $0 == outcome ? outcome : outcome + " · " + $0 } ?? outcome
        }
        return reason
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { selection; Spacer(minLength: 4); actions }
                VStack(alignment: .leading, spacing: 6) {
                    selection
                    HStack(spacing: 8) { actions }
                }
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
    }
    private var selection: some View {
        Text("\(model.storageSelection.count) selected · \(formatBytes(model.storageIndex?.selectedBytes(model.storageSelection) ?? 0))")
            .font(.caption).fixedSize().help("Selected unique logical bytes")
    }
    @ViewBuilder private var actions: some View {
        Button("Deselect") { model.storageSelection = [] }.disabled(model.storageSelection.isEmpty)
        if model.storageMoving { Button("Stop") { model.cleanupSession.stop() }.disabled(model.cleanupSession.stopping) }
        else {
            Button("Move to Trash", systemImage: "trash") { model.trashStorage() }
                .disabled(model.storageUnavailableReason != nil)
                .help(model.storageUnavailableReason ?? "Move selected local items to Trash")
        }
        if let id = model.lastStorageSessionID, let session = model.cleanupSession.sessions.first(where: { $0.id == id }), model.canUndo(session) {
            Button("Undo") { model.undo(session) }.disabled(model.mutationUnavailableReason != nil)
        }
        Button("Activity") { model.openCore(.history) }.nativeCheckTarget("Activity")
    }
}
