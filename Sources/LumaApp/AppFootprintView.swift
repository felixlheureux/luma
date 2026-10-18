import SwiftUI
import LumaCore

struct AppFootprintView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var search = ""
    @ViewState private var largestFirst = false
    private var resetMode: Bool { model.reviewingApplicationReset }
    @ViewState private var resetBlocked = true
    @ViewState private var checkingActivity = false
    @ViewState private var activityMessage = "Check that the app and its helpers have stopped."
    @ViewState private var knownOwners: Set<String> = []
    let app: ApplicationRecord
    private struct Group: Identifiable {
        let id: String
        let entries: [FootprintEntry]
        let bytes: Int64
        let consequence: String?
    }
    private var groups: [Group] {
        guard let footprint = model.footprintDetails else { return [] }
        if resetMode {
            var preceding: [CleanupItem] = []
            return ResetCategory.allCases.map { category in
                let entries = footprint.entries.filter { ResetCategory.category(for: $0.relationship) == category }
                let items = entries.compactMap(\.item)
                let bytes = footprint.accounting.bytes(for: preceding + items) - footprint.accounting.bytes(for: preceding)
                preceding += items
                return Group(id: category.rawValue, entries: filtered(entries), bytes: bytes, consequence: category.consequence)
            }
        }
        return FootprintCategory.allCases.map { category in
            Group(id: category.rawValue, entries: entries(category), bytes: footprint.bytes(in: category),
                  consequence: category == .bundle ? "Select the bundle explicitly to uninstall. Related files remain separate choices." : nil)
        }
    }
    private var eligibleItems: [CleanupItem] {
        model.footprint.filter { !resetMode || $0.ruleID == "application.exact-related" }
    }
    private func filtered(_ entries: [FootprintEntry]) -> [FootprintEntry] {
        let matches = entries.filter { search.isEmpty || $0.relationship.url.path.localizedCaseInsensitiveContains(search) }
        return largestFirst ? matches.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) } : matches
    }
    private func checkActivity() async {
        checkingActivity = true; resetBlocked = true; knownOwners = []
        defer { checkingActivity = false }
        let context = await CleanupExecutionContext.current()
        do {
            let app = app
            let owners = try await Task.detached(priority: .utility) {
                try ApplicationReset.knownOwners(app: app, home: FileManager.default.homeDirectoryForCurrentUser)
            }.value
            knownOwners = owners
            try await Task.detached(priority: .utility) {
                try ApplicationReset.validateActivity(app: app, home: FileManager.default.homeDirectoryForCurrentUser, context: context)
            }.value
            resetBlocked = false
            activityMessage = "App and known helpers are stopped. Luma checks again before every move."
        } catch {
            activityMessage = error.localizedDescription
        }
    }
    private func requestQuit() {
        let owner = app.bundleID.lowercased()
        for running in NSWorkspace.shared.runningApplications {
            if running.bundleIdentifier.map({ knownOwners.contains($0.lowercased()) || $0.lowercased() == owner }) == true || running.bundleURL.map({ $0.path.hasPrefix(app.url.path + "/") }) == true {
                _ = running.terminate()
            }
        }
        activityMessage = "Quit requested. Save any work or respond to app prompts, then check again."
        resetBlocked = true
    }
    private var inspecting: Bool { model.scanSessions.isBusy && model.scanTarget == .footprint }
    private func entries(_ category: FootprintCategory) -> [FootprintEntry] {
        let entries = model.footprintDetails?.entries.filter {
            $0.relationship.category == category && (search.isEmpty || $0.relationship.url.path.localizedCaseInsensitiveContains(search))
        } ?? []
        return largestFirst ? entries.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) } : entries
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "macwindow").font(.system(size: 36)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(resetMode ? "Reset \(app.name)" : app.name).font(.system(size: 24, weight: .semibold))
                    Text(app.bundleID).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if inspecting { Button("Cancel inspection") { model.cancel() }.buttonStyle(.glass) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if inspecting {
                ScanSessionPanel(onlyTarget: .footprint)
                Text("Inspecting footprint… Selection becomes available when inspection finishes.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if let footprint = model.footprintDetails {
                HStack {
                    Eyebrow(text: footprint.isComplete ? "Inspected footprint" : "Inspected footprint · partial")
                    Spacer()
                    Text(formatBytes(resetMode ? footprint.accounting.bytes(for: eligibleItems) : footprint.inspectedBytes)).font(.system(size: 24, weight: .semibold))
                }
                Text(resetMode ? "Reset covers supported exact app data only. The bundle and shared groups are excluded. Totals include filtered data; category totals count shared hard-linked content once, in the order shown." : "Covers exact identifiers, verified containers and explicit ownership mappings. Other locations and shared groups are excluded. Totals cover the whole inspection, including filtered paths. Category totals count shared hard-linked content once, in the order shown.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if resetMode {
                    Text("Choose only the data you intend to reset. The app stays installed. Other app data is a separate choice and may contain valuable files or sign-in state. Active apps can recreate paths and block a non-overwriting Restore. Activity records each move; inspect again after completion.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activityMessage).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Request normal quit") { requestQuit() }.disabled(checkingActivity || knownOwners.isEmpty)
                            Button(checkingActivity ? "Checking…" : "Check again") { Task { await checkActivity() } }.disabled(checkingActivity)
                        }
                    }
                }
                CompletedScanCaption(target: .footprint)
                HStack {
                    TextField("Filter paths in this footprint", text: $search).textFieldStyle(.roundedBorder)
                    Toggle("Largest first", isOn: $largestFirst).toggleStyle(.checkbox)
                }.font(.system(size: 11))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            let relationships = group.entries
                            if !relationships.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(group.id).font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Text("Inspected " + formatBytes(group.bytes)).font(.system(size: 11)).monospacedDigit()
                                    }
                                    if let consequence = group.consequence { Text(consequence).font(.system(size: 11)).foregroundStyle(.secondary) }
                                    ItemList(items: relationships.compactMap(\.item))
                                    ForEach(relationships.filter { $0.item == nil }) { entry in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(entry.relationship.url.lastPathComponent)
                                                Spacer()
                                                Text(entry.state == .missing ? "Not present" : "Size unavailable").foregroundStyle(.secondary)
                                            }
                                            Text(entry.relationship.url.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                            if entry.state != .missing {
                                                Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                                if entry.state == .blocked {
                                                    Button("Open Full Disk Access settings") {
                                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                                                    }.font(.system(size: 11))
                                                }
                                            }
                                        }.padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                    }
                }.frame(height: resetMode ? 280 : 340)
                HStack {
                    Text("\(eligibleItems.filter { model.selected.contains($0.id) }.count) selected · \(formatBytes(footprint.accounting.bytes(for: eligibleItems.filter { model.selected.contains($0.id) })))").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !model.selected.isEmpty { Button("Deselect all") { model.selected = [] } }
                }
            } else {
                Text("No completed footprint inspection. Retry to measure related data.").foregroundStyle(.secondary)
            }
            HStack {
                if !resetMode {
                    Button("Review reset") { model.reviewingApplicationReset = true }
                        .disabled(model.busy || model.footprintDetails == nil || !ApplicationRelationships.supports(app.bundleID))
                } else {
                    Button("Back to footprint") { model.reviewingApplicationReset = false; model.selected = [] }
                }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                Button("Inspect again") { let wasReset = resetMode; model.inspect(app); model.reviewingApplicationReset = wasReset; if wasReset { Task { await checkActivity() } } }.disabled(model.busy)
                Spacer()
                PrimaryButton(title: "Review selection", symbol: "arrow.right") {
                    let selected = eligibleItems.filter { model.selected.contains($0.id) }
                    dismiss()
                    Task { try? await Task.sleep(for: .milliseconds(250)); model.review(selected, source: resetMode ? .applicationReset : .applications, resetApplication: resetMode ? app : nil) }
                }.disabled(!eligibleItems.contains { model.selected.contains($0.id) } || model.busy || (resetMode && resetBlocked))
            }
        }.padding(28).frame(width: 780)
        .onAppear { model.selected = []; if resetMode { Task { await checkActivity() } } }
        .onChange(of: resetMode) { _, value in model.selected = []; if value { Task { await checkActivity() } } }
        .onChange(of: search) { _, _ in model.selected = [] }
        .onDisappear { if inspecting { model.cancel() } }
    }
}
