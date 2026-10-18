import SwiftUI
import LumaCore

struct ItemList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    let items: [CleanupItem]
    @ViewState private var expanded: Set<String> = []
    @ViewState private var displayLimit = 200
    private var visible: [CleanupItem] { items.filter { !model.isIgnored($0) } }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.prefix(displayLimit))) { item in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 13) {
                        Toggle("Select \(item.name)", isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }))
                            .toggleStyle(.checkbox).labelsHidden().disabled(model.busy)
                        SymbolTile(symbol: item.category.symbol, size: 34)
                        Button { toggle(item.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(item.displayPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Details for \(item.name)")
                            .accessibilityValue(expanded.contains(item.id) ? "Expanded" : "Collapsed")
                        SafetyBadge(level: item.safety)
                        Text(formatBytes(item.bytes)).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 84, alignment: .trailing)
                        Button { toggle(item.id) } label: { Image(systemName: expanded.contains(item.id) ? "chevron.up" : "info.circle").foregroundStyle(.secondary).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help("Inspect rule and removal consequences")
                            .accessibilityLabel("\(expanded.contains(item.id) ? "Hide" : "Show") removal consequences for \(item.name)")
                    }.padding(.vertical, 14)
                    if expanded.contains(item.id) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.explanation).font(.system(size: 12)).lineSpacing(3)
                            Label(item.consequence, systemImage: "arrow.uturn.backward").font(.system(size: 11)).foregroundStyle(.secondary)
                            if let owner = item.ownerBundleID {
                                Text("Owner: \(owner)").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Text("Rule: \(item.ruleID)\nPath: \(item.url.path)\nMatched: \(item.scannedAt.formatted())\nIdentity: \(item.identity.device):\(item.identity.inode)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                Button("Always ignore") { model.ignore(item) }
                            }.buttonStyle(.bordered).controlSize(.small)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 12)
                    }
                }
                if item.id != items.last?.id { Divider() }
            }
            if visible.count > displayLimit {
                Button("Show next \(min(200, visible.count - displayLimit)) items") { displayLimit += 200 }
                    .buttonStyle(.glass).padding(.vertical, 15)
            }
        }
    }
    private func toggle(_ id: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
    }
}

struct SelectionBar: View {
    @Environment(AppModel.self) private var model
    let items: [CleanupItem]
    var logicalBytes: (([CleanupItem]) -> Int64)? = nil
    private var selected: [CleanupItem] { items.filter { model.selected.contains($0.id) && !model.isIgnored($0) } }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle").foregroundStyle(Palette.accent)
            Text("\(selected.count) selected").font(.system(size: 12, weight: .medium))
            Text("Up to \(formatBytes(logicalBytes?(selected) ?? selected.reduce(0) { $0 + $1.bytes }))").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .help("The final logical size is verified in review, counting shared hard-linked content once.")
            Spacer()
            if !selected.isEmpty { Button("Deselect all") { model.selected = [] }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary) }
            PrimaryButton(title: "Review selection", symbol: "arrow.right") { model.review(items) }.disabled(selected.isEmpty || model.busy)
        }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var confirmed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 15) {
                SymbolTile(symbol: "trash", size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.reviewPlan?.source == .applicationReset ? "Review application reset" : "A final look before Trash").font(.system(size: 22, weight: .semibold))
                    Text("\(model.reviewItems.count) items · \(formatBytes(model.reviewPlan?.logicalBytes ?? 0))").foregroundStyle(.secondary)
                }
            }
            Text("Luma will validate each path again, then move your selection to the macOS Trash. Space is reclaimed when Trash is emptied in Finder.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            if model.reviewPlan?.source == .applicationReset {
                Text("The app bundle stays installed. Quit the app and its helpers before continuing. Active apps may recreate these paths; Restore and Undo never overwrite a recreated destination. Review completed moves in Activity and inspect again afterward.").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            Text("Logical size counts hard-linked content once across this selection.").font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.reviewItems) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(item.name).fontWeight(.semibold); Spacer(); SafetyBadge(level: item.safety); Text(formatBytes(item.bytes)).monospacedDigit() }
                            Text(item.displayPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(item.consequence).font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.frame(maxHeight: 280)
            Toggle("I reviewed these items and understand their removal consequences.", isOn: $confirmed).font(.system(size: 11))
            HStack {
                Button("Go back") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                PrimaryButton(title: "Move to Trash", symbol: "trash") { model.moveToTrash() }.disabled(!confirmed || model.busy || model.reviewPlan == nil)
            }
        }.padding(30).frame(width: 600)
    }
}
