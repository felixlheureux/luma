#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    // Opt-in native QA. Only synthetic files in this check's fixture directory
    // are created/removed. This never calls the cleanup executor or Restore.
    func checkCleanupReview(output: String) {
        Task { @MainActor in
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/review-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            var report: [String: Any] = [:]
            do {
                try await Task.sleep(for: .seconds(2))
                let model = AppModel.shared
                let one = root.appendingPathComponent("first"), two = root.appendingPathComponent("second")
                for folder in [one, two] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
                let file = one.appendingPathComponent("shared")
                try Data("fixture".utf8).write(to: file)
                try FileManager.default.linkItem(at: file, to: two.appendingPathComponent("shared"))
                let items = try [one, two].map {
                    try Filesystem.item($0, category: .storage, safety: .userData,
                                        explanation: "Synthetic review fixture", consequence: "Fixture only", rule: "manual.folder-review")
                }
                model.destination = .storage; model.storage = items
                model.authorizedRoots = [root]
                var scanReport = ScanReport(); scanReport.items = items
                let fixtureResult = ScanResult(report: scanReport)
                model.scanSessions.start(.init(.storage, root: root)) { _ in fixtureResult }
                try await waitForReview(model)
                model.selected = Set(items.map(\.id))
                model.review(items, source: .storage)
                try await waitForReview(model)
                try await Task.sleep(for: .milliseconds(600))
                report["reviewShown"] = model.showingReview
                report["nativeSheetAttached"] = NSApp.windows.contains { $0.attachedSheet != nil }
                report["itemCount"] = model.reviewPlan?.items.count ?? 0
                report["logicalBytes"] = model.reviewPlan?.logicalBytes ?? -1
                report["rawItemBytes"] = items.reduce(Int64(0)) { $0 + $1.bytes }
                report["uniqueTotalCorrect"] = model.reviewPlan?.logicalBytes == 7
                model.showingReview = false; model.reviewPlan = nil
                try await Task.sleep(for: .milliseconds(400))
                // A forged duplicate label without group evidence must fail in
                // the actual AppModel review path before any sheet can authorize it.
                let unsupported = try Filesystem.item(file, category: .storage, safety: .userData,
                    explanation: "Missing evidence fixture", consequence: "Fixture only", rule: "duplicates.sha256")
                model.selected = [unsupported.id]; model.duplicates = []; model.error = nil
                model.review([unsupported], source: .duplicates)
                try await waitForReview(model)
                report["missingEvidenceRejected"] = model.reviewPlan == nil && !model.showingReview && model.error != nil
                report["fixtureUnchanged"] = try String(contentsOf: file, encoding: .utf8) == "fixture"
                report["mutationInvoked"] = false
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
            catch { FileHandle.standardError.write(Data("Review check failed: \(error.localizedDescription)\n".utf8)) }
        }
    }

    private func waitForReview(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(15)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        if model.busy { throw LumaError.rejected("Review check timed out.") }
    }
}
#endif
