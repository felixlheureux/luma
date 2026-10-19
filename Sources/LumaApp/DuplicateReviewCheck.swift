#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkDuplicateReview(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/duplicate-ui-\(UUID())")
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            defer { model.clearDuplicateComparison(); try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            @MainActor func wait(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(30)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                guard predicate() else { throw LumaError.rejected("Duplicate comparison native check timed out") }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                try await Task.detached {
                    for path in ["Original/Notes.txt", "Archive/Notes-copy.txt", "Elsewhere/Notes.bin"] {
                        let url = root.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data("Personal fixture notes.\nKeep the location you need.\n".utf8).write(to: url)
                    }
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No duplicate comparison window") }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let history = try encoder.encode(model.history), ignores = model.ignored
                model.destination = .duplicates; model.authorizedRoots.append(root)
                model.startScan(.init(.duplicates, root: root))
                try await wait { !model.busy }
                let group = try { () throws -> DuplicateGroup in
                    guard let group = model.duplicates.first, group.items.count == 3 else { throw LumaError.rejected("Missing comparison fixture group") }
                    return group
                }()
                report["nothingSelected"] = model.selected.isEmpty
                try await Task.sleep(for: .milliseconds(350))
                model.compareDuplicateGroup(group, source: .duplicates)
                try await wait { model.duplicateComparisons.count + model.duplicateComparisonErrors.count == 3 }
                report["comparisonLoaded"] = model.duplicateComparisons.count == 3 && model.duplicateComparisons.values.allSatisfy { $0.linkCount == 1 }
                report["unsupportedPreviewExplicit"] = model.duplicateComparisons.contains { path, comparison in
                    if case .unavailable = comparison.preview { return path.hasSuffix(".bin") }; return false
                }
                try await Task.sleep(for: .milliseconds(400))
                try saveScanCheckWindow(window, path: output + "-comparison.png")
                let keeper = group.items[0]
                model.prepareDuplicateKeeper(group: group, keeper: keeper, source: .duplicates)
                try await wait { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["proposalPresented"] = model.duplicateChoice?.removals.count == 2 && model.selected.isEmpty && window.attachedSheet != nil
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-proposal.png")
                model.applyDuplicateKeeper()
                try await wait { !model.busy }
                report["explicitSelection"] = model.selected == Set(group.items.filter { $0.id != keeper.id }.map(\.id))
                try await Task.sleep(for: .milliseconds(350))
                model.review(group.items)
                try await wait { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["ordinaryReviewPresented"] = model.showingReview && model.reviewPlan?.items.count == 2 && window.attachedSheet != nil
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-review.png")
                model.showingReview = false; model.reviewPlan = nil; model.selected = []
                try await Task.sleep(for: .milliseconds(300))
                model.prepareDuplicateKeeper(group: group, keeper: keeper, source: .duplicates)
                try await wait { !model.busy }
                try await Task.detached { try Data("changed fixture keeper".utf8).write(to: keeper.url) }.value
                model.applyDuplicateKeeper()
                try await wait { !model.busy }
                report["changedKeeperRejected"] = model.duplicateChoice == nil && model.selected.isEmpty && model.error != nil
                model.error = nil
                // Yield for the native alert update, then wait for its actual sheet
                // dismissal before terminating the fixture app.
                try await Task.sleep(for: .milliseconds(30))
                try await wait { window.attachedSheet == nil }
                report["historyAndIgnoresPreserved"] = try encoder.encode(model.history) == history && model.ignored == ignores
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Duplicate review report failed: %@", error.localizedDescription) }
        }
    }
}
#endif
