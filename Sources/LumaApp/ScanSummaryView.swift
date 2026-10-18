import AppKit
import SwiftUI
import LumaCore

struct ScanSummaryCard: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport
    @ViewState private var showingCoverage = false
    private var exclusions: Int { report.coverage.filter { $0.state == .blocked || $0.state == .skipped }.count }
    private var readable: Int { report.coverage.filter { $0.state == .found || $0.state == .empty }.count }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    SymbolTile(symbol: exclusions == 0 ? "checkmark.circle" : "info.circle", tint: exclusions == 0 ? Palette.mint : Palette.peach, size: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exclusions == 0 ? "Your scan, at a glance" : "Scan finished with exclusions").font(.system(size: 16, weight: .semibold))
                        Text("\(Rules.generated.count) checks completed · \(readable) locations read · \(String(format: "%.1f", report.duration))s")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Scan coverage") { showingCoverage = true }.buttonStyle(.glass).foregroundStyle(.primary)
                }
                HStack(spacing: 18) {
                    ForEach([ItemCategory.caches, .developer, .logs]) { category in
                        let items = report.items.filter { $0.category == category }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(category.rawValue, systemImage: category.symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(formatBytes(report.generatedAccounting.bytes(for: items))).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                            Text("\(items.count) locations found").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if exclusions > 0 {
                    Label("\(exclusions) locations were skipped. Their contents are not included in these totals.", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Category totals can share hard-linked content and may not add up to the unique overall total. Physical savings can differ; space is recovered after Trash is emptied.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $showingCoverage) { ScanCoverageView(report: report, request: model.snapshot(for: .generatedData)?.request ?? .init(.generatedData)) }
    }
}

private struct ScanCoverageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: ScanReport
    let request: ScanRequest
    @ViewState private var filter: CoverageState?
    private var rows: [ScanCoverage] { report.coverage.filter { filter == nil || $0.state == filter } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Scan coverage").font(.system(size: 24, weight: .semibold))
                    Text("See what was checked, absent, or left out of the totals.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
            }
            ScanPermissionGuidance(target: request.target, blocked: report.coverage.contains { $0.state == .blocked })
            HStack {
                Picker("Show", selection: $filter) {
                    Text("All locations (\(report.coverage.count))").tag(Optional<CoverageState>.none)
                    ForEach(CoverageState.allCases, id: \.self) { state in
                        Text("\(state.rawValue) (\(report.coverage.filter { $0.state == state }.count))").tag(Optional(state))
                    }
                }.frame(width: 300)
                Spacer()
                Button("Retry same scope") { dismiss(); model.startScan(request) }.buttonStyle(.glass).disabled(!model.canStartScan)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(row.title).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(row.state == .found ? formatBytes(row.bytes) : row.state.rawValue)
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(row.state == .blocked || row.state == .skipped ? Palette.peach : .secondary)
                            }
                            Text(row.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if row.accessCapability != nil {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (row.path as NSString).expandingTildeInPath)])
                                }.buttonStyle(.glass).accessibilityLabel("Reveal \(row.title) in Finder")
                            }
                        }.padding(.vertical, 14)
                        Divider()
                    }
                    if rows.isEmpty { Text("No locations in this group.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40) }
                }
            }.contentMargins(.trailing, 14, for: .scrollContent)
        }.padding(26).frame(width: 700, height: 600)
    }
}
