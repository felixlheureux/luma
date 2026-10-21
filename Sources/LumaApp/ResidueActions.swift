import SwiftUI
import LumaCore

extension AppModel {
    func dirtyRestoredResidueOwners(_ records: [CleanupRecord]) {
        for record in records where record.planSource == .leftovers {
            if let owner = LeftoverScanner.owner(at: record.original, home: uninstallHome) { dirtyResidueOwners([owner]) }
        }
    }
    func mergeHiddenAppData(_ observations: [HiddenAppDataObservation]) {
        var rows = Dictionary(hiddenAppData.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for observation in observations { rows[observation.id] = observation }
        hiddenAppData = Array(rows.values).sorted { $0.id < $1.id }
    }
    var visibleHiddenAppData: [HiddenAppDataObservation] {
        var rows = Dictionary(hiddenAppData.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if residueDiscovery.isBusy {
            for observation in residueDiscovery.session?.preview.hiddenAppData ?? [] { rows[observation.id] = observation }
        }
        return rows.values.filter { observation in
            !ignored.contains { Filesystem.isWithin(observation.url, root: URL(fileURLWithPath: $0)) }
                && (residueOwnerFilter == nil || observation.owner == residueOwnerFilter)
        }.sorted { $0.id < $1.id }
    }
    func reviewRemainingData() {
        guard let owner = remainingDataOwner else { return }
        residueOwnerFilter = owner; residueHiddenOnly = false
        destination = .residues
        ensureResidues()
    }
    func dirtyResidueOwners(_ owners: Set<String>) {
        residueDirtyOwners.formUnion(HiddenAppData.affectedOwners(owners))
    }

    func residueEligible(_ item: CleanupItem) -> Bool {
        if let observation = visibleHiddenAppData.first(where: { $0.id == item.id }), observation.state != .absent { return false }
        return item.ruleID == "application.leftover.exact-identifier" && item.safety == .review
            && item.ownerBundleID.map(ApplicationRelationships.supports) == true && !isIgnored(item)
    }
    var visibleResidues: [CleanupItem] {
        var rows = Dictionary(leftovers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if residueDiscovery.isBusy {
            for item in residueDiscovery.session?.preview.items ?? [] { rows[item.id] = item }
        }
        return rows.values.filter { !isIgnored($0) }.sorted { $0.id < $1.id }
    }
    var residueActionUnavailableReason: String? {
        mutationUnavailableReason ?? (selectedResidues.contains { !residueEligible($0) }
            ? "A selected owner's status changed. Deselect it or refresh before continuing." : nil)
    }
    var selectedResidues: [CleanupItem] {
        visibleResidues.filter { residueSelection[$0.id] != nil }
            .compactMap { residueSelection[$0.id] }
    }
    func selectResidue(_ item: CleanupItem, selected: Bool) {
        if selected { if residueEligible(item) { residueSelection[item.id] = item } }
        else { residueSelection.removeValue(forKey: item.id) }
    }
    func ensureResidues(refresh: Bool = false) {
        guard !operationBusy, !residueLoading, !residueDiscovery.isBusy else { return }
        guard !residueEntered || refresh || !residueDirtyOwners.isEmpty else { return }
        residueEntered = true; residueLoading = true
        Task {
            defer { residueLoading = false }
            if !residueLoaded {
                residueLoaded = true
                do {
                    if let saved = try await residueStore.load(), leftovers.isEmpty {
                        leftovers = saved.items; hiddenAppData = saved.hiddenAppData ?? []; residueSavedAt = saved.savedAt
                        residueCoverage = saved.notices
                        residueStatus = "Saved observations · checking current ownership…"
                    }
                } catch { residueStatus = "Saved observations unavailable: \(error.localizedDescription)" }
            }
            guard !operationBusy else { residueEntered = false; return }
            let runner = scanRunner
            let owners = !refresh && (residueSavedAt != nil || residueOwnerFilter != nil) && !residueDirtyOwners.isEmpty ? residueDirtyOwners : nil
            residueDirtyOwners = []
            let request = ScanRequest(.leftovers, residueOwners: owners)
            residueDiscovery.start(request) { emit in try await runner(request, emit) }
        }
    }
    func saveResidues() {
        let saved = ResidueObservations(items: leftovers, savedAt: residueSavedAt ?? Date(),
            complete: residueCoverage.isEmpty, notices: residueCoverage, hiddenAppData: hiddenAppData)
        let store = residueStore
        Task { do { try await store.save(saved) } catch { residueStatus = "Display results could not be saved: \(error.localizedDescription)" } }
    }
    func trashResidues() {
        guard let journal, residueActionUnavailableReason == nil else { residueOutcome = residueActionUnavailableReason; return }
        let captured = selectedResidues
        guard !captured.isEmpty else { return }
        let exclusions = ignored, home = uninstallHome
        operationBusy = true; residueMoving = true; residueOutcome = "Preparing selected residues…"
        residueDiscovery.cancel(); pauseApplicationReads()
        let detailEmitter = cleanupSession.detailEmitter
        cleanupSession.run { [self] in
            defer { residueMoving = false; finish() }
            var plan: CleanupPlan?
            var preparationError: String?
            do {
                try await waitForApplicationReads()
                while residueDiscovery.isBusy { try await Task.sleep(for: .milliseconds(20)) }
                let prepared = try await offMain { try ResidueObservations.prepare(captured, home: home, ignoredPaths: exclusions) }
                plan = prepared; lastResidueSessionID = prepared.id
                _ = try await journal.execute(prepared, context: { @MainActor [self] in
                    await prepared.executionContext(ignoredPaths: ignored)
                }, onRecord: { @MainActor [self] record in
                    history.insert(record, at: 0)
                    residueSelection.removeValue(forKey: record.original.path)
                    invalidateObservations(affected: [record.original])
                    saveResidues()
                }, onProgress: { @MainActor [self] progress in
                    cleanupSession.update(progress)
                    residueOutcome = "Checking and moving selected residues…"
                }, onDetail: detailEmitter)
            } catch {
                preparationError = error is CancellationError ? "Stopped before the next item." : error.localizedDescription
                if plan == nil && !(error is CancellationError) {
                    dirtyResidueOwners(Set(captured.compactMap(\.ownerBundleID)))
                }
            }
            do { apply(try await journal.reconcile()) }
            catch { journalError = error.localizedDescription; apply(await journal.snapshot()) }
            if let plan, let session = cleanupSession.sessions.first(where: { $0.id == plan.id }) {
                let moved = history.filter { $0.planID == plan.id }.count
                residueOutcome = "\(session.phase.label) · \(moved) moved · \(plan.items.count - moved) remaining. \(session.detail ?? "")"
            } else { residueOutcome = preparationError ?? "No items moved." }
            status = residueOutcome ?? "Review Activity"
        }
    }
}
