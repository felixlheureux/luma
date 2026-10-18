import SwiftUI
import LumaCore

struct ScanSessionPanel: View {
    @Environment(AppModel.self) private var model
    var onlyTarget: ScanTarget?
    private var visibleSession: ScanSession? {
        guard let session = model.scanSessions.session else { return nil }
        if let onlyTarget { return session.request.target == onlyTarget ? session : nil }
        return model.scanSessions.isBusy || session.request.target == model.currentScanTarget ? session : nil
    }
    var body: some View {
        if let session = visibleSession {
            Surface(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if model.scanSessions.isBusy { ProgressView().controlSize(.small) }
                        Text(model.scanSessions.statusText).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(Int(max(0, (session.endedAt ?? context.date).timeIntervalSince(session.startedAt))))s elapsed")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Text(session.request.scope).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if session.phase == .running {
                        Text(session.progress.current.isEmpty ? session.progress.phase : session.progress.current).font(.system(size: 12)).lineLimit(1)
                        if let total = session.progress.total {
                            ProgressView(value: Double(min(session.progress.completed, total)), total: Double(max(1, total)))
                            Text("\(session.progress.completed) / \(total) checks · \(session.progress.entries) entries · \(formatBytes(session.progress.bytes)) inspected")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        } else { Text("\(session.progress.entries) entries · \(formatBytes(session.progress.bytes)) inspected").font(.system(size: 10)).foregroundStyle(.secondary) }
                        if session.stalled {
                            Text("The current filesystem call has not reported progress. An expensive read can take time. Cancel requests a safe stop when the call returns.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if case .stopping = session.phase {
                        Text("Cancellation has been requested. The next scan waits until this worker returns; preview results cannot be selected.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let queued = model.scanSessions.queuedRequest {
                        Text("Queued: \(queued.scope)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if session.phase != .completed && session.phase != .completedWithExclusions {
                        ScanPreviewRows(preview: session.preview)
                    }
                    if session.phase.isTerminal && session.phase != .completed && session.phase != .completedWithExclusions {
                        Text(model.snapshot(for: session.request.target) == nil
                             ? "This preview cannot be used for cleanup. No completed snapshot is available."
                             : "The previous completed snapshot is retained below. This preview cannot be used for cleanup.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Retry same scope") { model.startScan(session.request) }.buttonStyle(.glass).disabled(!model.canStartScan)
                        ScanPermissionGuidance(target: session.request.target, blocked: session.failureCoverage == .blocked || session.preview.coverage.contains { $0.state == .blocked })
                    }
                }
            }
        }
    }
}

private struct ScanPreviewRows: View {
    let preview: ScanPreview
    var body: some View {
        if !preview.items.isEmpty || !preview.duplicates.isEmpty || !preview.applications.isEmpty {
            DisclosureGroup("Read-only preview · \(preview.items.count) locations · \(preview.applications.count) apps · \(preview.duplicates.count) duplicate groups") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(preview.items.sorted { $0.bytes > $1.bytes }.prefix(20)) { item in
                        HStack { Text(item.name).lineLimit(1); Spacer(); Text(formatBytes(item.bytes)).monospacedDigit() }
                    }
                    ForEach(preview.applications.sorted { $0.name < $1.name }.prefix(20)) { app in
                        HStack {
                            Text(app.name).lineLimit(1); Spacer()
                            Text(app.sizeState == .pending ? "Size pending" : app.sizeState == .unavailable ? "Size unavailable" : formatBytes(app.bytes))
                        }
                    }
                    ForEach(preview.duplicates.prefix(8)) { group in
                        Text("\(group.items.count) verified copies · \(formatBytes(group.recoverable)) potential savings")
                    }
                    if preview.truncated { Text("Preview is limited. The finished scan keeps its complete result set.") }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.system(size: 11))
        }
        if !preview.notices.isEmpty { Text("\(preview.notices.count) exclusions reported so far").font(.system(size: 11)).foregroundStyle(.secondary) }
    }
}

struct CompletedScanCaption: View {
    @Environment(AppModel.self) private var model
    let target: ScanTarget
    var body: some View {
        if let snapshot = model.snapshot(for: target) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Completed snapshot · \(snapshot.finishedAt.formatted(date: .abbreviated, time: .standard)) · \(snapshot.request.scope)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                if !snapshot.result.report.notices.isEmpty || !snapshot.result.report.isComplete {
                    HStack {
                        Label("Limited coverage · excluded locations are absent from totals", systemImage: "info.circle")
                        Spacer()
                        Button("Retry same scope") { model.startScan(snapshot.request) }.disabled(!model.canStartScan)
                    }.font(.system(size: 11))
                    DisclosureGroup("Scan coverage") {
                        ForEach(Array(snapshot.result.report.notices.prefix(50).enumerated()), id: \.offset) { _, notice in
                            Text(notice).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.font(.system(size: 11))
                }
                ScanPermissionGuidance(target: target, blocked: snapshot.result.report.coverage.contains { $0.state == .blocked })
            }
        }
    }
}

struct ScanPermissionGuidance: View {
    @Environment(AppModel.self) private var model
    let target: ScanTarget
    let blocked: Bool
    var body: some View {
        if blocked {
            VStack(alignment: .leading, spacing: 8) {
                Text(target == .storage || target == .duplicates
                     ? "You can continue with readable results. For excluded folders, review Files & Folders access or choose the same folder again, then retry."
                     : "You can continue with readable results. Grant access only to the locations you want included, then retry this scope.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Files & Folders settings") { model.openSettings("com.apple.preference.security?Privacy_FilesAndFolders") }
                    if [.generatedData, .overview, .leftovers, .footprint].contains(target) {
                        Button("Full Disk Access settings") { model.openSettings("com.apple.preference.security?Privacy_AllFiles") }
                    }
                }.buttonStyle(.glass).controlSize(.small)
            }
        }
    }
}
