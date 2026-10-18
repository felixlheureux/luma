import SwiftUI
import LumaCore

struct ApplicationsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var search = ""
    @ViewState private var sortBySize = false
    @ViewState private var displayLimit = 200
    private var visible: [ApplicationRecord] {
        let apps = model.visibleApplications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
        return sortBySize ? apps.sorted { ($0.sizeState == .available ? $0.bytes : -1) > ($1.sizeState == .available ? $1.bytes : -1) } : apps
    }
    private var measuredStorage: String {
        let apps = model.visibleApplications
        let measured = apps.filter { $0.sizeState == .available }
        if measured.isEmpty && apps.contains(where: { $0.sizeState == .pending }) { return "Measuring…" }
        if measured.isEmpty && !apps.isEmpty { return "Unavailable" }
        return formatBytes(measured.reduce(0) { $0 + $1.bytes })
    }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 22) {
            Picker("Applications", selection: $model.applicationTab) {
                ForEach(ApplicationTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
            }.pickerStyle(.segmented).frame(width: 260)
            if model.applicationTab == .leftovers {
                LeftoversView()
            } else if !model.completedScans.contains(.applications) && model.visibleApplications.isEmpty {
                EmptyState(symbol: "square.stack.3d.up", title: "Meet your applications.", message: "Inventory your Applications folders, then inspect exact bundle identifiers and related data. Shared containers and fuzzy matches are excluded.", actionTitle: "Find installed applications") { model.runScan(.applications) }.disabled(!model.canStartScan)
            } else {
                HStack(spacing: 16) {
                    summary("APPLICATIONS", value: "\(model.visibleApplications.count)")
                    summary("MEASURED BUNDLE STORAGE", value: measuredStorage)
                    summary("RELATIONSHIP MATCHING", value: "Exact paths and mappings")
                }
                if model.scanSessions.isBusy && [.applications, .overview].contains(model.scanTarget) {
                    Text("Live inventory preview · sizes may still be pending · inspection is available when this scan finishes.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if model.applications.contains(where: { $0.sizeState == .unavailable }) {
                    Text("Measured storage excludes applications with unavailable sizes. See coverage for details.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Filter applications", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Spacer()
                    Toggle("Largest first", isOn: $sortBySize).toggleStyle(.checkbox).font(.system(size: 11))
                }
                Surface(padding: 18) {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.prefix(displayLimit))) { app in
                            if model.busy {
                                applicationRow(app).accessibilityLabel("\(app.name), read-only scan preview")
                            } else {
                                Button { model.inspect(app) } label: { applicationRow(app) }.buttonStyle(.plain)
                            }
                            if app.id != visible.last?.id { Divider() }
                        }
                        if visible.count > displayLimit {
                            Button("Show 200 more applications") { displayLimit += 200 }.padding(12)
                        }
                        if visible.isEmpty { Text("No applications match this filter.").foregroundStyle(.secondary).padding(25) }
                    }
                }
            }
        }
        .onChange(of: model.applicationTab) { _, _ in model.selected = [] }
    }
    private func applicationRow(_ app: ApplicationRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.secondary).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 12, weight: .semibold))
                Text("\(app.version) · \(app.bundleID)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(app.sizeState == .pending ? "Size pending…" : app.sizeState == .unavailable ? "Size unavailable" : formatBytes(app.bytes))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            if !model.busy { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }.padding(.vertical, 10).contentShape(Rectangle())
    }

    private func summary(_ title: String, value: String) -> some View {
        Surface(padding: 18) { VStack(alignment: .leading, spacing: 13) { Eyebrow(text: title); Text(value).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) } }
    }
}

struct LeftoversView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var ownerLimit = 100
    private struct OwnerGroup: Identifiable {
        let id: String
        let items: [CleanupItem]
        let bytes: Int64
    }
    private var groups: [OwnerGroup] {
        Dictionary(grouping: model.leftovers, by: { $0.ownerBundleID ?? "Unknown owner" }).map { owner, items in
            OwnerGroup(id: owner, items: items, bytes: items.reduce(0) { $0 + $1.bytes })
        }.sorted { $0.bytes > $1.bytes }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.didScanLeftovers {
                EmptyState(symbol: "tray.full", title: "What did an old app leave behind?",
                    message: "Look for data with exact bundle identifiers that no installed app or helper claims. Every result requires review; some may be useful if you reinstall.",
                    actionTitle: model.scanSessions.isBusy ? "Queue ownership check" : "Find potential leftovers") { model.runScan(.applications) }.disabled(!model.canStartScan)
            } else {
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 9) {
                            Eyebrow(text: "Potential app leftovers")
                            Text(formatBytes(model.leftovers.filter { !model.isIgnored($0) }.reduce(0) { $0 + $1.bytes }))
                                .font(.system(size: 36, weight: .semibold))
                            Text("\(groups.count) bundle identifiers · no installed owner found").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(); SymbolTile(symbol: "tray.full", tint: Palette.peach, size: 58)
                    }
                }
                Label("These are review candidates, not guaranteed junk. App documents, preferences, and offline content can remain useful.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if model.leftovers.isEmpty {
                    ContentUnavailableView("No potential leftovers found", systemImage: "checkmark.circle", description: Text("Only exact identifiers in supported locations are checked. Read failures are listed under scan coverage."))
                }
                ForEach(Array(groups.prefix(ownerLimit))) { group in
                    Surface(padding: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(group.id).font(.system(size: 12, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                                Spacer(); SafetyBadge(level: .review)
                            }
                            ItemList(items: group.items)
                        }
                    }
                }
                if groups.count > ownerLimit { Button("Show 100 more owners") { ownerLimit += 100 }.buttonStyle(.glass) }
                SelectionBar(items: model.leftovers)
                Text("Checks Applications folders, embedded helpers, and macOS Launch Services. Named support folders require an explicit ownership rule. Shared groups, Apple data, fuzzy matches, and symbolic links are excluded.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
