import SwiftUI
import LumaCore

struct ApplicationsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var sortBySize = false
    @ViewState private var displayLimit = 200
    private var visible: [ApplicationRecord] {
        let apps = model.visibleApplications.filter { model.applicationSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(model.applicationSearch) || $0.bundleID.localizedCaseInsensitiveContains(model.applicationSearch) }
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
            if model.applicationTab == .leftovers {
                LeftoversView()
            } else if !model.completedScans.contains(.applications) && model.visibleApplications.isEmpty {
                if let session = model.applicationInventory.session, session.phase.isTerminal {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.detail ?? model.applicationInventory.statusText).font(.caption)
                        Button("Retry inventory") { model.ensureApplicationInventory(refresh: true) }.disabled(model.operationBusy)
                    }
                } else {
                    ProgressView("Loading installed applications…").frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                HStack(spacing: 16) {
                    summary("APPLICATIONS", value: "\(model.visibleApplications.count)")
                    summary("MEASURED BUNDLE STORAGE", value: measuredStorage)
                }
                if model.applicationInventory.isBusy || (model.scanSessions.isBusy && [.applications, .overview].contains(model.scanTarget)) {
                    Text("Refreshing inventory · sizes may still be pending. Uninstall is available as rows arrive.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if model.applications.contains(where: { $0.sizeState == .unavailable }) {
                    Text("Measured storage excludes applications with unavailable sizes. See coverage for details.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(ApplicationUninstall.scopeDescription).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Filter applications", text: $model.applicationSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Spacer()
                    Toggle("Largest first", isOn: $sortBySize).toggleStyle(.checkbox).font(.system(size: 11))
                }
                Surface(padding: 18) {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.prefix(displayLimit))) { app in
                            applicationRow(app)
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
        .task(id: model.applicationTab) {
            if !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) && model.applicationTab == .installed { model.ensureApplicationInventory() }
        }
    }
    private func applicationRow(_ app: ApplicationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 14) {
            ApplicationIconView(app: app)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 12, weight: .semibold))
                Text("\(app.version) · \(app.bundleID)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(app.sizeState == .pending ? "Size pending…" : app.sizeState == .unavailable ? "Size unavailable" : formatBytes(app.bytes))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Button("Details") { model.inspect(app) }.disabled(model.operationBusy)
            Button("Uninstall") { model.uninstall(app) }
                .disabled(model.uninstallUnavailableReason(app) != nil)
                .accessibilityLabel("Uninstall " + app.name)
        }
        VStack(alignment: .leading, spacing: 4) {
            if let message = model.uninstallMessages[app.id] ?? model.uninstallUnavailableReason(app) {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        }.padding(.vertical, 10).contentShape(Rectangle())
    }

    private func summary(_ title: String, value: String) -> some View {
        Surface(padding: 18) { VStack(alignment: .leading, spacing: 13) { Eyebrow(text: title); Text(value).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) } }
    }
}

struct LeftoversView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var search = ""
    @ViewState private var largestFirst = false
    @ViewState private var collapsed: Set<String> = []
    private var groups: [LeftoverGroup] {
        LeftoverGroup.groups(for: model.visibleResidues, largestFirst: largestFirst, search: search)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App documents, preferences and offline content may be useful if you reinstall. Only your selected items move to Trash.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if model.residueDiscovery.isBusy { ProgressView().controlSize(.small) }
                    Text(model.residueStatus).font(.caption)
                    Spacer()
                    Button("Refresh") { model.ensureResidues(refresh: true) }
                        .disabled(model.residueDiscovery.isBusy || model.operationBusy)
                }
                if let date = model.residueSavedAt { Text("Last refresh: " + date.formatted()).font(.caption2).foregroundStyle(.secondary) }
                if !model.residueCoverage.isEmpty {
                    DisclosureGroup("Coverage") {
                        ForEach(Array(model.residueCoverage.enumerated()), id: \.offset) { _, notice in
                            Text(notice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(minHeight: 42, alignment: .topLeading)
            HStack {
                TextField("Filter identifiers or paths", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Largest first", isOn: $largestFirst).toggleStyle(.checkbox)
            }
            if groups.isEmpty {
                Text(model.residueDiscovery.isBusy ? "Discovering residues…" : model.didScanLeftovers ? "No residues in the checked locations match this filter. See coverage above." : "No current observations available. Refresh to retry.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical)
            }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    Surface(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ResidueGroupCheckbox(group: group).frame(width: 20, height: 20)
                                Button { if !collapsed.insert(group.id).inserted { collapsed.remove(group.id) } } label: {
                                    Label(group.id, systemImage: collapsed.contains(group.id) ? "chevron.right" : "chevron.down")
                                        .font(.system(.callout, design: .monospaced))
                                }.buttonStyle(.plain).accessibilityLabel("Expand or collapse " + group.id)
                                Spacer()
                                Text("\(group.items.count) items · \(formatBytes(group.bytes))").font(.caption)
                            }
                            if !collapsed.contains(group.id) {
                                ForEach(group.items) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Toggle("Select " + item.displayPath, isOn: Binding(get: { model.residueSelection[item.id] != nil },
                                            set: { model.selectResidue(item, selected: $0) }))
                                            .labelsHidden().toggleStyle(.checkbox).frame(width: 20)
                                            .disabled(!model.residueEligible(item) && model.residueSelection[item.id] == nil)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.displayPath).font(.caption).textSelection(.enabled)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.explanation)
                                                Text(item.consequence)
                                            }.font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(.leading, 28).padding(.vertical, 5)
                                }
                            }
                        }
                    }
                }
            }
        }.task { if !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) { model.ensureResidues() } }
    }
}

private struct ResidueGroupCheckbox: NSViewRepresentable {
    @Environment(AppModel.self) private var model
    let group: LeftoverGroup
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle))
        button.allowsMixedState = true
        button.setAccessibilityLabel("Select residues for " + group.id)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { model.selectResidueGroup(group) }
        let eligible = group.items.filter { model.residueEligible($0) }
        let count = eligible.filter { model.residueSelection[$0.id] != nil }.count
        button.state = count == 0 ? .off : count == eligible.count ? .on : .mixed
        button.isEnabled = !eligible.isEmpty
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {
        var action: (() -> Void)?
        @objc func toggle() { action?() }
    }
}

struct ResidueActionBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(model.selectedResidues.count) selected · \(formatBytes(LeftoverGroup.logicalBytes(model.selectedResidues))) including filtered groups")
                    .font(.caption)
                Spacer()
                Button("Deselect all") { model.residueSelection = [:] }
                Button("Move to Trash") { model.trashResidues() }
                    .disabled(model.selectedResidues.isEmpty || model.mutationUnavailableReason != nil)
                    .help(model.mutationUnavailableReason ?? "Move exactly the selected residues to Trash")
            }
            HStack {
                Text((model.residueMoving ? model.cleanupSession.detail?.phase : nil) ?? model.residueOutcome ?? model.mutationUnavailableReason ?? "Current ownership and file identity are checked before moving.").font(.caption).textSelection(.enabled)
                Spacer()
                if model.residueMoving {
                    Button("Stop") { model.cleanupSession.stop() }.disabled(model.cleanupSession.stopping)
                } else if let id = model.lastResidueSessionID,
                          let session = model.cleanupSession.sessions.first(where: { $0.id == id }), model.canUndo(session) {
                    Button("Undo") { model.undo(session) }.disabled(model.mutationUnavailableReason != nil)
                }
                Button("Activity") { model.destination = .history }.nativeCheckTarget("Activity")
            }
        }.padding(12).background(.bar)
    }
}

struct ApplicationActionBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
            HStack(spacing: 12) {
                if model.uninstallingApp != nil { ProgressView().controlSize(.small) }
                Text(model.uninstallingApp != nil ? "Preparing and moving to Trash…" : model.uninstallOutcome ?? "Choose Uninstall on an app row. Details are optional.")
                    .font(.caption).lineLimit(2)
                Spacer()
                if model.cleanupSession.isRunning {
                    Button("Stop") { model.cleanupSession.stop() }.disabled(model.cleanupSession.stopping)
                } else if let id = model.lastUninstallSessionID, let session = model.cleanupSession.sessions.first(where: { $0.id == id }),
                          model.canUndo(session) {
                    Button("Undo") { model.undo(session) }.disabled(model.mutationUnavailableReason != nil)
                }
                Button("Activity") { model.destination = .history }.nativeCheckTarget("Activity")
            }.padding(12).background(.bar)
    }
}
