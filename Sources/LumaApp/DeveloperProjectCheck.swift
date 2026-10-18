#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Disposable project inspection and native review only; never invokes Trash,
    /// package managers or mutation of a user's actual project.
    func checkDeveloperProjects(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let root = URL(fileURLWithPath: "/private/tmp")
                .appendingPathComponent("luma-project-ui-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            var report: [String: Any] = ["mutationInvoked": false, "fixtureRoot": root.path]
            do {
                try await Task.sleep(for: .seconds(2))
                let preparation = Task.detached(priority: .utility) {
                    let files = [
                        "Node/package.json": "{\"name\":\"fixture\"}",
                        "Node/src/index.ts": "valuable source",
                        "Node/package-lock.json": "keep lockfile",
                        "Node/node_modules/dep/index.js": "locally modified dependency",
                        "Rust/Cargo.toml": "[package]\nname = \"fixture\"\nversion = \"1.0.0\"",
                        "Rust/target/debug/fixture": "build product",
                        "Swift/Package.swift": "// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"Fixture\")",
                        "Swift/.build/arm64-apple-macosx/debug/product": "build product",
                        "Swift/.build/checkouts/Dep/source.swift": "keep edited checkout"
                    ]
                    for (path, text) in files {
                        let url = root.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(text.utf8).write(to: url)
                    }
                }
                try await preparation.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No Projects window.") }
                model.destination = .projects; model.authorizedRoots.append(root)
                model.startScan(.init(.developerProjects, root: root, ignoredPaths: []))
                try await waitForProjectCheck { !model.busy }
                guard let inventory = model.projectInventory else { throw LumaError.rejected("No project inventory: \(model.scanSessions.session?.detail ?? model.status)") }
                report["threeProjects"] = inventory.projects.count == 3
                report["threeReviewItems"] = inventory.report.items.count == 3 && inventory.report.items.allSatisfy { $0.safety == .review }
                report["nothingSelected"] = model.selected.isEmpty
                report["sourceAndLockfileKept"] = inventory.projects.flatMap(\.entries).contains { $0.kind == .source && $0.item == nil }
                    && inventory.projects.flatMap(\.entries).contains { $0.url.lastPathComponent == "package-lock.json" && $0.item == nil }
                report["checkoutKept"] = inventory.projects.flatMap(\.entries).contains { $0.url.lastPathComponent == "checkouts" && $0.item == nil }
                try await Task.sleep(for: .milliseconds(350))
                try saveScanCheckWindow(window, path: output + "-projects.png")
                model.selected = Set(inventory.report.items.map(\.id))
                model.review(inventory.report.items)
                try await waitForProjectCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(350))
                report["reviewPresented"] = model.showingReview && window.attachedSheet != nil
                    && model.reviewPlan?.source == .developerProjects && model.reviewPlan?.items.count == 3
                try saveScanCheckWindow(window, path: output + "-review.png")
                model.showingReview = false; model.reviewPlan = nil; model.selected = []
                try await Task.sleep(for: .milliseconds(250))
                let item = inventory.report.items[0]
                let extra = item.url.appendingPathComponent("new-build-file")
                try await Task.detached { try Data("concurrent build".utf8).write(to: extra) }.value
                model.selected = [item.id]; model.error = nil
                model.review([item])
                try await waitForProjectCheck { !model.busy }
                report["changedOutputRejected"] = model.error != nil && model.reviewPlan == nil && !model.showingReview
                model.error = nil
                model.invalidateProjects()
                report["invalidatedSelectionAndSnapshot"] = model.selected.isEmpty && model.projectInventory == nil && model.completedSnapshots[.developerProjects] == nil
                report["monitoringContinued"] = !model.cpuHistory.isEmpty
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic) }
            catch { NSLog("Project QA report failed: %@", error.localizedDescription) }
        }
    }
    private func waitForProjectCheck(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard predicate() else { throw LumaError.rejected("Project QA timed out.") }
    }
}
#endif
