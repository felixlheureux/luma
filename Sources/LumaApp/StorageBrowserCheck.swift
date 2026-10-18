#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Uses generated folders and read-only review. Never invokes cleanup or Open.
    func checkStorageBrowser(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let oldRunner = model.scanRunner
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/storage-\(UUID())")
            let denied = root.appendingPathComponent("Unreadable")
            defer {
                model.scanRunner = oldRunner
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                try? FileManager.default.removeItem(at: root)
                NSApp.terminate(nil)
            }
            var report: [String: Any] = ["mutationInvoked": false]
            do {
                try await Task.sleep(for: .seconds(2))
                let preparation = Task.detached(priority: .utility) {
                    for path in ["a/b/c", "Empty", "Unreadable", "Library/CloudStorage", "Sample.bundle"] {
                        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
                    }
                    for i in 0..<20 { try Data(repeating: UInt8(i), count: 30 + i).write(to: root.appendingPathComponent("entry-\(i).dmg")) }
                    for i in 0..<1_000 { try Data("nested fixture".utf8).write(to: root.appendingPathComponent("a/b/c/file-\(i)")) }
                    try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
                    try Data("opaque package".utf8).write(to: root.appendingPathComponent("Sample.bundle/content"))
                    try Data("unreadable".utf8).write(to: denied.appendingPathComponent("content"))
                    try Data("provider fixture".utf8).write(to: root.appendingPathComponent("Library/CloudStorage/content"))
                    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
                }
                try await preparation.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
                    throw LumaError.rejected("No native storage window.")
                }
                model.destination = .storage
                model.authorizedRoots.append(root)
                model.scanRunner = { request, emit in
                    try await Task.sleep(for: .seconds(1))
                    return try await ScanEngine.run(request, emit: emit)
                }
                let start = Date()
                model.startScan(.init(.storage, root: root))
                try await Task.sleep(for: .milliseconds(300))
                try saveScanCheckWindow(window, path: output + "-loading.png")
                try await waitForStorageCheck { !model.busy }
                let index = try requireStorageIndex(model)
                report["scanSecondsIncludingInjectedDelay"] = Date().timeIntervalSince(start)
                report["indexSeconds"] = index.duration
                report["nodes"] = index.nodes.count
                report["partialRoot"] = index.nodes[index.rootID]?.isComplete == false
                report["providerExcluded"] = index.nodes[root.appendingPathComponent("Library/CloudStorage").path]?.accessCapability == .providerManaged
                report["unreadablePartial"] = index.nodes[denied.path]?.isComplete == false
                report["nothingSelected"] = model.selected.isEmpty
                let map = StorageMapEntry.entries(for: index.children(of: index.rootID))
                report["remainderMatchesList"] = map.last?.isRemainder == true && map.reduce(0) { $0 + $1.bytes } == index.children(of: index.rootID).reduce(0) { $0 + $1.bytes }
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-partial.png")
                let leaf = root.appendingPathComponent("entry-0.dmg")
                model.storageFocus = leaf.path; model.selected = [leaf.path]
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-selected.png")
                model.reviewStorage()
                try await waitForStorageCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["reviewPresented"] = model.showingReview && window.attachedSheet != nil && model.reviewPlan?.items.count == 1
                model.showingReview = false; model.reviewPlan = nil
                try await Task.sleep(for: .milliseconds(250))
                for path in ["a", "a/b", "a/b/c"] { model.navigateStorage(root.appendingPathComponent(path).path) }
                report["threeLevelsAndSelectionCleared"] = model.storageDirectory == root.appendingPathComponent("a/b/c").path && model.selected.isEmpty && model.storageFocus == nil
                report["cachedNavigation"] = model.storageIndex?.scannedAt == index.scannedAt && !model.scanSessions.isBusy
                model.navigateStorage(index.rootID)
                report["breadcrumbBack"] = model.storageDirectory == index.rootID
                model.navigateStorage(root.appendingPathComponent("Empty").path)
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-empty.png")
                report["emptyComplete"] = index.nodes[model.storageDirectory ?? ""]?.isComplete == true
                model.navigateStorage(index.rootID)
                try Data("changed".utf8).write(to: leaf)
                model.selected = [leaf.path]; model.error = nil
                model.reviewStorage()
                try await waitForStorageCheck { !model.busy }
                report["staleReviewRejected"] = model.error != nil && model.reviewPlan == nil && !model.showingReview
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: output), options: .atomic)
            } catch { NSLog("Storage QA report failed: %@", error.localizedDescription) }
        }
    }

    private func requireStorageIndex(_ model: AppModel) throws -> StorageIndex {
        guard let index = model.storageIndex else { throw LumaError.rejected("No completed storage index.") }
        return index
    }

    private func waitForStorageCheck(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard predicate() else { throw LumaError.rejected("Storage QA timed out.") }
    }
}
#endif
