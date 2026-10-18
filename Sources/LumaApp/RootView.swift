import SwiftUI
import LumaCore

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView().navigationSplitViewColumnWidth(min: 205, ideal: 216, max: 250)
        } detail: {
            ZStack {
                AmbientBackground()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                pageHeader.id("page-top")
                                CleanupProgressPanel()
                                ScanSessionPanel()
                                if let target = model.currentScanTarget { CompletedScanCaption(target: target) }
                                Group {
                                    switch model.destination ?? .overview {
                                    case .overview: OverviewView()
                                    case .clean: CleanView()
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
                        .onChange(of: model.storageDirectory) { _, _ in
                            if model.destination == .storage { proxy.scrollTo("page-top", anchor: .top) }
                        }
                        .onChange(of: model.storageFocus) { _, id in
                            if model.destination == .storage, id != nil {
                                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("storage-details", anchor: .bottom) }
                            }
                        }
                    }
                    WindowStatusBar()
                }
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
        .tint(Palette.accent)
        .frame(minWidth: 1010, minHeight: 700)
        .sheet(isPresented: $model.showingReview) { ReviewSheet() }
        .sheet(item: Binding(get: { model.cleanupSession.undoReview }, set: { model.cleanupSession.undoReview = $0 })) { UndoReviewSheet(review: $0) }
        .sheet(item: $model.inspectedApp) { app in AppFootprintView(app: app) }
        .alert("Luma needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.destination) { _, _ in model.selected = [] }
        .task {
            model.showMainWindow = { openWindow(id: "main"); NSApplication.shared.activate() }
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
            if [.overview, .clean, .applications].contains(model.destination ?? .overview) {
                Button { model.runScan() } label: { Label(model.scanSessions.isBusy ? "Queue new scan" : model.destination == .overview ? "Local check" : "Scan again", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
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
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            TextField("Search tools, apps, and scanned files", text: $model.search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Destination.allCases.filter { model.search.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(model.search) }) { item in
                        Button { model.destination = item; model.showingSearch = false } label: { Label(item.rawValue, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.buttonStyle(.plain)
                    }
                    if !model.search.isEmpty {
                        if let index = model.storageIndex, let directory = model.storageDirectory {
                            ForEach(index.children(of: directory).filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(model.search) }.prefix(20)) { node in
                                Button {
                                    model.destination = .storage
                                    model.storageFocus = node.id
                                    model.showingSearch = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(node.url.lastPathComponent)
                                        Text(node.url.path).font(.caption).foregroundStyle(.secondary)
                                    }.padding(8)
                                }.buttonStyle(.plain)
                            }
                        }
                        ForEach((model.cleanup + model.storage).filter { $0.name.localizedCaseInsensitiveContains(model.search) }.prefix(20)) { item in
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                                VStack(alignment: .leading, spacing: 3) { Text(item.name); Text(item.displayPath).font(.caption).foregroundStyle(.secondary) }.padding(8)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(18).frame(width: 360, height: 370)
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
        return Button { model.destination = destination } label: {
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
            Image(systemName: "lock"); Text("On this Mac. Only.")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 11)
            .background(.bar)
    }
}

private struct SidebarDiskCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary)
                    Text("Macintosh HD").font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                GeometryReader { proxy in
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule().fill(LinearGradient(colors: [Palette.accent.opacity(0.6), Palette.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(1 - Double(model.system.availableDisk) / Double(max(1, model.system.totalDisk))))
                }.frame(height: 5)
                Text("\(formatBytes(model.system.availableDisk)) available").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(16).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 14).padding(.bottom, 18)
    }
}
