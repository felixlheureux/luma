import SwiftUI
import LumaCore

extension CleanupPhase {
    var label: String {
        switch self {
        case .validating: "Validating selection"
        case .moving: "Checking and moving current item"
        case .stopping: "Stopping"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .partial: "Partially completed"
        case .failed: "Failed"
        case .recoveryNeeded: "Recovery needed"
        }
    }
}

struct CleanupProgressPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let operation = model.cleanupSession
        if operation.isRunning {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(operation.stopping ? "Stopping after the current operation…" : operation.progress?.phase.label ?? "Preparing operation…").font(.headline)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(Int(max(0, context.date.timeIntervalSince(operation.startedAt ?? context.date))))s elapsed")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button("Stop") { operation.stop() }.buttonStyle(.glass).foregroundStyle(.primary).disabled(operation.stopping)
                    }
                    if let progress = operation.progress {
                        Text(progress.current?.lastPathComponent ?? "Checking the complete reviewed selection")
                        ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                        Text(progress.phase == .validating
                             ? "\(progress.completed) of \(progress.total) items validated · nothing moved yet"
                             : "\(progress.completed) of \(progress.total) items moved")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let detail = operation.detail {
                        Text(detail.phase).font(.caption)
                        if !detail.current.isEmpty { Text(detail.current).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        if detail.entries > 0 {
                            Text("\(detail.entries) entries checked · \(formatBytes(detail.bytes)) inspected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("An in-flight move finishes and is recorded before Stop takes effect. Review Activity for completed moves and any recovery needed.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CleanupSessionHistory: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ForEach(model.cleanupSession.sessions.reversed()) { session in
            let records = model.history.filter { $0.planID == session.id }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.source.displayName).font(.headline)
                            Text("\(session.date.formatted()) · \(session.phase.label)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Review undo") { model.reviewUndo(session) }.buttonStyle(.glass).foregroundStyle(.primary)
                            .disabled(model.busy || records.isEmpty || !model.recoveryNotices.isEmpty)
                    }
                    Text("\(records.count) moved · \(session.paths.count - records.count) not confirmed moved · \(formatBytes(records.reduce(Int64(0)) { $0 + ($1.accountedBytes ?? $1.bytes) })) logical size moved of \(formatBytes(session.logicalBytes)) reviewed")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(records.filter(\.restored).count) restored. Moving to Trash does not establish physical space reclaimed.").font(.caption).foregroundStyle(.secondary)
                    if let detail = session.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("Items and outcomes") {
                        ForEach(session.paths, id: \.self) { path in
                            let record = records.first { $0.original == path }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(path.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                Text(record.map { $0.restored ? "Restored" : "Moved to Trash" } ?? (session.phase == .recoveryNeeded ? "Not confirmed moved; review recovery" : (session.blockedPath == path ? "Blocked: \(session.detail ?? "Review Activity")" : "Unattempted")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                    ForEach(model.cleanupSession.undoAttempts.filter { $0.sessionID == session.id }) { attempt in
                        DisclosureGroup("Undo · \(attempt.phase.label) · \(attempt.outcomes.filter(\.restored).count) restored of \(attempt.recordIDs.count)") {
                            ForEach(attempt.recordIDs, id: \.self) { id in
                                let record = records.first { $0.id == id }
                                let outcome = attempt.outcomes.first { $0.recordID == id }
                                Text("\(record?.original.lastPathComponent ?? "Item"): \(outcome?.detail ?? "Not attempted or awaiting recovery")").font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension CleanupSource {
    var displayName: String {
        switch self {
        case .generatedData: "Generated data cleanup"
        case .applications: "Application cleanup"
        case .applicationReset: "Application reset"
        case .leftovers: "Leftover cleanup"
        case .storage: "Storage cleanup"
        case .duplicates: "Duplicate cleanup"
        case .developerProjects: "Project cleanup"
        case .downloads: "Downloads review"
        }
    }
}

struct UndoReviewSheet: View {
    @Environment(AppModel.self) private var model
    let review: UndoReview
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review undo").font(.title2).fontWeight(.semibold)
            Text("\(review.eligibleIDs.count) eligible of \(review.items.count) items. Only eligible items in this review will be restored, with identity and destination checked again.").font(.callout)
            Text("Restore runs in reverse path order and stops between items. Parents must still exist. Conflicts stay untouched; recovery is not an atomic rollback.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(review.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.record.original.lastPathComponent).fontWeight(.semibold)
                            Text(item.record.original.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Original folder") { NSWorkspace.shared.open(item.record.original.deletingLastPathComponent()) }
                                Button("Trash in Finder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
                            }.buttonStyle(.glass).controlSize(.small).foregroundStyle(.primary)
                        }.padding(12)
                    }
                }
            }.contentMargins(.trailing, 14, for: .scrollContent).frame(maxHeight: 330)
            HStack {
                Button("Cancel") { model.cleanupSession.undoReview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                PrimaryButton(title: "Restore \(review.eligibleIDs.count) eligible items", symbol: "arrow.uturn.backward") { model.undoSession() }
                    .disabled(review.eligibleIDs.isEmpty || model.busy)
            }
        }.padding(28).frame(width: 620)
    }
}
