import SwiftUI
import LumaCore

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all
    @ViewState private var scrollPosition = ScrollPosition(y: 0)
    @ViewState private var pageOffsets: [Destination: CGFloat] = [:]
    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView().navigationSplitViewColumnWidth(min: 205, ideal: 216, max: 250)
        } detail: {
            GeometryReader { geometry in
                ZStack {
                    AmbientBackground()
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 28) {
                                    pageHeader.id("page-top")
                                    if model.destination != .maintenance && model.uninstallingApp == nil && !model.residueMoving && !model.storageMoving { CleanupProgressPanel() }
                                    if model.destination != .storage && model.destination != .maintenance { ScanSessionPanel() }
                                    if let target = model.currentScanTarget, target != .overview, target != .storage, model.destination != .maintenance { CompletedScanCaption(target: target) }
                                    Group {
                                        switch model.destination ?? .overview {
                                        case .overview: OverviewView()
                                        case .residues: LeftoversView().task { if !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) { model.ensureResidues() } }
                                        case .maintenance: MaintenanceEntryView()
                                        case .clean: CleanView()
                                        case .backups: DeviceBackupsView()
                                        case .downloads: DownloadsView()
                                        case .projects: ProjectsView()
                                        case .storage: StorageView()
                                        case .applications: ApplicationsView()
                                        case .duplicates: DuplicatesView()
                                        case .optimizer: OptimizerView()
                                        case .system: SystemView()
                                        case .privacy: PrivacyView()
                                        case .history: HistoryView()
                                        }
                                    }
                                }.padding(.horizontal, 36).padding(.top, 22).padding(.bottom, 30).frame(maxWidth: 1160)
                                    .frame(maxWidth: .infinity)
                            }
                            .scrollPosition($scrollPosition)
                            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                                if let page = model.destination { pageOffsets[page] = y }
                            }
                            .onChange(of: model.destination) { _, page in
                                let y = page.flatMap { pageOffsets[$0] } ?? 0
                                DispatchQueue.main.async { scrollPosition.scrollTo(y: y) }
                            }
                            .onChange(of: model.monitoringFocus) { _, id in
                                guard let id else { return }
                                DispatchQueue.main.async {
                                    if model.destination == .system, model.monitoringFocus == id { proxy.scrollTo(id, anchor: .top) }
                                }
                            }
                            .onChange(of: model.duplicateComparisonGroup) { _, id in
                                if let id { proxy.scrollTo("duplicate-group-" + id, anchor: .top) }
                            }
                            .onChange(of: model.downloadsTab) { _, _ in
                                if model.destination == .downloads { proxy.scrollTo("page-top", anchor: .top) }
                            }
                            .onChange(of: model.downloadFocus) { _, id in
                                if model.destination == .downloads, id != nil {
                                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("downloads-details", anchor: .bottom) }
                                }
                            }

                        }.frame(minHeight: 0, maxHeight: .infinity)
                        if model.destination == .applications && model.applicationTab == .installed { ApplicationActionBar() }
                        if model.destination == .residues || (model.destination == .applications && model.applicationTab == .leftovers) { ResidueActionBar() }
                        if model.destination == .storage { StorageActionBar() }
                        WindowStatusBar()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .navigationTitle("")
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer").font(.system(size: 11))
                        Text(model.computerName).font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.showingSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search tools and scanned files").help("Search tools and scanned files (⌘K)").keyboardShortcut("k", modifiers: .command)
                        .popover(isPresented: $model.showingSearch, arrowEdge: .bottom) { SearchView() }
                }
            }
        }
        .background(MainWindowReader(model: model))
        .background(ClickAwayEditing())
        .tint(Palette.accent)
        .frame(minWidth: 640, minHeight: 540)
        .sheet(isPresented: $model.showingReview) { ReviewSheet() }
        .sheet(item: $model.inspectedApp) { app in AppFootprintView(app: app) }
        .alert("Luma needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.destination) { _, _ in
            model.cancelPendingReview()
            if let page = model.destination, Destination.core.contains(page) {
                UserDefaults.standard.set(page.rawValue, forKey: "luma.lastCorePage")
            }
        }
        .onChange(of: model.applicationTab) { _, _ in model.cancelPendingReview() }
        .onChange(of: model.downloadsTab) { _, _ in model.cancelPendingReview() }
        .task {
            model.showMainWindow = {
                if let window = model.mainWindow {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    window.makeKeyAndOrderFront(nil)
                } else { openWindow(id: "main") }
                NSApplication.shared.activate()
            }
            model.showSettingsWindow = { openSettings(); NSApplication.shared.activate() }
            model.startMonitoring()
            await model.loadJournal()
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text((model.destination ?? .overview).rawValue).font(.system(size: 28, weight: .semibold)).tracking(-0.7).accessibilityAddTraits(.isHeader)
                Text((model.destination ?? .overview).subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.canCancel {
                Button { model.cancel() } label: { Label(model.scanSessions.isBusy ? "Cancel scan" : "Cancel review", systemImage: "stop.circle") }.buttonStyle(.glass)
            }
            if [.clean, .applications].contains(model.destination ?? .overview) {
                Button { if model.destination == .applications { if model.applicationTab == .installed { model.ensureApplicationInventory(refresh: true) } else { model.ensureResidues(refresh: true) } } else { model.runScan() } } label: { Label(model.scanSessions.isBusy ? "Queue new scan" : model.destination == .overview ? "Smart Check" : model.destination == .applications && model.applicationTab == .installed ? "Refresh inventory" : "Scan again", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                    .buttonStyle(.glass).controlSize(.large).font(.system(size: 11, weight: .medium)).keyboardShortcut("r", modifiers: .command).disabled(!model.canStartScan)
            }
        }
    }

}

struct LumaMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(red: 0.62, green: 0.59, blue: 0.97), Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(nsImage: LumaBrand.glyphImage(size: 20)).opacity(0.95)
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var typing: Bool
    @ViewState private var highlighted = 0
    private struct Match: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let activate: () -> Void
    }
    private var matches: [Match] {
        var result = Destination.allCases.filter { model.search.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(model.search) }.map { page in
            Match(id: "page:" + page.id, title: page.rawValue, detail: "Open page", symbol: page.symbol) { model.openCore(page) }
        }
        if model.search.isEmpty || "Settings".localizedCaseInsensitiveContains(model.search) {
            result.append(Match(id: "settings", title: "Settings", detail: "Preferences and permissions", symbol: "gearshape") { model.showSettingsWindow?() })
        }
        guard !model.search.isEmpty else { return result }
        result += model.visibleApplications.filter { $0.name.localizedCaseInsensitiveContains(model.search) || $0.bundleID.localizedCaseInsensitiveContains(model.search) }.prefix(20).map { app in
            Match(id: "app:" + app.id, title: app.name, detail: app.bundleID, symbol: "app") {
                model.applicationSearch = app.name; model.openCore(.applications)
            }
        }
        result += (model.storageIndex?.nodes.values.filter { $0.url.isFileURL && $0.url.path.localizedCaseInsensitiveContains(model.search) }.sorted { $0.bytes > $1.bytes }.prefix(40) ?? []).map { node in
            Match(id: "file:" + node.id, title: node.url.lastPathComponent, detail: node.url.path, symbol: node.isDirectory ? "folder" : "doc") {
                model.openCore(.storage)
                model.storageLocation = "All locations"; model.storageFilter = "All items"
                if node.hidden { model.storageShowHidden = true }
                model.storageSearch = node.url.path; model.storageMode = node.isDirectory ? "Explore" : "Largest files"
                if let parent = node.parentID { model.navigateStorage(parent) }
                model.storageFocus = node.id
            }
        }
        return result
    }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search apps and discovered paths", text: $model.search).textFieldStyle(.roundedBorder)
                .focused($typing).onSubmit { activate() }
                .onKeyPress(.downArrow) { highlighted = min(max(0, matches.count - 1), highlighted + 1); return .handled }
                .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { i, match in
                            Button { highlighted = i; activate() } label: {
                                HStack {
                                    Image(systemName: match.symbol)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(match.title).lineLimit(1)
                                        Text(match.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                }.padding(8).background(highlighted == i ? Palette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).id(i).nativeCheckTarget("search-" + match.id)
                        }
                        if matches.isEmpty { Text("No matches in available observations.").font(.caption) }
                        if model.storageIndex == nil { Text("Files are not indexed yet. Open Storage and choose Scan accessible Mac.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.onChange(of: highlighted) { _, i in proxy.scrollTo(i) }
            }
        }.padding(18).frame(width: 400, height: 400)
            .background(ClickAwayEditing())
            .defaultFocus($typing, true)
            .onChange(of: model.search) { _, _ in highlighted = 0 }
            .onExitCommand { model.showingSearch = false }
            .task { typing = true; if !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) { model.ensureApplicationInventory() } }
    }
    private func activate() {
        guard matches.indices.contains(highlighted) else { return }
        matches[highlighted].activate(); model.showingSearch = false
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LumaMark().frame(width: 30, height: 30)
                Text("luma").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1.0)
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 30)
            Eyebrow(text: "Workspace").padding(.horizontal, 23).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Destination.allCases.dropLast())) { destination in navRow(destination) }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 12)
            SidebarDiskCard()
            navRow(.history)
            SettingsLink {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 11)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 8)
            HStack(spacing: 5) { Image(systemName: "circle.dotted"); Text("OPEN SOURCE · LOCAL FIRST").tracking(0.7) }
                .font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 23).padding(.vertical, 21)
        }.background(.ultraThinMaterial)
    }

    private func navRow(_ destination: Destination) -> some View {
        let active = model.destination == destination
        return Button { model.openCore(destination) } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol).font(.system(size: 14, weight: active ? .semibold : .regular)).frame(width: 19)
                Text(destination.rawValue).font(.system(size: 12, weight: active ? .semibold : .medium))
                Spacer()
                if destination == .clean, !model.cleanup.isEmpty {
                    Text("\(model.cleanup.count)").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.05), in: Capsule())
                }
            }.foregroundStyle(active ? Color.white : .primary.opacity(0.63)).padding(.horizontal, 14).padding(.vertical, 11)
                .background {
                    if active { RoundedRectangle(cornerRadius: 11).fill(Palette.accent) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3).accessibilityAddTraits(active ? .isSelected : [])
    }

}

struct WindowStatusBar: View {
    @Environment(AppModel.self) private var model
    @ViewState private var showNotices = false
    var body: some View {
        HStack(spacing: 7) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Circle().fill(Palette.mint).frame(width: 5, height: 5) }
            Text(model.status).lineLimit(1)
            if !model.currentNotices.isEmpty {
                Button { showNotices.toggle() } label: { Image(systemName: "info.circle").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Show scan coverage")
                    .popover(isPresented: $showNotices) {
                        ScrollView { VStack(alignment: .leading, spacing: 10) {
                            Text("Scan coverage").font(.headline)
                            Text("From this feature's last completed snapshot. These excluded contents are absent from totals.").foregroundStyle(.secondary)
                            ForEach(Array(model.currentNotices.enumerated()), id: \.offset) { _, notice in Text(notice).textSelection(.enabled) }
                        }.padding(20) }.frame(width: 420, height: 330)
                    }
            }
            Spacer()
            if model.cleanupSession.isRunning {
                Button("Stop") { model.cleanupSession.stop() }.disabled(model.cleanupSession.stopping)
            }
            Image(systemName: "lock"); Text("On this Mac. Only.")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 11)
            .background(.bar)
    }
}

private struct SidebarDiskCard: View {
    @Environment(AppModel.self) private var model
    private var availability: String {
        guard model.system.diskAvailable else { return model.system.sampledAt == nil ? "Collecting…" : "Unavailable" }
        let stale = model.system.sampledAt.map { Date().timeIntervalSince($0) > 10 } ?? false
        return (stale ? "Stale · " : "") + "\(formatBytes(model.system.availableDisk)) available"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary)
                    Text("Macintosh HD").font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                GeometryReader { proxy in
                    Capsule().fill(.primary.opacity(0.07))
                    if model.system.diskAvailable {
                        Capsule().fill(LinearGradient(colors: [Palette.accent.opacity(0.6), Palette.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * CGFloat(min(1, max(0, 1 - Double(model.system.availableDisk) / Double(max(1, model.system.totalDisk))))))
                    }
                }.frame(height: 5)
                Text(availability).font(.system(size: 10)).foregroundStyle(.secondary).help("Available for important usage")
            }.padding(16).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 14).padding(.bottom, 18)
    }
}

/// Capture the actual SwiftUI main window without mistaking Settings or the panel for it.
private struct MainWindowReader: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WindowView { WindowView(model: model) }
    func updateNSView(_ view: WindowView, context: Context) {}
    final class WindowView: NSView {
        let model: AppModel
        init(model: AppModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { model.mainWindow = window } }
    }
}
