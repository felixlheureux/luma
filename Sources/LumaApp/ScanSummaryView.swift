import SwiftUI
import LumaCore

struct ScanProgressCard: View {
    let progress: ScanProgress
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking \(progress.current)").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(progress.completedRules) / \(progress.totalRules) checks").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(progress.completedRules), total: Double(max(1, progress.totalRules))).tint(Palette.accent)
                HStack {
                    Text(progress.entries > 0 ? "\(progress.entries.formatted()) items checked in this folder" : "Checking supported locations")
                    Spacer()
                    Text("\(formatBytes(progress.bytes)) found so far").monospacedDigit()
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

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
                    Button("Scan coverage") { showingCoverage = true }.buttonStyle(.glass)
                }
                HStack(spacing: 18) {
                    ForEach([ItemCategory.caches, .developer, .logs]) { category in
                        let items = report.items.filter { $0.category == category }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(category.rawValue, systemImage: category.symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(formatBytes(items.reduce(0) { $0 + $1.bytes })).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                            Text("\(items.count) locations found").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if exclusions > 0 {
                    Label("\(exclusions) locations were skipped. Their contents are not included in these totals.", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Sizes reflect this scan. Actual savings can differ, and disk space is recovered after Trash is emptied.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $showingCoverage) { ScanCoverageView(report: report) }
    }
}

private struct ScanCoverageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: ScanReport
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
            if report.coverage.contains(where: { $0.state == .blocked }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Some locations need permission").font(.system(size: 13, weight: .semibold))
                    Text("Review access in macOS Settings if you want those locations included, then scan again. Luma does not change your permissions.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button("Files & folders") { model.openSettings("com.apple.preference.security?Privacy_FilesAndFolders") }
                        Button("Full Disk Access") { model.openSettings("com.apple.preference.security?Privacy_AllFiles") }
                    }.buttonStyle(.glass).controlSize(.small)
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Palette.peach.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack {
                Picker("Show", selection: $filter) {
                    Text("All locations (\(report.coverage.count))").tag(Optional<CoverageState>.none)
                    ForEach(CoverageState.allCases, id: \.self) { state in
                        Text("\(state.rawValue) (\(report.coverage.filter { $0.state == state }.count))").tag(Optional(state))
                    }
                }.frame(width: 300)
                Spacer()
                Button("Scan again") { dismiss(); model.destination = .clean; model.runScan(.clean) }.buttonStyle(.glass).disabled(model.busy)
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
                        }.padding(.vertical, 14)
                        Divider()
                    }
                    if rows.isEmpty { Text("No locations in this group.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40) }
                }
            }
        }.padding(26).frame(width: 700, height: 600)
    }
}
