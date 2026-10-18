import SwiftUI
import LumaCore

extension AppModel {
    func chooseSmartScope(_ target: ScanTarget) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Include folder"
        panel.message = "Include this folder in the next Smart Check. Nothing is selected for removal."
        guard panel.runModal() == .OK, let root = panel.url else { return }
        smartScopes[target] = root
    }

    func openSmartResult(_ target: ScanTarget) {
        guard let snapshot = smartSnapshots[target],
              snapshot.finishedAt >= (smartStartedAt ?? .distantFuture),
              completedSnapshots[target]?.sessionID == snapshot.sessionID,
              snapshot.result.smartCheckFailure == nil else { return }
        switch target {
        case .generatedData: destination = .clean
        case .applications: applicationTab = .installed; destination = .applications
        case .leftovers: applicationTab = .leftovers; destination = .applications
        case .developerProjects: destination = .projects
        case .downloads: destination = .downloads
        default: return
        }
    }
}

struct SmartCheckView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Smart Check", detail: "Read-only · review each result")
            Text("Completed checks appear as they finish. Totals stay in each review because categories may overlap. Personal files and potential leftovers need your judgment.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            DisclosureGroup("Optional folder checks for the next run") {
                ForEach([ScanTarget.developerProjects, .downloads], id: \.self) { target in
                    HStack {
                        Button("Choose \(target.title) folder…") { model.chooseSmartScope(target) }
                        Text(model.smartScopes[target]?.path ?? "Skipped · no folder chosen")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if model.smartScopes[target] != nil {
                            Button("Remove") { model.smartScopes.removeValue(forKey: target) }
                        }
                    }.font(.system(size: 11)).disabled(model.busy)
                }
            }.font(.system(size: 12))
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 10) {
                    ForEach(SmartCheck.targets, id: \.self) { target in
                        resultRow(target, now: context.date)
                    }
                    measurementRow(now: context.date)
                }
            }
            Text("Backup integrity, security, app updates and similar photos are not checked. No health score or automatic cleanup is produced.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ target: ScanTarget, now: Date) -> some View {
        let snapshot = model.smartSnapshots[target]
        let captured = model.scanRequests[.overview]
        let included = ![ScanTarget.downloads, .developerProjects].contains(target) || captured?.smartScopes[target] != nil
        let currentRun = snapshot.map { $0.finishedAt >= (model.smartStartedAt ?? .distantFuture) } ?? false
        let available = currentRun && snapshot?.result.smartCheckFailure == nil
            && snapshot?.sessionID == model.completedSnapshots[target]?.sessionID
        let invalidated = currentRun && snapshot?.result.smartCheckFailure == nil && !available
        let status = invalidated ? "Stale · check again" : !included ? "Skipped · no folder authorized" : SmartCheck.status(
            snapshot: snapshot, startedAt: model.smartStartedAt, phase: model.smartPhase, now: now)
        return Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(target.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let snapshot, currentRun {
                    Text("\(snapshot.request.scope) · \(snapshot.finishedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(evidence(snapshot)).font(.system(size: 12))
                    if invalidated { Text("Results changed or were invalidated. Run a new check.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Button("Open \(target.title) results") { model.openSmartResult(target) }
                        .buttonStyle(.glass).disabled(!available)
                } else {
                    Text(captured?.smartScopes[target]?.path ?? "Run Smart Check to inspect this category.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func evidence(_ snapshot: ScanSnapshot) -> String {
        let result = snapshot.result
        if let failure = result.smartCheckFailure { return failure }
        let exclusions = result.report.coverage.filter { [.blocked, .skipped].contains($0.state) }.count
        let detail: String
        switch snapshot.request.target {
        case .applications: detail = "\(result.applications.count) apps inventoried; related footprints are inspected separately."
        case .downloads: detail = "\(result.downloadsInventory?.files.count ?? 0) personal files to review; no files selected."
        default: detail = "\(result.report.items.count) locations to review; no items selected."
        }
        return detail + (exclusions > 0 ? " \(exclusions) excluded checks; open results for coverage." : "")
    }

    private func measurementRow(now: Date) -> some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage, memory and thermals").font(.system(size: 14, weight: .semibold))
                if let sample = model.smartMeasurement, let date = sample.sampledAt {
                    Text("This Mac · \(date.formatted(date: .abbreviated, time: .standard))\(now.timeIntervalSince(date) > 30 ? " · Stale sample" : "")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(sample.totalDisk > 0 ? "\(formatBytes(sample.availableDisk)) available of \(formatBytes(sample.totalDisk))." : "Storage capacity unavailable.")
                    Text("Memory pressure: \(sample.pressure). Thermals: \(sample.thermal). High RAM use alone does not indicate pressure.")
                    Button("Open live system measurements") { model.destination = .system }.buttonStyle(.glass)
                } else { Text("Not checked · waiting for a measurement and a Smart Check.") }
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
