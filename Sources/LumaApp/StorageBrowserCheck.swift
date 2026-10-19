#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Generated home and injected mover only; never scans personal folders or uses real Trash.
    func checkStorageBrowser(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/discovery-\(UUID())")
            let downloads = home.appendingPathComponent("Downloads")
            let denied = downloads.appendingPathComponent("Unreadable")
            var checkedWindow: NSWindow?, originalFrame: NSRect?
            let originalRunner = model.scanRunner
            var report: [String: Any] = ["realTrashInvoked": false, "personalFoldersScanned": false]
            defer {
                model.storageWatch?.cancel(); model.storageChanges = nil
                model.storageDiscovery.cancel(); model.scanSessions.cancel(); model.scanRunner = originalRunner
                if let window = checkedWindow, let frame = originalFrame {
                    window.setFrame(frame, display: true)
                    if !window.frameAutosaveName.isEmpty { window.saveFrame(usingName: window.frameAutosaveName) }
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                try? FileManager.default.removeItem(at: home)
                NSApp.terminate(nil)
            }
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(30)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard predicate() else { throw LumaError.rejected("Native Storage fixture timed out") }
            }
            @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            @MainActor func marker(_ window: NSWindow, _ name: String) -> NSView? {
                window.contentView.flatMap { descendants($0).first { $0.identifier?.rawValue == "luma-check-" + name } }
            }
            @MainActor func clickMarker(_ window: NSWindow, _ name: String) throws {
                guard let view = marker(window, name) else { throw LumaError.rejected("Missing Storage control: " + name) }
                let frame = view.convert(view.bounds, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: frame.midX, y: frame.midY),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw LumaError.rejected("No Storage pointer event") }
                    NSApp.postEvent(event, atStart: false)
                }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                let preparation = Task.detached(priority: .utility) {
                    for path in ["Downloads/a/b/c", "Downloads/Empty", "Downloads/Unreadable", "Library/CloudStorage", ".Trash", "Downloads/Sample.bundle", "Documents"] {
                        try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
                    }
                    for i in 0..<180 { try Data("bounded fixture".utf8).write(to: home.appendingPathComponent("Documents/item-\(i)")) }
                    for i in 0..<20 { try Data(repeating: UInt8(i), count: 30 + i).write(to: downloads.appendingPathComponent("entry-\(i).dmg")) }
                    let count = Int(ProcessInfo.processInfo.environment["LUMA_STORAGE_QA_FILES"] ?? "1000") ?? 1000
                    for i in 0..<count { try Data("nested fixture".utf8).write(to: downloads.appendingPathComponent("a/b/c/file-\(i)")) }
                    try Data("hidden".utf8).write(to: downloads.appendingPathComponent(".hidden"))
                    try Data("package".utf8).write(to: downloads.appendingPathComponent("Sample.bundle/content"))
                    try Data("unreadable".utf8).write(to: denied.appendingPathComponent("content"))
                    try Data("provider fixture".utf8).write(to: home.appendingPathComponent("Library/CloudStorage/content"))
                    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
                }
                try await preparation.value
                model.showMainWindow?()
                try await Task.sleep(for: .milliseconds(100))
                report["launchWindows"] = NSApp.windows.map { ["class": $0.className, "frame": NSStringFromRect($0.frame), "visible": String($0.isVisible), "canBecomeMain": String($0.canBecomeMain)] }
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.frame.width >= 600 && $0.frame.height >= 400 }) else { throw LumaError.rejected("No native Storage window") }
                checkedWindow = window; originalFrame = window.frame
                window.setContentSize(NSSize(width: 1200, height: 850))
                window.makeKeyAndOrderFront(nil); NSApp.activate()
                try await Task.sleep(for: .milliseconds(200))
                let trash = home.appendingPathComponent(".Trash")
                let journal = try CleanupJournal(home: home, trashMover: { source in
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: source, to: destination); return destination
                })
                try await model.installFixtureJournal(journal)
                model.uninstallHome = home; model.ignored = []; model.authorizedRoots = []
                model.storageRootsOverride = [home]; model.storageStore = StorageObservationStore(home: home)
                model.storageLimit = 200_000
                model.openCore(.storage)
                model.loadSavedStorage()
                try await wait { !model.storageLoading }
                try await Task.sleep(for: .milliseconds(250))
                report["noScanOnOpen"] = model.storageIndex == nil && model.storageDiscovery.session == nil
                    && model.storageChanges == nil && model.storageWatch == nil
                let cold = Date()
                var maxMainActorDelay: TimeInterval = 0
                let heartbeat = Task { @MainActor in
                    var previous = Date()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                        let now = Date(); maxMainActorDelay = max(maxMainActorDelay, now.timeIntervalSince(previous)); previous = now
                    }
                }
                defer { heartbeat.cancel() }
                model.ensureStorage()
                try await wait { model.storageIndex != nil }
                report["firstResultsSeconds"] = Date().timeIntervalSince(cold)
                try await wait { !model.storageDiscovery.isBusy && !model.storageLoading }
                guard let index = model.storageIndex else { throw LumaError.rejected("Missing requested inventory") }
                report["discoverySeconds"] = Date().timeIntervalSince(cold)
                heartbeat.cancel()
                report["maxMainActorDelaySeconds"] = maxMainActorDelay
                report["nodes"] = index.nodes.count
                report["requestedScanWithoutPicker"] = index.isDiscovery && model.authorizedRoots.isEmpty
                report["partialCoverage"] = index.nodes[index.rootID]?.isComplete == false
                report["providerExcluded"] = index.nodes[home.appendingPathComponent("Library/CloudStorage").path]?.isComplete == false
                report["unreadablePartial"] = index.nodes[denied.path]?.isComplete == false
                report["nothingSelected"] = model.storageSelection.isEmpty
                let cloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                let states: [CloudStorageMetadata.State] = [.local, .onlineOnly, .unknown]
                let cloudItems = states.map { state in
                    CloudStorageObservation(url: cloudRoot.appendingPathComponent(state.rawValue), isDirectory: false,
                        metadata: CloudStorageMetadata(state: state, source: state == .unknown ? .index : .filesystem,
                            observedAt: Date(), logicalBytes: 800_000_000, allocatedBytes: state == .local ? 4096 : nil))
                }
                let cloudIndex = index.includingCloud(.init(observations: cloudItems, notice: "Synthetic cloud metadata · partial coverage"))
                model.publishStorage(cloudIndex)
                report["cloudMetadataVisible"] = cloudItems.allSatisfy { cloudIndex.nodes[$0.url.path]?.cloud?.state == $0.metadata.state }
                report["cloudCleanupRejected"] = cloudItems.allSatisfy { item in
                    guard let node = cloudIndex.nodes[item.url.path] else { return false }
                    return !model.storageEligible(node) && (try? cloudIndex.prepare(ids: [node.id], home: home, ignoredPaths: [])) == nil
                }
                report["cloudBytesExcluded"] = cloudIndex.nodes[index.rootID]?.bytes == index.nodes[index.rootID]?.bytes
                    && cloudIndex.selectedBytes(Set(cloudItems.map { $0.url.path })) == 0
                model.storageMode = "Largest files"
                try await Task.sleep(for: .milliseconds(200))
                try saveScanCheckWindow(window, path: output + "-cloud.png")
                model.publishStorage(index)
                model.storageMode = "Explore"; model.navigateStorage(downloads.path)
                try await Task.sleep(for: .milliseconds(250))
                try saveScanCheckWindow(window, path: output + "-explore.png")
                let leaf = downloads.appendingPathComponent("entry-0.dmg")
                guard let node = index.nodes[leaf.path] else { throw LumaError.rejected("Missing leaf") }
                model.selectStorage(node, selected: true)
                model.scanRunner = { _, _ in
                    try await Task.sleep(for: .milliseconds(100))
                    return ScanResult(duplicates: [])
                }
                model.startScan(.init(.duplicates, root: downloads))
                try await wait { !model.scanSessions.isBusy }
                report["unrelatedDuplicateCompletionPreservesSelection"] = model.storageSelection == [leaf.path]
                model.scanRunner = originalRunner
                let navigationSession = model.storageDiscovery.session?.id
                for path in ["a", "a/b", "a/b/c"] { model.navigateStorage(downloads.appendingPathComponent(path).path) }
                model.storageMode = "Largest files"; model.storageSearch = "file-999"
                report["selectionSurvivesNavigationAndFilters"] = model.storageSelection == [leaf.path] && model.storageIndex?.rootID == index.rootID
                    && model.storageIndex?.nodes[leaf.path]?.sameObservation(as: node) == true
                model.storageHistory(back: true); model.storageHistory(back: false)
                report["cachedHistory"] = model.storageDirectory == downloads.appendingPathComponent("a/b/c").path && model.storageDiscovery.session?.id == navigationSession
                let hiddenID = downloads.appendingPathComponent(".hidden").path
                guard let hiddenNode = index.nodes[hiddenID] else { throw LumaError.rejected("Missing hidden fixture") }
                model.selectStorage(hiddenNode, selected: true)
                model.storageLocation = home.appendingPathComponent("Documents").path
                model.storageFilter = "Selected"; model.storageShowHidden = false
                try await Task.sleep(for: .milliseconds(250))
                let selectedQuery = StorageListingQuery(largestFiles: true, directory: model.storageDirectory,
                    filter: "Selected", showHidden: false, search: model.storageSearch, location: model.storageLocation,
                    sort: "Name", selection: model.storageSelection)
                let selectedRows = try await Task.detached { try index.listing(selectedQuery) }.value
                let captured = try await Task.detached { try index.prepare(ids: Set(selectedRows.map(\.id)), home: home, ignoredPaths: []) }.value
                report["selectedIgnoresBrowsingFilters"] = Set(selectedRows.map(\.id)) == model.storageSelection
                    && Set(captured.items.map(\.id)) == model.storageSelection
                    && marker(window, "storage-row-" + leaf.path) != nil && marker(window, "storage-row-" + hiddenID) != nil
                model.ignored = [hiddenID]
                report["ineligibleSelectionVisibleAndBlocked"] = model.storageUnavailableReason != nil
                    && marker(window, "storage-row-" + hiddenID) != nil
                try await Task.sleep(for: .milliseconds(150))
                if let footer = marker(window, "Activity"), let content = window.contentView {
                    let rect = footer.convert(footer.bounds, to: content)
                    report["selectedFooterVisible"] = content.bounds.contains(rect)
                    report["selectedFooterFrame"] = NSStringFromRect(rect)
                } else { report["selectedFooterVisible"] = false }
                try saveScanCheckWindow(window, path: output + "-selected.png")
                try clickMarker(window, "storage-select-" + hiddenID)
                try await Task.sleep(for: .milliseconds(150))
                report["ineligibleSelectionCanDeselect"] = model.storageSelection == [leaf.path]
                model.ignored = []; model.storageSelection = [leaf.path]
                model.storageFilter = "All items"; model.storageLocation = "All locations"; model.storageSearch = ""
                model.storageMode = "Explore"; model.navigateStorage(downloads.path)
                window.makeKeyAndOrderFront(nil); NSApp.activate()
                var mapAgreement = true, mapReveal = true
                for ordering in ["Size", "Name", "Modified"] {
                    model.storageSort = ordering
                    try await Task.sleep(for: .milliseconds(250))
                    let query = StorageListingQuery(largestFiles: false, directory: downloads.path, filter: "All items",
                        showHidden: false, search: "", location: "All locations", sort: ordering, selection: [])
                    let rows = try await Task.detached { try index.listing(query) }.value
                    let partition = StorageExploreListing(nodes: rows), map = StorageMapEntry.entries(for: rows)
                    mapAgreement = mapAgreement && map.filter { !$0.isRemainder }.map(\.id) == partition.primary.filter { $0.bytes > 0 }.map(\.id)
                        && map.filter { !$0.isRemainder }.allSatisfy { marker(window, "storage-map-" + $0.id) != nil }
                    try clickMarker(window, "storage-map-storage-remainder")
                    try await Task.sleep(for: .milliseconds(200))
                    if let first = partition.remainder.first { mapReveal = mapReveal && marker(window, "storage-row-" + first.id).map { !$0.visibleRect.isEmpty } == true }
                    mapReveal = mapReveal && model.storageSelection == [leaf.path] && model.storageDiscovery.session?.id == navigationSession
                    try saveScanCheckWindow(window, path: output + "-map-" + ordering + ".png")
                    guard mapReveal else { throw LumaError.rejected("Map remainder did not reveal its first row under " + ordering) }
                }
                report["mapListMembershipAllSorts"] = mapAgreement
                report["mapRemainderRevealsRows"] = mapReveal
                let originalStorageStatus = model.storageStatus
                let documents = home.appendingPathComponent("Documents")
                let bounded = try await Task.detached { try StorageDiscovery.scan(home: home, roots: [documents], limit: 128) }.value
                model.publishStorage(bounded); model.storageLimit = 128; model.storageRootsOverride = [documents]
                let oldSession = model.storageDiscovery.session?.id
                model.rescanStorageWithLargerLimit()
                try await wait { !model.storageLoading && !model.storageDiscovery.isBusy }
                report["honestLargerFreshScan"] = bounded.largerScanLimit(current: 128) == 256 && model.storageLimit == 256
                    && model.storageDiscovery.session?.id != oldSession && (model.storageIndex?.nodes.count ?? 0) > bounded.nodes.count
                var timed = bounded; timed.discoveryBounds = [.time]
                model.publishStorage(timed); model.storageLimit = 128
                let timedSession = model.storageDiscovery.session?.id
                model.rescanStorageWithLargerLimit()
                report["timeBoundCannotOfferLargerScan"] = timed.largerScanLimit(current: 128) == nil && model.storageLimit == 128
                    && model.storageDiscovery.session?.id == timedSession
                model.storageRootsOverride = [home]; model.storageLimit = 200_000
                model.publishStorage(index); model.storageSelection = [leaf.path]; model.storageSort = "Size"; model.storageStatus = originalStorageStatus
                model.storageSearch = ""; model.storageMode = "Explore"; model.navigateStorage(downloads.path)
                window.setContentSize(NSSize(width: 720, height: 700))
                try await Task.sleep(for: .milliseconds(300))
                report["narrowWindow"] = window.contentView.map { $0.bounds.width < 800 } == true
                try saveScanCheckWindow(window, path: output + "-narrow.png")
                if let frame = originalFrame { window.setFrame(frame, display: true) }
                let moveStarted = Date()
                model.trashStorage(); model.openCore(.system)
                try await wait { !model.operationBusy && !model.cleanupSession.isRunning }
                report["trashSeconds"] = Date().timeIntervalSince(moveStarted)
                report["directTrashWithoutSheet"] = !FileManager.default.fileExists(atPath: leaf.path) && !model.showingReview && window.attachedSheet == nil && model.storageOutcome?.contains("1 moved") == true
                report["unaffectedInventoryRetained"] = model.storageIndex?.nodes[downloads.appendingPathComponent("entry-1.dmg").path] != nil
                model.openCore(.storage)
                guard let id = model.lastStorageSessionID, let session = model.cleanupSession.sessions.first(where: { $0.id == id }) else { throw LumaError.rejected("Missing Storage session: \(model.storageOutcome ?? "unknown")") }
                let undoStarted = Date()
                model.undo(session)
                try await wait { !model.operationBusy && !model.cleanupSession.isRunning }
                report["undoSeconds"] = Date().timeIntervalSince(undoStarted)
                report["undoWithoutSheet"] = FileManager.default.fileExists(atPath: leaf.path) && window.attachedSheet == nil
                try await wait { !model.storageDiscovery.isBusy }
                report["undoUpdatesObservation"] = model.storageIndex?.nodes[leaf.path] != nil && model.storageOutcome?.hasPrefix("Undo:") == true
                let outcome = model.storageOutcome, publishedRoot = model.storageIndex?.rootID
                model.scanRunner = { _, _ in try await Task.sleep(for: .milliseconds(250)); throw LumaError.rejected("Synthetic B unavailable") }
                model.startScan(.init(.storage, root: home.appendingPathComponent("unavailable-B")))
                report["pendingScopeKeepsLabels"] = model.storageIndex?.rootID == publishedRoot
                try await wait { !model.scanSessions.isBusy }
                report["failedScopeKeepsLabelsAndOutcome"] = model.storageIndex?.rootID == publishedRoot && model.storageOutcome == outcome
                if let observedScope = model.storageIndex?.scope {
                    let protectedResidue = try await Task.detached { try Filesystem.item(leaf, category: .storage, safety: .userData, explanation: "fixture", consequence: "fixture", rule: "manual.folder-review") }.value
                    model.residueSelection["protected-fixture"] = protectedResidue
                    let nextRoot = home.appendingPathComponent("Documents")
                    model.scanRunner = { request, emit in
                        try await Task.sleep(for: .milliseconds(500))
                        return try await ScanEngine.run(request, emit: emit)
                    }
                    model.startScan(.init(.storage, root: nextRoot))
                    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didUnmountNotification, object: nil,
                        userInfo: [NSWorkspace.volumeURLUserInfoKey: URL(fileURLWithPath: observedScope.volume.identity.mountPath)])
                    try await wait { !model.scanSessions.isBusy }
                    report["oldVolumeDoesNotCancelNewScope"] = model.storageIndex?.scope.root.path == nextRoot.path && model.scanSessions.session?.phase == .completed
                    report["volumeInvalidationPreservesResidues"] = model.residueSelection["protected-fixture"] != nil
                    model.residueSelection.removeValue(forKey: "protected-fixture")
                }
                model.scanRunner = originalRunner
                model.ensureStorage(refresh: true)
                try await wait { !model.storageLoading && !model.storageDiscovery.isBusy }
                guard let saved = model.storageIndex else { throw LumaError.rejected("Missing refreshed index") }
                try await model.storageStore.save(saved)
                let warm = Date()
                let sessionBeforeWarmOpen = model.storageDiscovery.session?.id
                model.storageIndex = nil; model.storageEntered = false; model.loadSavedStorage()
                try await wait { model.storageIndex != nil }
                report["warmOpenSeconds"] = Date().timeIntervalSince(warm)
                report["warmHierarchyAvailable"] = model.storageIndex?.nodes[leaf.path] != nil
                report["noScanOnWarmOpen"] = model.storageDiscovery.session?.id == sessionBeforeWarmOpen && !model.storageDiscovery.isBusy
                try await wait { !model.storageLoading && !model.storageDiscovery.isBusy }
                // One coalesced refresh may cover earlier genuine Trash/Undo events.
                try await Task.sleep(for: .seconds(3))
                try await wait { !model.storageDiscovery.isBusy }
                let settled = model.storageIndex?.scannedAt
                try await Task.sleep(for: .seconds(6))
                report["persistenceSettles"] = !model.storageDiscovery.isBusy && model.storageIndex?.scannedAt == settled
                model.storageMode = "Largest files"
                try await Task.sleep(for: .milliseconds(250))
                try saveScanCheckWindow(window, path: output + "-largest.png")
                // Type through the native field editor, activate the first matching path,
                // then dismiss a second popover with Escape.
                window.makeKeyAndOrderFront(nil); NSApp.activate()
                model.search = ""; model.showingSearch = true
                try await Task.sleep(for: .milliseconds(300))
                let searchWindow = NSApp.windows.first { $0.isVisible && $0.className == "_NSPopoverWindow" }
                let editor = searchWindow?.firstResponder as? NSTextView
                report["searchImmediateTyping"] = editor != nil
                report["searchWindowDebug"] = NSApp.windows.filter(\.isVisible).map { "\($0.className): key=\($0.isKeyWindow) responder=\(String(describing: $0.firstResponder))" }
                editor?.insertText("entry-19", replacementRange: NSRange(location: NSNotFound, length: 0))
                try await wait { model.search == "entry-19" }
                try await Task.sleep(for: .milliseconds(200))
                if let keyWindow = searchWindow,
                   let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: keyWindow.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) { keyWindow.sendEvent(event) }
                try await Task.sleep(for: .milliseconds(250))
                report["searchKeyboardActivation"] = !model.showingSearch && model.storageFocus == downloads.appendingPathComponent("entry-19.dmg").path
                report["searchActivationDebug"] = ["search": model.search, "showing": String(model.showingSearch), "focus": model.storageFocus ?? "nil"]
                model.showingSearch = true
                try await Task.sleep(for: .milliseconds(250))
                if let keyWindow = NSApp.windows.first(where: { $0.isVisible && $0.className == "_NSPopoverWindow" }),
                   let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: keyWindow.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) { keyWindow.sendEvent(event) }
                try await Task.sleep(for: .milliseconds(200))
                report["searchEscape"] = !model.showingSearch
                model.showingSearch = false
                model.storageSearch = "no-matching-fixture"
                try await Task.sleep(for: .milliseconds(250))
                try saveScanCheckWindow(window, path: output + "-empty.png")
                model.storageMode = "Explore"; model.navigateStorage(downloads.path)
                try await Task.sleep(for: .milliseconds(250))
                try saveScanCheckWindow(window, path: output + "-empty-explore.png")
                model.storageSearch = ""
                report["coreRoutes"] = Destination.allCases.map(\.rawValue) == ["Overview", "Storage", "Apps", "Residues", "Maintenance", "System", "Activity"]
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
                report["windowFrameRestored"] = window.frame == originalFrame
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Storage QA report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
