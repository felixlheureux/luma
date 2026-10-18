#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Generated app/data only. Checks native inspection and review; never cleans.
    func checkApplicationFootprint(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let oldRunner = model.scanRunner
            let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/footprint-\(UUID())")
            let denied = home.appendingPathComponent("Library/Logs/com.microsoft.VSCode")
            var report: [String: Any] = ["mutationInvoked": false]
            defer {
                model.scanRunner = oldRunner
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                try? FileManager.default.removeItem(at: home)
                NSApp.terminate(nil)
            }
            do {
                try await Task.sleep(for: .seconds(2))
                let app = try await Task.detached(priority: .utility) {
                    func file(_ path: String, _ content: String) throws {
                        let url = home.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(content.utf8).write(to: url)
                    }
                    try file("Applications/Fixture.app/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.microsoft.VSCode</string></dict></plist>")
                    try file("Library/Application Support/Code/Documents/offline", "valuable content")
                    try file("Library/Caches/com.microsoft.VSCode/cache", "generated data")
                    try file("Library/Preferences/com.microsoft.VSCode.plist", "settings")
                    try file("Library/Logs/com.microsoft.VSCode/log", "diagnostics")
                    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
                    return ApplicationRecord(url: home.appendingPathComponent("Applications/Fixture.app"), name: "Footprint Fixture", bundleID: "com.microsoft.VSCode", version: "1", bytes: 0)
                }.value
                guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No main footprint window.") }
                model.scanRunner = { request, emit in
                    try await Task.sleep(for: .milliseconds(500))
                    return try await ScanEngine.run(request, home: home, applicationRoots: [home.appendingPathComponent("Applications")], emit: emit)
                }
                model.destination = .applications
                model.inspect(app)
                try await waitForFootprintCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(400))
                let footprint = try requireFootprint(model)
                report["nativeSheet"] = window.attachedSheet != nil
                report["nothingSelected"] = model.selected.isEmpty
                report["partialRetainsReadable"] = !footprint.isComplete && footprint.items.count == 4
                report["fourCategories"] = Set(footprint.entries.compactMap { $0.item == nil ? nil : $0.relationship.category }).count == 4
                report["deniedIsUnknown"] = footprint.entries.contains { $0.relationship.url.path == denied.path && $0.state == .blocked && $0.bytes == nil }
                report["absentIsDistinct"] = footprint.entries.contains { $0.state == .missing && $0.bytes == nil }
                report["namedMapping"] = footprint.entries.contains { $0.relationship.url.lastPathComponent == "Code" && $0.relationship.category == .userData && $0.relationship.evidence.contains("Explicit ownership mapping") }
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-partial.png")
                let items = footprint.items.filter { $0.category != .applications }
                model.selected = Set(items.map(\.id))
                model.inspectedApp = nil
                try await Task.sleep(for: .milliseconds(400))
                model.review(items, source: .applications)
                try await waitForFootprintCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(400))
                report["separateBundleChoice"] = model.reviewPlan?.items.allSatisfy { $0.category != .applications } == true
                report["reviewMatchesTotals"] = model.showingReview && window.attachedSheet != nil && model.reviewPlan?.logicalBytes == footprint.accounting.bytes(for: items)
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-review.png")
                model.showingReview = false; model.reviewPlan = nil
                try await Task.sleep(for: .milliseconds(400))
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
                model.inspect(app)
                try await waitForFootprintCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(400))
                report["retryComplete"] = try requireFootprint(model).isComplete && model.selected.isEmpty
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-complete.png")
                model.reviewingApplicationReset = true
                model.selected = []
                try await Task.sleep(for: .milliseconds(500))
                report["resetNativeSheet"] = window.attachedSheet != nil && model.reviewingApplicationReset
                report["resetStartsEmpty"] = model.selected.isEmpty
                if let sheet = window.attachedSheet {
                    sheet.selectNextKeyView(nil)
                    report["resetKeyboardFocus"] = sheet.firstResponder != nil && sheet.firstResponder !== sheet
                }
                report["resetGroups"] = Set(try requireFootprint(model).entries.compactMap { ResetCategory.category(for: $0.relationship) }).count == 4
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-reset.png")
                let resetItems = try requireFootprint(model).entries.filter {
                    ResetCategory.category(for: $0.relationship) == .preferences
                }.compactMap(\.item)
                model.selected = Set(resetItems.map(\.id))
                model.inspectedApp = nil
                try await Task.sleep(for: .milliseconds(400))
                model.review(resetItems, source: .applicationReset, resetApplication: app)
                try await waitForFootprintCheck { !model.busy }
                try await Task.sleep(for: .milliseconds(400))
                report["resetReview"] = model.showingReview && window.attachedSheet != nil && model.reviewPlan?.source == .applicationReset
                    && model.reviewPlan?.items.count == 1 && model.reviewPlan?.items.allSatisfy { $0.ruleID == "application.exact-related" } == true
                try saveScanCheckWindow(window.attachedSheet ?? window, path: output + "-reset-review.png")
                model.showingReview = false; model.reviewPlan = nil
                try await Task.sleep(for: .milliseconds(400))
                model.invalidateLeftovers()
                report["mutationInvalidatesLeftovers"] = !model.didScanLeftovers && model.leftovers.isEmpty && model.completedSnapshots[.leftovers] == nil
                model.invalidateApplicationFootprint()
                report["mutationInvalidatesFootprint"] = model.footprintDetails == nil && model.footprint.isEmpty && model.completedSnapshots[.footprint] == nil && model.scanSessions.snapshots[.footprint] == nil
                report["monitoringContinued"] = !model.cpuHistory.isEmpty && self.scanCheckMenuVisible()
            } catch { report["error"] = error.localizedDescription }
            model.inspectedApp = nil
            model.showingReview = false
            try? await Task.sleep(for: .milliseconds(400))
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic)
            } catch { NSLog("Footprint QA report failed: %@", error.localizedDescription) }
        }
    }
    private func requireFootprint(_ model: AppModel) throws -> ApplicationFootprint {
        guard let footprint = model.footprintDetails else { throw LumaError.rejected("No completed footprint.") }
        return footprint
    }
    private func waitForFootprintCheck(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        guard condition() else { throw LumaError.rejected("Footprint QA timed out.") }
    }
}
#endif
