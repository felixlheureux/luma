#if DEBUG
import SwiftUI
import LumaCore

private final class CleanupCheckGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    let release = DispatchSemaphore(value: 0)
    var isStarted: Bool { lock.withLock { started } }
    func enter() {
        lock.withLock { started = true }
        _ = release.wait(timeout: .now() + 10)
    }
}

extension LumaAppDelegate {
    /// Native QA uses a generated home and injected fixture mover only.
    /// No real home/Trash or reference-app mutation is invoked.
    func checkCleanupSessions(output: String) {
        Task { @MainActor in
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/Fixtures/cleanup-session-\(UUID())")
            let gate = CleanupCheckGate()
            defer { gate.release.signal(); try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            var report: [String: Any] = [:]
            do {
                try await Task.sleep(for: .seconds(2))
                let downloads = root.appendingPathComponent("Downloads")
                let trash = root.appendingPathComponent(".Trash")
                for path in [downloads, trash] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
                let items = try ["first", "second", "third"].map { name in
                    let path = downloads.appendingPathComponent(name)
                    try Data("synthetic session fixture".utf8).write(to: path)
                    return try Filesystem.item(path, category: .storage, safety: .userData,
                        explanation: "Synthetic fixture", consequence: "Fixture only", rule: "manual.folder-review")
                }
                let journal = try CleanupJournal(home: root, trashMover: { source in
                    gate.enter()
                    let destination = trash.appendingPathComponent(source.lastPathComponent)
                    try FileManager.default.moveItem(at: source, to: destination)
                    return destination
                })
                let model = AppModel.shared
                try await model.installFixtureJournal(journal)
                model.destination = .history
                model.reviewPlan = try CleanupPlan(items: items, authorizedRoots: [downloads])
                let samples = model.cpuHistory.count
                model.moveToTrash()
                try await waitCleanupCheck { gate.isStarted }
                report["mutationTrackedSeparately"] = model.cleanupSession.isRunning && model.scanTask == nil && !model.scanSessions.isBusy
                model.cleanupSession.stop()
                try await Task.sleep(for: .milliseconds(600))
                report["stoppingRetainsBusy"] = model.busy && model.cleanupSession.stopping
                try saveCleanupCheck(output, suffix: "stopping")
                // View rendering may finish before the next two-second sample.
                // Prove monitoring continues while the fixture mutation is gated.
                try await waitCleanupCheck { model.cpuHistory.count > samples }
                gate.release.signal()
                try await waitCleanupCheck { !model.busy && !model.cleanupSession.isRunning }
                report["partialCleanupRecorded"] = model.history.count == 1 && model.cleanupSession.sessions.first?.phase == .partial && model.recoveryNotices.isEmpty
                report["remainingUntouched"] = items.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }
                try await Task.sleep(for: .milliseconds(600))
                try saveCleanupCheck(output, suffix: "activity")
                guard let session = model.cleanupSession.sessions.first else { throw LumaError.rejected("Missing session fixture.") }
                report["undoWithoutSheet"] = !NSApp.windows.contains { $0.attachedSheet != nil }
                report["undoOnlyEligible"] = model.history.filter { !$0.restored }.count == 1
                model.undo(session)
                try await waitCleanupCheck { !model.busy && !model.cleanupSession.isRunning }
                report["undoRecorded"] = model.history.first?.restored == true && model.cleanupSession.undoAttempts.first?.phase == .completed
                report["allContentsPreserved"] = try items.allSatisfy { try String(contentsOf: $0.url, encoding: .utf8) == "synthetic session fixture" }
                report["monitoringContinued"] = model.cpuHistory.count > samples
                report["menuStayedVisible"] = scanCheckMenuVisible()
                report["realTrashInvoked"] = false
                try await Task.sleep(for: .milliseconds(600))
                try saveCleanupCheck(output, suffix: "restored")
            } catch { report["error"] = error.localizedDescription }
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output)) }
            catch { FileHandle.standardError.write(Data("Cleanup check report failed: \(error.localizedDescription)\n".utf8)) }
        }
    }

    private func waitCleanupCheck(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(40)) }
        guard predicate() else { throw LumaError.rejected("Cleanup session QA timed out.") }
    }

    private func saveCleanupCheck(_ output: String, suffix: String) throws {
        if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
            let target = suffix == "undo" ? (window.attachedSheet ?? window) : window
            target.contentView?.layoutSubtreeIfNeeded()
            try saveScanCheckWindow(target, path: URL(fileURLWithPath: output).deletingPathExtension().path + "-\(suffix).png")
        }
    }
}

#endif
