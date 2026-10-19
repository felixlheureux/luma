import AppKit
import LumaCore

extension AppModel {
    func refreshMaintenanceTrash() {
        guard !maintenanceTrashLoading, !maintenanceEmptying else { return }
        maintenanceTrashLoading = true
        let reader = maintenanceTrashReader
        Task {
            defer { maintenanceTrashLoading = false }
            do {
                maintenanceTrash = try await offMain { try reader() }
                if let journal {
                    maintenanceHistory = await journal.trashRemovalHistory()
                }
                if let previous = maintenanceHistory.last {
                    maintenanceTrashStatus = previous.summary + ". Refresh observed current contents; nothing was retried."
                } else { maintenanceTrashStatus = "Only supported unchanged entries can be permanently removed." }
            } catch { maintenanceTrash = nil; maintenanceTrashStatus = "Local Trash unavailable: \(error.localizedDescription). Open Trash in Finder to review access." }
        }
    }

    func openLocalTrash() {
        do {
            let root = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            if !NSWorkspace.shared.open(root) { maintenanceTrashStatus = "Finder could not open the local Trash." }
        } catch { maintenanceTrashStatus = "Local Trash unavailable: \(error.localizedDescription)" }
    }

    func emptyMaintenanceTrash(_ captured: TrashReview) {
        guard let journal, mutationUnavailableReason == nil else { maintenanceTrashStatus = mutationUnavailableReason ?? "Activity unavailable."; return }
        operationBusy = true; maintenanceEmptying = true
        maintenanceTrashStatus = "Checking approved Trash contents…"
        status = maintenanceTrashStatus
        cleanupSession.run { [self] in
            defer { operationBusy = false; maintenanceEmptying = false }
            do {
                let result = try await journal.emptyTrash(captured, progress: { @MainActor [self] in maintenanceTrashStatus = $0; status = $0 })
                maintenanceTrashStatus = result.summary + ". Other bins, excluded and changed contents remain."
            } catch { maintenanceTrashStatus = "Empty Trash stopped: \(error.localizedDescription). Review remaining contents; no automatic retry." }
            status = maintenanceTrashStatus
            maintenanceHistory = await journal.trashRemovalHistory()
            apply(await journal.snapshot())
            let reader = maintenanceTrashReader
            maintenanceTrash = try? await offMain { try reader() }
        }
    }

    func trashMaintenanceCaches(_ captured: [CleanupItem]) {
        guard let journal, mutationUnavailableReason == nil else { maintenanceCacheStatus = mutationUnavailableReason ?? "Activity unavailable."; return }
        guard !captured.isEmpty else { maintenanceCacheStatus = "Select supported generated data first."; return }
        let exclusions = ignored
        operationBusy = true; maintenanceCleaning = true; maintenanceCacheStatus = "Checking approved generated data…"
        cleanupSession.run { [self] in
            defer { maintenanceCleaning = false; finish() }
            var plan: CleanupPlan?
            do {
                let prepared = try await offMain {
                    let prepared = try CleanupPlan(items: captured, ignoredPaths: exclusions, source: .generatedData)
                    return prepared
                }
                plan = prepared
                _ = try await journal.execute(prepared, context: { @MainActor [self] in
                    await prepared.executionContext(ignoredPaths: ignored)
                }, onRecord: { @MainActor [self] record in
                    history.insert(record, at: 0)
                    retainMaintenanceGenerated(after: record.original)
                    invalidateObservations(affected: [record.original])
                }, onProgress: { @MainActor [self] progress in
                    cleanupSession.update(progress)
                    maintenanceCacheStatus = "\(progress.phase.label) · \(progress.completed) of \(progress.total)"
                })
                maintenanceCacheStatus = "Approved generated data moved to Trash. Restore from Activity."
            } catch { maintenanceCacheStatus = "Stopped: \(error.localizedDescription). Completed moves remain in Activity." }
            apply(await journal.snapshot())
            if let plan, let session = cleanupSession.sessions.first(where: { $0.id == plan.id }) {
                let moved = history.filter { $0.planID == plan.id }.count
                maintenanceCacheStatus = "\(session.phase.label) · \(moved) moved · \(plan.items.count - moved) remaining. \(session.detail ?? "")"
            }
            status = maintenanceCacheStatus
        }
    }
}
