import SwiftUI
import LumaCore

/// Shared comparison and explicit selection flow for folder and Downloads scans.
struct DuplicateGroupsView: View {
    @Environment(AppModel.self) private var model
    let groups: [DuplicateGroup]
    let source: CleanupSource
    @ViewState private var query = ""
    @ViewState private var minimumBytes: Int64 = 0
    @ViewState private var order = DuplicateOrder.savings
    @ViewState private var displayLimit = 100
    private var visible: [DuplicateGroup] {
        // An ignored member invalidates the whole visible choice, never silently
        // shrinks the group or promotes an excluded copy to keeper evidence.
        DuplicateReview.groups(groups.filter { !$0.items.contains(where: model.isIgnored) }, query: query, minimumBytes: minimumBytes, order: order)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Filter full paths", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Filter duplicate groups by full path")
                Picker("Savings", selection: $minimumBytes) {
                    Text("Any size").tag(Int64(0)); Text("At least 100 MB").tag(Int64(100_000_000)); Text("At least 1 GB").tag(Int64(1_000_000_000))
                }.frame(width: 180)
                Picker("Order", selection: $order) { ForEach(DuplicateOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 220)
            }.font(.system(size: 11))
            Text("\(visible.count) matching complete groups. Nothing selected automatically. Dates use modification time; ties use full path order.").font(.system(size: 11)).foregroundStyle(.secondary)
            if visible.isEmpty {
                ContentUnavailableView("No matching exact duplicates", systemImage: "doc.on.doc", description: Text("Try another filter or scan again. Names and visual resemblance never establish exact matches."))
            }
            ForEach(Array(visible.prefix(displayLimit))) { group in
                DuplicateGroupCard(group: group, source: source).id("duplicate-group-" + group.id)
            }
            if visible.count > displayLimit { Button("Show 100 more groups") { displayLimit += 100 }.buttonStyle(.glass) }
        }
        .onChange(of: query) { _, _ in reset() }
        .onChange(of: minimumBytes) { _, _ in reset() }
        .onChange(of: order) { _, _ in reset() }
        .onDisappear { model.clearDuplicateComparison(); model.duplicateChoice = nil }
        .sheet(isPresented: Binding(get: { model.duplicateChoice != nil && model.duplicateChoiceSource == source }, set: { if !$0 { model.duplicateChoice = nil } })) {
            if let choice = model.duplicateChoice { DuplicateKeeperSheet(choice: choice) }
        }
    }
    private func reset() {
        model.selected.subtract(groups.flatMap(\.items).map(\.id)); displayLimit = 100
        model.duplicateChoice = nil; model.clearDuplicateComparison()
    }
}

private struct DuplicateGroupCard: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup
    let source: CleanupSource
    @ViewState private var limit = 100
    private var comparing: Bool { model.duplicateComparisonGroup == group.id }
    var body: some View {
        Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(group.items.count) identical copies · \(formatBytes(group.recoverable)) possible savings").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(comparing ? "Close comparison" : "Compare copies") {
                        if comparing { model.clearDuplicateComparison() } else { model.compareDuplicateGroup(group, source: source) }
                    }.buttonStyle(.glass).disabled(model.busy)
                }
                HStack {
                    ForEach(DuplicateKeeperPreference.allCases, id: \.self) { preference in
                        Button("Preview: \(preference.rawValue.lowercased())") {
                            if let keeper = DuplicateReview.keeper(in: group, preference: preference) { model.prepareDuplicateKeeper(group: group, keeper: keeper, source: source) }
                        }.buttonStyle(.glass).disabled(model.busy)
                    }
                }.font(.system(size: 11))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(Array(DuplicateReview.members(group).prefix(limit))) { item in
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle("Move \(item.name) to Trash", isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }))
                                .toggleStyle(.checkbox)
                                .disabled(model.busy || (!model.selected.contains(item.id) && group.items.filter { !model.selected.contains($0.id) }.count <= 1))
                                .accessibilityLabel("Select for Trash review: \(item.url.path)")
                                .accessibilityHint("At least one copy must remain. Nothing moves until final review and confirmation.")
                            Text(item.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text("\(formatBytes(item.bytes)) · Modified \(item.identity.modified.formatted())").font(.system(size: 11)).foregroundStyle(.secondary)
                            if comparing { comparison(item) }
                            Button("Preview keeping this copy") { model.prepareDuplicateKeeper(group: group, keeper: item, source: source) }
                                .buttonStyle(.glass).font(.system(size: 11)).disabled(model.busy)
                                .accessibilityLabel("Preview keeping \(item.url.path)")
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if group.items.count > limit { Button("Show 100 more copies") { limit += 100 }.buttonStyle(.glass) }
                if comparing && group.items.count > 100 { Text("Inline previews are limited to the first 100 paths per group. Full paths, modification dates and keeper choices remain available for every copy.").font(.caption).foregroundStyle(.secondary) }
                Text("One path per filesystem object. Hard links do not count as extra copies; shared bytes may remain after moving a path. Every location may still be needed.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func comparison(_ item: CleanupItem) -> some View {
        if let value = model.duplicateComparisons[item.id] {
            Text("Created \(value.created.formatted()) · \(value.linkCount == 1 ? "Independent file" : "Hard-linked file (\(value.linkCount) paths)")").font(.system(size: 11)).foregroundStyle(.secondary)
            switch value.preview {
            case .text(let text, let truncated):
                ScrollView { Text(verbatim: text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 140)
                    .accessibilityLabel("Text preview for \(item.url.path)")
                if truncated { Text("First 64 KiB only").font(.caption) }
            case .png(let data):
                if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 170).accessibilityLabel("Image preview for \(item.url.path)") }
            case .unavailable(let reason): Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else if let reason = model.duplicateComparisonErrors[item.id] {
            Text(reason).font(.system(size: 11)).foregroundStyle(Palette.peach)
        } else if DuplicateReview.members(group).prefix(100).contains(where: { $0.id == item.id }) {
            ProgressView("Reading local comparison…").controlSize(.small)
        }
    }
}

struct DuplicateKeeperSheet: View {
    @Environment(AppModel.self) private var model
    let choice: DuplicateKeeperChoice
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preview keeper choice").font(.title2).fontWeight(.semibold)
            Text("Keep this copy").font(.headline)
            Text(choice.keeper.url.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Text("Select \(choice.removals.count) \(choice.removals.count == 1 ? "copy" : "copies") for later Trash review").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(choice.removals) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Text(formatBytes(item.bytes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.trailing, 16).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 260)
            Text("Applying replaces this group's selection. Files stay in place until you review and confirm Trash. Changed or missing copies require a new scan.").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.duplicateChoice = nil }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button("Apply selection") { model.applyDuplicateKeeper() }.buttonStyle(.glassProminent).disabled(model.busy)
            }
        }.padding(24).frame(width: 650)
    }
}
