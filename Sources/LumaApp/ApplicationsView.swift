import SwiftUI
import LumaCore

struct ApplicationsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var search = ""
    @ViewState private var sortBySize = false
    private var visible: [ApplicationRecord] {
        let apps = model.applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
        return sortBySize ? apps.sorted { $0.bytes > $1.bytes } : apps
    }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 22) {
            Picker("Applications", selection: $model.applicationTab) {
                ForEach(ApplicationTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
            }.pickerStyle(.segmented).frame(width: 260).disabled(model.busy)
            if model.applicationTab == .leftovers {
                LeftoversView()
            } else if !model.completedScans.contains(.applications) {
                EmptyState(symbol: "square.stack.3d.up", title: "Meet your applications.", message: "Inventory your Applications folders, then inspect exact bundle identifiers and related data. Shared containers and fuzzy matches are excluded.", actionTitle: "Find installed applications") { model.runScan(.applications) }.disabled(model.busy)
            } else {
                HStack(spacing: 16) {
                    summary("APPLICATIONS", value: "\(model.applications.count)")
                    summary("BUNDLE STORAGE", value: formatBytes(model.applications.reduce(0) { $0 + $1.bytes }))
                    summary("RELATIONSHIP MATCHING", value: "Exact identifiers")
                }
                HStack {
                    TextField("Filter applications", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Spacer()
                    Toggle("Largest first", isOn: $sortBySize).toggleStyle(.checkbox).font(.system(size: 11))
                }
                Surface(padding: 18) {
                    VStack(spacing: 0) {
                        ForEach(visible) { app in
                            Button { model.inspect(app) } label: {
                                HStack(spacing: 14) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.name).font(.system(size: 12, weight: .semibold))
                                        Text("\(app.version) · \(app.bundleID)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(app.bytes == 0 ? "Size unavailable" : formatBytes(app.bytes)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                            if app.id != visible.last?.id { Divider() }
                        }
                        if visible.isEmpty { Text("No applications match this filter.").foregroundStyle(.secondary).padding(25) }
                    }
                }
            }
        }
        .onChange(of: model.applicationTab) { _, _ in model.selected = [] }
    }
    private func summary(_ title: String, value: String) -> some View {
        Surface(padding: 18) { VStack(alignment: .leading, spacing: 13) { Eyebrow(text: title); Text(value).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) } }
    }
}

struct LeftoversView: View {
    @Environment(AppModel.self) private var model
    private var owners: [String] {
        Set(model.leftovers.compactMap(\.ownerBundleID)).sorted { left, right in
            model.leftovers.filter { $0.ownerBundleID == left }.reduce(0) { $0 + $1.bytes }
                > model.leftovers.filter { $0.ownerBundleID == right }.reduce(0) { $0 + $1.bytes }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.didScanLeftovers {
                EmptyState(symbol: "tray.full", title: "What did an old app leave behind?",
                    message: "Look for data with exact bundle identifiers that no installed app or helper claims. Every result requires review; some may be useful if you reinstall.",
                    actionTitle: model.busy ? "Checking ownership…" : "Find potential leftovers") { model.runScan(.applications) }.disabled(model.busy)
            } else {
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 9) {
                            Eyebrow(text: "Potential app leftovers")
                            Text(formatBytes(model.leftovers.filter { !model.isIgnored($0) }.reduce(0) { $0 + $1.bytes }))
                                .font(.system(size: 36, weight: .semibold))
                            Text("\(owners.count) bundle identifiers · no installed owner found").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(); SymbolTile(symbol: "tray.full", tint: Palette.peach, size: 58)
                    }
                }
                Label("These are review candidates, not guaranteed junk. App documents, preferences, and offline content can remain useful.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if model.leftovers.isEmpty {
                    ContentUnavailableView("No potential leftovers found", systemImage: "checkmark.circle", description: Text("Only exact identifiers in supported locations are checked. Read failures are listed under scan coverage."))
                }
                ForEach(owners, id: \.self) { owner in
                    Surface(padding: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(owner).font(.system(size: 12, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                                Spacer(); SafetyBadge(level: .review)
                            }
                            ItemList(items: model.leftovers.filter { $0.ownerBundleID == owner })
                        }
                    }
                }
                SelectionBar(items: model.leftovers)
                Text("Checks Applications folders, embedded helpers, and macOS Launch Services. Named support folders require an explicit ownership rule. Shared groups, Apple data, fuzzy matches, and symbolic links are excluded.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct AppFootprintView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let app: ApplicationRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name).font(.system(size: 24, weight: .semibold))
                    Text(app.bundleID).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack { Eyebrow(text: "Matched footprint"); Spacer(); Text(formatBytes(model.footprint.reduce(0) { $0 + $1.bytes })).font(.system(size: 24, weight: .semibold)) }
            Text("Only exact bundle identifier matches are shown. Other app data may remain. Review preferences and support files carefully; they can contain personal data.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView { ItemList(items: model.footprint) }.frame(maxHeight: 360)
            HStack {
                Button("Open application") { NSWorkspace.shared.open(app.url) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                Spacer()
                PrimaryButton(title: "Review selection", symbol: "arrow.right") {
                    let selected = model.footprint.filter { model.selected.contains($0.id) }
                    dismiss()
                    Task { try? await Task.sleep(for: .milliseconds(250)); model.reviewItems = selected; model.showingReview = !selected.isEmpty }
                }.disabled(!model.footprint.contains { model.selected.contains($0.id) } || model.busy)
            }
        }.padding(28).frame(width: 760)
        .onAppear { model.selected = [] }
    }
}
