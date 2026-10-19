import SwiftUI
import LumaCore

extension AppModel {
    func ensureApplicationInventory(refresh: Bool = false) {
        guard !applicationInventory.isBusy, !operationBusy,
              !(scanSessions.isBusy && [.applications, .overview].contains(scanTarget)),
              refresh || !completedScans.contains(.applications) else { return }
        let runner = scanRunner
        let request = ScanRequest(.applications)
        applicationInventory.start(request) { emit in try await runner(request, emit) }
    }

    func pauseApplicationReads() {
        applications = visibleApplications
        applicationInventory.cancel()
        if residueDiscovery.isBusy { residueDiscovery.cancel(); residueEntered = false }
        if [.applications, .overview, .footprint, .leftovers].contains(scanTarget) {
            if let queued = scanSessions.queuedRequest, ![.applications, .overview, .footprint, .leftovers].contains(queued.target) {
                let runner = scanRunner
                scanSessions.start(queued) { emit in try await runner(queued, emit) }
            } else { scanSessions.cancel() }
        }
    }

    func waitForApplicationReads() async throws {
        while residueDiscovery.isBusy || applicationInventory.isBusy || (scanSessions.isBusy && [.applications, .overview, .footprint, .leftovers].contains(scanTarget)) {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    var mutationUnavailableReason: String? {
        if recoveryLoading { return "Loading Activity…" }
        if let journalError { return journalError }
        if !recoveryNotices.isEmpty { return "Resolve interrupted operations in Activity first." }
        if operationBusy || cleanupSession.isRunning { return "Wait for the current operation." }
        if journal == nil { return "Activity is unavailable. Open Activity to retry." }
        return nil
    }

    func uninstallUnavailableReason(_ app: ApplicationRecord) -> String? {
        if !ApplicationRelationships.supports(app.bundleID) { return "Protected or unsupported application." }
        let owner = app.bundleID.lowercased()
        if runningApplicationIDs.contains(where: { $0.lowercased() == owner || $0.lowercased().hasPrefix(owner + ".") })
            || runningApplicationURLs.contains(where: { Filesystem.isWithin($0, root: app.url) }) {
            return "Quit the app and its helpers, then retry."
        }
        return mutationUnavailableReason
    }

    func uninstall(_ app: ApplicationRecord) {
        guard let journal else { uninstallMessages[app.id] = mutationUnavailableReason; return }
        guard uninstallUnavailableReason(app) == nil else { uninstallMessages[app.id] = uninstallUnavailableReason(app); return }
        // Capture the row and operation before the first suspension. Navigation has no effect on intent.
        let exclusions = ignored
        operationBusy = true
        uninstallingApp = app.id
        uninstallOutcome = nil
        uninstallMessages[app.id] = "Preparing Uninstall…"
        status = "Preparing Uninstall for \(app.name)…"
        // Preserve progressive rows when the sizing worker yields to this mutation.
        pauseApplicationReads()
        cleanupSession.run { [self] in
            defer { uninstallingApp = nil; finish() }
            var capturedPlan: CleanupPlan?
            var preparationPhase: CleanupPhase = .failed
            do {
                try await waitForApplicationReads()
                let home = uninstallHome
                let plan = try await offMain { try ApplicationUninstall.prepare(app, home: home, ignoredPaths: exclusions) }
                capturedPlan = plan
                lastUninstallSessionID = plan.id
                uninstallMessages[app.id] = plan.items.count == 1 ? "Moving the bundle; shared or unverified related data stays." : "Moving the bundle and verified exclusive caches, logs and settings."
                status = "Checking and moving \(app.name) to Trash…"
                _ = try await journal.execute(plan, context: { @MainActor [self] in
                    await plan.executionContext(ignoredPaths: ignored)
                }, onRecord: { @MainActor [self] record in
                    history.insert(record, at: 0)
                    if record.original == app.url {
                        dirtyResidueOwners([app.bundleID])
                        removedApplicationPaths.insert(app.id)
                        applications.removeAll { $0.id == app.id }
                    }
                    // Only observations overlapping confirmed moves become stale.
                    invalidateObservations(affected: [record.original])
                }, onProgress: { @MainActor [self] progress in cleanupSession.update(progress) })
            } catch {
                preparationPhase = error is CancellationError ? .stopped : .failed
                uninstallMessages[app.id] = error is CancellationError ? "Stopped before the next item." : error.localizedDescription
            }
            do { apply(try await journal.reconcile()) }
            catch { journalError = error.localizedDescription; apply(await journal.snapshot()) }
            if let plan = capturedPlan, let session = cleanupSession.sessions.first(where: { $0.id == plan.id }) {
                let moved = history.filter { $0.planID == plan.id }.count
                uninstallOutcome = "\(app.name): \(session.phase.label) · \(moved) moved · \(plan.items.count - moved) remaining"
                uninstallMessages[app.id] = session.detail ?? uninstallOutcome
            } else {
                uninstallOutcome = "\(app.name): \(preparationPhase.label) · \(uninstallMessages[app.id] ?? "Uninstall unavailable")"
            }
            status = uninstallOutcome ?? "Review Activity"
        }
    }

    func invalidateObservations(affected paths: [URL]) {
        func overlaps(_ url: URL) -> Bool {
            paths.contains { Filesystem.isWithin(url, root: $0) || Filesystem.isWithin($0, root: url) }
        }
        if cleanup.contains(where: { overlaps($0.url) }) { invalidateGeneratedFindings() }
        if footprint.contains(where: { overlaps($0.url) }) { invalidateApplicationFootprint() }
        let affectedResidues = leftovers.filter { overlaps($0.url) }
        for item in affectedResidues { residueSelection.removeValue(forKey: item.id) }
        if !affectedResidues.isEmpty {
            removeSelection(ids: Set(leftovers.filter { overlaps($0.url) }.map(\.id)), prefix: Destination.applications.rawValue + ApplicationTab.leftovers.rawValue)
            let previous = completedSnapshots[.leftovers]
            if let remaining = scanSessions.retainRemainingLeftovers(excluding: paths) {
                if let previous { retainSelection(from: previous, to: remaining, prefix: Destination.applications.rawValue + ApplicationTab.leftovers.rawValue) }
                completedSnapshots[.leftovers] = remaining
                leftovers.removeAll { overlaps($0.url) }; didScanLeftovers = true
            } else {
                leftovers.removeAll { overlaps($0.url) }
                completedSnapshots.removeValue(forKey: .leftovers)
                scanSessions.invalidateSnapshots(for: [.leftovers])
            }
        }
        if !affectedResidues.isEmpty { saveResidues() }
        if duplicates.contains(where: { $0.items.contains { overlaps($0.url) } }) {
            let invalid = duplicates.filter { $0.items.contains { overlaps($0.url) } }
            duplicates.removeAll { group in invalid.contains { $0.id == group.id } }
            clearDuplicateComparison(); duplicateChoice = nil
            removeSelection(ids: Set(invalid.flatMap { $0.items.map(\.id) }), prefix: Destination.duplicates.rawValue)
        }
        if let index = storageIndex, index.scopes.contains(where: { overlaps($0.root) }) {
            storageIndex = index.removing(paths)
            storageSelection = storageSelection.filter { id in
                guard let node = index.nodes[id] else { return false }
                return !overlaps(node.url)
            }
            saveStorage()
        }
        if let root = downloadsRoot, overlaps(root) { invalidateDownloads() }
        if let root = projectRoot, overlaps(root) { invalidateProjects() }
    }

    func canUndo(_ session: CleanupSession) -> Bool {
        history.contains { record in
            guard record.planID == session.id, !record.restored, record.identity?.location != nil else { return false }
            guard let eligibility = undoEligibility[record.id]?.eligibility else { return true }
            return ![.missing, .unavailable, .restored].contains(eligibility)
        }
    }

    func refreshRestoredApplications(_ records: [CleanupRecord]) async {
        let restored = records.filter { $0.restored && $0.original.pathExtension == "app" }
        guard !restored.isEmpty else { return }
        for record in restored {
            let url = record.original
            do {
                // A confirmed durable Restore must refresh its row even when Stop arrived after the native move.
                let app = try await Task.detached(priority: .utility) {
                    try ApplicationScanner.restoredRecord(at: url, verifiedBytes: record.bytes)
                }.value
                dirtyResidueOwners([app.bundleID])
                removedApplicationPaths.remove(app.id)
                applications.removeAll { $0.id == app.id }; applications.append(app)
            } catch { status = "Restored app; inventory metadata unavailable: \(error.localizedDescription)" }
        }
    }
}
