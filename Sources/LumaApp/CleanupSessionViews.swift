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
                        if progress.phase != .validating { ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total))) }
                        Text(progress.phase == .validating
                             ? "\(progress.completed) of \(progress.total) items validated · nothing moved yet"
                             : "\(progress.completed) of \(progress.total) items \(operation.restoring ? "restored" : "moved")")
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
                        if model.canUndo(session) {
                            Button("Undo") { model.undo(session) }.buttonStyle(.glass).foregroundStyle(.primary)
                                .disabled(model.mutationUnavailableReason != nil)
                        } else { Text(records.isEmpty ? "Nothing to restore" : records.allSatisfy(\.restored) ? "Restored" : "Unavailable · inspect items").font(.caption) }
                    }
                    Text("\(records.count) moved · \(session.paths.count - records.count) not confirmed moved · \(formatBytes(records.reduce(Int64(0)) { $0 + ($1.accountedBytes ?? $1.bytes) })) logical size moved of \(formatBytes(session.logicalBytes)) reviewed")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(records.filter(\.restored).count) restored. Moving to Trash does not establish physical space reclaimed.").font(.caption).foregroundStyle(.secondary)
                    if let reason = model.mutationUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    if let message = model.undoMessages[session.id] { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if let detail = session.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("Items and outcomes") {
                        ForEach(session.paths, id: \.self) { path in
                            let record = records.first { $0.original == path }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(path.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                Text(record.map { $0.permanentlyRemoved == true ? "Permanently removed or partially emptied; Restore unavailable" : ($0.restored ? "Restored" : "Moved to Trash") } ?? (session.phase == .recoveryNeeded ? "Not confirmed moved; review recovery" : (session.blockedPath == path ? "Blocked: \(session.detail ?? "Review Activity")" : "Unattempted")))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let record, !record.restored, record.permanentlyRemoved != true {
                                    if let eligibility = model.undoEligibility[record.id] {
                                        Text(eligibility.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let message = model.restoreMessages[record.id] { Text(message).font(.caption).foregroundStyle(.secondary) }
                                    Button("Restore") { model.restore(record) }
                                        .disabled(model.mutationUnavailableReason != nil || record.identity?.location == nil || record.permanentlyRemoved == true)
                                }
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
