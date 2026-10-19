import SwiftUI
import LumaCore

extension AppModel {
    func openCore(_ target: Destination) {
        switch target {
        case .downloads, .projects, .backups:
            destination = .storage
            storageMode = "Largest files"
            storageLocation = [.downloads, .projects].contains(target) ? uninstallHome.appendingPathComponent(target == .projects ? "Projects" : "Downloads").path : "All locations"
        case .clean, .optimizer: destination = .maintenance
        case .privacy: showSettingsWindow?()
        case .applications: applicationTab = .installed; destination = .applications
        case .residues: destination = .residues
        default: destination = target
        }
    }
    func configureStorageDiscovery() {
        storageDiscovery.onChange = { [weak self] in
            guard let self, self.storageAcceptAutomatic, let session = self.storageDiscovery.session else { return }
            if self.storageDiscovery.isBusy {
                self.storageStatus = "Discovering · \(session.progress.entries) entries checked · previous observations stay visible"
                if !self.storageRetainsCompletedResults, let partial = session.preview.storageIndex,
                   self.storagePreviewSession != session.id || self.storagePreviewRevision != session.preview.storageRevision {
                    self.storagePreviewSession = session.id
                    self.storagePreviewRevision = session.preview.storageRevision
                    self.publishStorage(partial, completed: false)
                }
            } else if ![.completed, .completedWithExclusions].contains(session.phase) {
                self.storageStatus = (session.detail ?? "Discovery stopped") + " · previous observations retained"
            }
        }
        storageDiscovery.onComplete = { [weak self] snapshot in
            guard let self, self.storageAcceptAutomatic, let index = snapshot.result.storageIndex else { return }
            self.publishStorage(index)
            self.storageStatus = "\(index.nodes.count) observations · \(index.scannedAt.formatted(date: .omitted, time: .shortened)) · partial local and iCloud coverage"
            self.saveStorage()
        }
    }

    func publishStorage(_ index: StorageIndex, completed: Bool = true) {
        let old = storageIndex
        if old?.rootID != index.rootID { storageSelection = []; storageBack = []; storageForward = [] }
        else {
            storageSelection = storageSelection.filter { id in
                guard let before = old?.nodes[id], let after = index.nodes[id] else { return false }
                return before.sameObservation(as: after) && after.isComplete
            }
        }
        storageIndex = index
        storageRoot = index.isDiscovery ? nil : index.scope.root
        storageExpectedVolume = index.scope.volume.identity
        if storageDirectory.flatMap({ index.nodes[$0] }) == nil { storageDirectory = index.rootID }
        if completed {
            let capturedRoot = index.rootID, capturedDate = index.scannedAt
            storageVolumes.observe(index.scope) { [weak self] in
                guard let self, self.storageIndex?.rootID == capturedRoot, self.storageIndex?.scannedAt == capturedDate else { return }
                // The old displayed scope may disappear while a different target is running.
                // Its callback never cancels another controller/generation.
                self.invalidateStorage()
                self.storageStatus = "Observed volume unavailable · refresh for current storage"
            }
        }
    }

    /// Opening Storage reads only Luma's saved metadata, never the filesystem tree.
    func loadSavedStorage() {
        #if DEBUG
        guard storageRootsOverride != nil || !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) else { return }
        #endif
        guard storageIndex == nil, !storageLoading, !storageDiscovery.isBusy else { return }
        storageLoading = true
        let generation = storageCacheGeneration
        Task { [self] in
            defer { storageLoading = false }
            if let saved = try? await storageStore.load(), storageCacheGeneration == generation, storageIndex == nil {
                publishStorage(saved)
                storageStatus = "Saved observations · \(saved.scannedAt.formatted(date: .abbreviated, time: .shortened)) · scan to update"
            }
        }
    }

    func ensureStorage(refresh: Bool = false) {
        #if DEBUG
        guard storageRootsOverride != nil || !CommandLine.arguments.contains(where: { $0.hasPrefix("--check-") }) else { return }
        #endif
        guard !operationBusy, !storageLoading, !storageDiscovery.isBusy else { return }
        guard !storageEntered || refresh else { return }
        storageEntered = true; storageLoading = true
        Task { [self] in
            defer { storageLoading = false }
            if storageIndex == nil, let saved = try? await storageStore.load() {
                publishStorage(saved)
                storageStatus = "Saved observations · checking changes…"
            }
            guard !operationBusy else { storageEntered = false; return }
            storageAcceptAutomatic = true
            if scanSessions.isBusy && scanTarget == .storage { scanSessions.cancel() }
            while scanSessions.isBusy && scanTarget == .storage { try? await Task.sleep(for: .milliseconds(20)) }
            _ = storageChanges?.take() // A full walk covers changes pending before it starts.
            let home = uninstallHome, roots = storageRootsOverride, exclusions = ignored, limit = storageLimit
            let request = ScanRequest(.storage)
            storageRetainsCompletedResults = storageIndex != nil
            // Local observations stay unchanged until the next user-requested scan.
            storageWatch?.cancel(); storageWatch = nil; storageChanges = nil
            storageDiscovery.start(request) { emit in
                let index = try StorageDiscovery.scan(home: home, roots: roots, limit: limit, ignoredPaths: exclusions, emit: emit)
                return ScanResult(storageIndex: index)
            }
        }
    }

    func rescanStorageWithLargerLimit() {
        guard !operationBusy, !storageLoading, !storageDiscovery.isBusy,
              let next = storageIndex?.largerScanLimit(current: storageLimit) else { return }
        storageLimit = next
        ensureStorage(refresh: true)
    }

    func refreshStorage(paths: [URL]) {
        guard let current = storageIndex, current.isDiscovery else { return }
        let home = uninstallHome, exclusions = ignored, limit = storageLimit
        storageRetainsCompletedResults = true
        storageDiscovery.start(.init(.storage)) { emit in
            let updated = try StorageDiscovery.refresh(current, paths: paths, home: home, ignoredPaths: exclusions, limit: limit, emit: emit)
            return ScanResult(storageIndex: updated)
        }
    }

    func saveStorage() {
        guard let index = storageIndex else { return }
        let store = storageStore, generation = storageCacheGeneration
        Task {
            guard storageCacheGeneration == generation else { return }
            do { try await store.save(index) }
            catch { storageStatus = "Results could not be saved: \(error.localizedDescription)" }
        }
    }

    func navigateStorage(_ id: String) {
        guard storageIndex?.nodes[id]?.canNavigate == true, storageDirectory != id else { return }
        if let previous = storageDirectory { storageBack.append(previous) }
        storageForward = []; storageFocus = nil; storageDirectory = id
    }
    func storageHistory(back: Bool) {
        let target = back ? storageBack.popLast() : storageForward.popLast()
        guard let target, storageIndex?.nodes[target] != nil else { return }
        if let current = storageDirectory { if back { storageForward.append(current) } else { storageBack.append(current) } }
        storageDirectory = target; storageFocus = nil
    }
    func selectStorage(_ node: StorageNode, selected: Bool) {
        if !selected { storageSelection.remove(node.id); return }
        guard storageEligible(node), let index = storageIndex else { return }
        if storageSelection.contains(where: { id in index.nodes[id].map { Filesystem.isWithin(node.url, root: $0.url) } ?? false }) { return }
        storageSelection = storageSelection.filter { id in index.nodes[id].map { !Filesystem.isWithin($0.url, root: node.url) } ?? false }
        storageSelection.insert(node.id)
    }
    func storageEligible(_ node: StorageNode) -> Bool {
        node.isComplete && Date().timeIntervalSince(node.observedAt) < 1800 && node.url.isFileURL && !node.isPackage
            && SafetyEngine(home: uninstallHome, ignoredPaths: ignored).permitsManualSelection(at: node.url, authorizedRoots: [uninstallHome])
            && storageIndex?.scopes.contains(where: { Filesystem.isWithin(node.url, root: $0.root) && !$0.volume.isReadOnly }) == true
    }
    var storageUnavailableReason: String? {
        if let reason = mutationUnavailableReason { return reason }
        if let index = storageIndex, Date().timeIntervalSince(index.scannedAt) >= 1800 { return "Observations are over 30 minutes old. Refresh before moving files." }
        guard !storageSelection.isEmpty else { return "Select local files to move to Trash." }
        guard let index = storageIndex, storageSelection.allSatisfy({ index.nodes[$0].map(storageEligible) == true }) else {
            return "Selection includes stale, ignored or read-only items. Deselect or refresh."
        }
        return nil
    }

    // Optional legacy review remains callable for debug/secondary inspection.
    func reviewStorage() {
        guard let index = storageIndex, !index.scope.inspectionOnly, !operationBusy else { return }
        let ids = storageSelection, home = uninstallHome, exclusions = ignored, groups = knownStorageDuplicates
        operationBusy = true
        scanTask = Task {
            defer { finish() }
            do { reviewPlan = try await offMain { try index.prepare(ids: ids, home: home, ignoredPaths: exclusions, duplicateGroups: groups) }; showingReview = true }
            catch { self.error = error.localizedDescription }
        }
    }
    var knownStorageDuplicates: [DuplicateGroup] {
        var groups = Dictionary(duplicates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for group in downloadsInventory?.duplicates ?? [] { groups[group.id] = group }
        return Array(groups.values)
    }
    func trashStorage() {
        guard let journal, storageUnavailableReason == nil, let index = storageIndex else { storageOutcome = storageUnavailableReason; return }
        let ids = storageSelection, home = uninstallHome, exclusions = ignored, groups = knownStorageDuplicates
        operationBusy = true; storageMoving = true; storageOutcome = "Preparing selected files…"
        storageDiscovery.cancel()
        if scanSessions.isBusy && scanTarget == .storage { scanSessions.cancel() }
        cleanupSession.run { [self] in
            defer { storageMoving = false; finish() }
            var plan: CleanupPlan?
            var failure: String?
            do {
                while storageDiscovery.isBusy || (scanSessions.isBusy && scanTarget == .storage) { try await Task.sleep(for: .milliseconds(20)) }
                let prepared = try await offMain { try index.prepare(ids: ids, home: home, ignoredPaths: exclusions, duplicateGroups: groups) }
                plan = prepared; lastStorageSessionID = prepared.id
                _ = try await journal.execute(prepared, context: { @MainActor [self] in await prepared.executionContext(ignoredPaths: ignored) },
                    onRecord: { @MainActor [self] record in
                        history.insert(record, at: 0); storageSelection.remove(record.original.path)
                        invalidateObservations(affected: [record.original])
                    }, onProgress: { @MainActor [self] progress in
                        cleanupSession.update(progress); storageOutcome = "Checking and moving selected files…"
                    })
            } catch { failure = error is CancellationError ? "Stopped before the next item." : error.localizedDescription }
            do { apply(try await journal.reconcile()) }
            catch { journalError = error.localizedDescription; apply(await journal.snapshot()) }
            if let plan, let session = cleanupSession.sessions.first(where: { $0.id == plan.id }) {
                let moved = history.filter { $0.planID == plan.id }.count
                storageOutcome = "\(session.phase.label) · \(moved) moved · \(plan.items.count - moved) remaining. \(session.detail ?? "")"
            } else { storageOutcome = failure ?? "No items moved." }
            status = storageOutcome ?? "Review Activity"
        }
    }
}
