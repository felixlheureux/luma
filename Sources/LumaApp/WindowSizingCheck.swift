#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkWindowSizing(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            let saved = UserDefaults.standard.string(forKey: "NSWindow Frame main")
            defer { NSApp.terminate(nil) }
            func require(_ value: Bool, _ key: String) throws {
                report[key] = value
                if !value { throw LumaError.rejected(key) }
            }
            do {
                try await Task.sleep(for: .seconds(2))
                guard let window = model.mainWindow else { throw LumaError.rejected("No main window") }
                window.makeKeyAndOrderFront(nil); NSApp.activate()
                try require(window.styleMask.contains(.resizable), "nativeResizableStyle")
                report["autosaveName"] = window.frameAutosaveName
                report["restorable"] = window.isRestorable
                try require(window.frameAutosaveName.isEmpty && !window.isRestorable, "qaDoesNotAutosave")
                let samples = model.cpuHistory.count
                for (page, size) in [(Destination.overview, NSSize(width: 760, height: 650)), (.system, NSSize(width: 1200, height: 850)), (.maintenance, NSSize(width: 900, height: 740))] {
                    model.destination = page
                    window.setContentSize(size)
                    try await Task.sleep(for: .seconds(3))
                    let actual = window.contentView?.bounds.size ?? .zero
                    try require(abs(actual.width - size.width) < 2 && abs(actual.height - size.height) < 2, "\(page.rawValue)KeepsRequestedSizeAcrossUpdates")
                    try require(window.contentMaxSize.width > 1200 && window.contentMaxSize.height > 850, "\(page.rawValue)NoContentMaximumLock")
                    try require(window.frameAutosaveName.isEmpty, "\(page.rawValue)AutosavingStaysDisabled")
                }
                MainWindowSizing.restoreDefault(window)
                try await Task.sleep(for: .milliseconds(300))
                try require(abs((window.contentView?.bounds.width ?? 0) - 1200) < 2, "restoresWideDefault")
                try require(model.cpuHistory.count > samples, "monitoringContinues")
                window.close(); model.openMain()
                try await Task.sleep(for: .milliseconds(300))
                try require(window.isVisible && abs((window.contentView?.bounds.width ?? 0) - 1200) < 2, "reopenKeepsWideSize")
                try require(UserDefaults.standard.string(forKey: "NSWindow Frame main") == saved, "savedUserFrameUnchanged")
                try saveWindowRender(window, path: output + ".png")
                report["width"] = window.contentView?.bounds.width
                report["height"] = window.contentView?.bounds.height
                report["physicalEdgeDragVerified"] = false
            } catch { report["error"] = error.localizedDescription }
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
}
#endif
