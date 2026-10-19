#if DEBUG
import SwiftUI
import LumaCore

private final class ScanCheckGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    let release = DispatchSemaphore(value: 0)
    func pauseOnce(_ event: ScanEvent) {
        guard case .progress(let pulse) = event, pulse.phase == "Measuring application bundles" else { return }
        lock.lock(); let pause = !used; used = true; lock.unlock()
        if pause { _ = release.wait(timeout: .now() + 20) }
    }
}

extension LumaAppDelegate {
    /// Native integration QA: fixture scans only, no cleanup execution, no
    /// permission changes outside synthetic folders, and no external app actions.
    func checkScanSessions(output: String) {
        Task { @MainActor in
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/session-\(UUID())")
            let apps = root.appendingPathComponent("Applications"), data = root.appendingPathComponent("Data")
            let denied = data.appendingPathComponent("Denied")
            let gate = ScanCheckGate()
            let model = AppModel.shared
            let oldRunner = model.scanRunner
            defer {
                gate.release.signal(); model.scanRunner = oldRunner
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                try? FileManager.default.removeItem(at: root)
                NSApp.terminate(nil)
            }
            var report: [String: Any] = ["mutationInvoked": false]
            do {
                try await Task.sleep(for: .seconds(2))
                model.showMainWindow?()
                try await waitForScanCheck { NSApp.windows.contains { $0.isVisible && $0.canBecomeMain } }
                let preparation = Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
                    try Data("readable fixture".utf8).write(to: data.appendingPathComponent("Readable"))
                    try Data("denied fixture".utf8).write(to: denied.appendingPathComponent("Child"))
                    for appIndex in 0..<30 {
                        let bundle = apps.appendingPathComponent("Fixture\(appIndex).app/Contents")
                        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Resources"), withIntermediateDirectories: true)
                        let plist: [String: String] = ["CFBundleIdentifier": "org.example.fixture\(appIndex)", "CFBundleShortVersionString": "1.0"]
                        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
                        for fileIndex in 0..<200 {
                            try Data("synthetic fixture \(fileIndex)".utf8).write(to: bundle.appendingPathComponent("Resources/\(fileIndex)"))
                        }
                    }
                }
                try await preparation.value
                report["fixtureApplications"] = 30; report["fixtureResourceFiles"] = 6_000
                model.scanRunner = { request, emit in
                    try await ScanEngine.run(request, home: root, applicationRoots: [apps], emit: { event in
                        emit(event); gate.pauseOnce(event)
                    })
                }
                model.destination = .applications; model.applicationTab = .installed
                model.runScan(.applications)
                try await waitForScanCheck { model.visibleApplications.count == 30 && model.visibleApplications.allSatisfy { $0.sizeState == .pending } }
                report["metadataVisibleBeforeSizing"] = true
                report["previewCannotInspect"] = model.busy && model.completedSnapshots[.applications] == nil
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { throw LumaError.rejected("No main window for scan QA.") }
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + ".png")
                model.destination = .system
                try await Task.sleep(for: .milliseconds(200))
                report["navigationWhileScanning"] = model.destination == .system && model.scanSessions.isBusy
                let beforeSettings = Set(NSApp.windows.map(\.windowNumber))
                model.showSettingsWindow?()
                try await Task.sleep(for: .milliseconds(500))
                let settings = NSApp.windows.filter { !beforeSettings.contains($0.windowNumber) && $0.isVisible }
                report["settingsWhileScanning"] = !settings.isEmpty
                for settingsWindow in settings { settingsWindow.close() }
                let samples = model.cpuHistory.count
                window.performClose(nil)
                try await Task.sleep(for: .seconds(2.5))
                report["windowClosedDuringScan"] = !window.isVisible && model.scanSessions.isBusy
                report["monitoringContinued"] = model.cpuHistory.count > samples
                report["menuStayedVisible"] = self.scanCheckMenuVisible()
                model.showMainWindow?()
                try await Task.sleep(for: .milliseconds(300))
                report["windowReopenedDuringScan"] = window.isVisible && model.scanSessions.isBusy
                model.cancel()
                report["stoppingUntilWorkerReturns"] = model.scanSessions.isBusy && model.scanSessions.session?.phase == .stopping(.cancelled)
                gate.release.signal()
                try await waitForScanCheck { !model.busy }
                report["cancelledInventoryNotCommitted"] = model.completedSnapshots[.applications] == nil && model.applications.isEmpty

                // Retry the real 6,000-file fixture without the synthetic blocked call.
                model.destination = .applications
                var heartbeats = 0, maxDelay: TimeInterval = 0, previousBeat = Date()
                let heartbeat = Task { @MainActor in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(30)) } catch { break }
                        let now = Date(); maxDelay = max(maxDelay, now.timeIntervalSince(previousBeat)); previousBeat = now; heartbeats += 1
                    }
                }
                let started = Date()
                model.retryScan(.applications)
                model.destination = .storage; model.destination = .applications
                try await waitForScanCheck { !model.busy }
                heartbeat.cancel()
                report["inventorySeconds"] = Date().timeIntervalSince(started)
                report["mainActorHeartbeatsDuringInventory"] = heartbeats
                report["maxMainActorHeartbeatDelaySeconds"] = maxDelay
                report["completedApplicationCount"] = model.applications.count
                report["allSizesResolved"] = model.applications.allSatisfy { $0.sizeState == .available }

                let footprintGate = ScanCheckGate()
                model.scanRunner = { request, emit in
                    try await ScanEngine.run(request, home: root, applicationRoots: [apps], emit: { event in
                        emit(event)
                        if case .item = event { footprintGate.pauseOnce(.progress(.init("Measuring application bundles"))) }
                    })
                }
                if let application = model.applications.first {
                    model.inspect(application)
                    try await waitForScanCheck { model.scanSessions.session?.preview.items.isEmpty == false }
                    try await Task.sleep(for: .milliseconds(350))
                    report["footprintSheetVisibleWhileScanning"] = NSApp.windows.contains { $0.attachedSheet != nil }
                    report["footprintInspectionTracked"] = model.canCancel && model.scanTarget == .footprint && model.footprint.isEmpty
                    model.cancel(); footprintGate.release.signal()
                    try await waitForScanCheck { !model.busy }
                    report["cancelledFootprintNotCommitted"] = model.completedSnapshots[.footprint] == nil && model.footprint.isEmpty
                    model.inspectedApp = nil
                    try await Task.sleep(for: .milliseconds(350))
                }

                // A cancelled partial scan cannot feed AppModel's review path.
                let item = try Filesystem.item(data.appendingPathComponent("Readable"), category: .storage, safety: .userData,
                    explanation: "Synthetic preview", consequence: "Fixture only", rule: "manual.folder-review")
                let previewRelease = ScanCheckGate()
                model.scanRunner = { _, emit in
                    emit(.item(item)); emit(.progress(.init("Measuring application bundles")))
                    previewRelease.pauseOnce(.progress(.init("Measuring application bundles")))
                    return ScanResult()
                }
                model.startScan(.init(.storage, root: data))
                try await waitForScanCheck { model.scanSessions.session?.preview.items.count == 1 }
                model.cancel(); previewRelease.release.signal()
                try await waitForScanCheck { !model.busy }
                model.selected = [item.id]; model.authorizedRoots = [data]; model.error = nil
                model.review([item], source: .storage)
                report["partialReviewRejected"] = model.reviewPlan == nil && model.error != nil && !model.showingReview
                model.error = nil; model.selected = []

                model.scanRunner = { request, emit in try await ScanEngine.run(request, home: root, applicationRoots: [apps], emit: emit) }
                try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
                model.startScan(.init(.storage, root: data))
                try await waitForScanCheck { !model.busy }
                report["deniedCoverageReported"] = model.snapshot(for: .storage)?.result.report.coverage.contains { $0.state == .blocked } == true
                report["readableResultsRetained"] = model.storageIndex?.children(of: data.path).filter { $0.isComplete }.count == 1
                let firstSnapshot = model.snapshot(for: .storage)?.finishedAt
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                model.retryScan(.storage)
                try await waitForScanCheck { !model.busy }
                report["permissionRetrySameScope"] = model.snapshot(for: .storage)?.request.root == data && model.storageRoot == data
                report["permissionRetrySucceeded"] = model.storageIndex?.children(of: data.path).filter { $0.isComplete }.count == 2 && model.snapshot(for: .storage)?.result.report.isComplete == true
                report["newSnapshotTimestamp"] = model.snapshot(for: .storage)?.finishedAt != firstSnapshot
                report["nothingSelected"] = model.selected.isEmpty

                // Real platform-policy exclusion on generated local data. No
                // account, provider content, download or Finder launch is used.
                model.destination = .storage
                let provider = data.appendingPathComponent("Library/CloudStorage")
                try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: true)
                try Data("synthetic downloaded provider bytes".utf8).write(to: provider.appendingPathComponent("Downloaded"))
                model.retryScan(.storage)
                try await waitForScanCheck { !model.busy }
                let coverage = model.snapshot(for: .storage)?.result.report.coverage ?? []
                report["providerScopeExcluded"] = coverage.contains { $0.accessCapability == .providerManaged && $0.state == .skipped }
                report["providerBytesNotCounted"] = model.storageIndex?.children(of: data.path).filter { $0.isComplete }.count == 2 && model.storageIndex?.nodes[provider.path]?.accessCapability == .providerManaged
                report["providerSelectionEmpty"] = model.selected.isEmpty
                if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                    try await Task.sleep(for: .milliseconds(350))
                    try self.saveScanCheckWindow(window, path: URL(fileURLWithPath: output).deletingPathExtension().path + "-provider.png")
                }

                // Current supported app layout, in a fixture home; no real app
                // data, package manager or cleanup executor is invoked.
                let support = try self.prepareCacheDiscoveryFixture(home: root)
                model.destination = .clean
                model.startScan(.init(.generatedData))
                try await waitForScanCheck { !model.busy }
                report["expandedCacheUnits"] = model.cleanup.count == 4
                report["cacheGroups"] = GeneratedDataGroup.groups(for: model.cleanup).count == 2
                report["cacheUniqueBytes"] = model.cleanupBytes == 39
                report["cacheAdjacentDataPreserved"] = FileManager.default.fileExists(atPath: support.appendingPathComponent("Backups/unsaved").path)
                report["cacheNothingSelected"] = model.selected.isEmpty
                if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                    try await Task.sleep(for: .milliseconds(350))
                    try self.saveScanCheckWindow(window, path: URL(fileURLWithPath: output).deletingPathExtension().path + "-caches.png")
                }
                model.selected = Set(model.cleanup.map(\.id))
                model.review(model.cleanup, source: .generatedData)
                try await waitForScanCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["cacheReviewTotalMatches"] = model.reviewPlan?.logicalBytes == 39
                report["cacheReviewPresented"] = NSApp.windows.contains { $0.attachedSheet != nil }
                model.showingReview = false; model.reviewPlan = nil
                model.invalidateGeneratedFindings()
                report["cacheSnapshotInvalidated"] = model.cleanupReport == nil && model.cleanup.isEmpty && !model.completedScans.contains(.clean) && model.snapshot(for: .generatedData) == nil && model.scanSessions.snapshots[.generatedData] == nil && model.scanSessions.session == nil && model.selected.isEmpty
            } catch { report["error"] = error.localizedDescription }
            // Let SwiftUI detach review/error sheets before requesting application
            // termination; otherwise AppKit may defer Quit after the report succeeds.
            model.showingReview = false
            model.inspectedApp = nil
            model.error = nil
            try? await Task.sleep(for: .milliseconds(400))
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
            catch { FileHandle.standardError.write(Data("Scan QA report failed: \(error.localizedDescription)\n".utf8)) }
        }
    }

    private func prepareCacheDiscoveryFixture(home: URL) throws -> URL {
        guard let required = Rules.generated.first(where: { $0.id == "app.vscode.bytecode" })?.requiredApplication else {
            throw LumaError.rejected("The cache fixture has no supported owner definition.")
        }
        let bundle = home.appendingPathComponent("Applications/Visual Studio Code.app/Contents")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Resources/app"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": required.bundleID, "CFBundleShortVersionString": required.version], format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        try JSONSerialization.data(withJSONObject: ["darwinBundleIdentifier": required.bundleID, "nameShort": required.productName, "commit": required.commit]).write(to: bundle.appendingPathComponent("Resources/app/product.json"))
        try JSONSerialization.data(withJSONObject: ["version": required.version]).write(to: bundle.appendingPathComponent("Resources/app/package.json"))
        let root = home.appendingPathComponent("Library/Application Support/Code")
        for leaf in ["Cache", "GPUCache", "CachedData", "logs", "User", "Backups"] {
            let directory = root.appendingPathComponent(leaf)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("cache fixture".utf8).write(to: directory.appendingPathComponent(leaf == "Backups" ? "unsaved" : "entry"))
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("logs/entry"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("CachedData/entry"), to: root.appendingPathComponent("logs/entry"))
        return root
    }

    private func waitForScanCheck(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard condition() else { throw LumaError.rejected("Native scan QA timed out.") }
    }

    func saveScanCheckWindow(_ window: NSWindow, path: String) throws {
        try saveWindowRender(window, path: path)
    }
}
#endif
