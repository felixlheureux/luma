#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    func checkHomebrew(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/brew-ui-\(UUID())")
            var report: [String: Any] = ["realBrewExecuted": false, "realTrashInvoked": false]
            defer { try? FileManager.default.removeItem(at: root); NSApp.terminate(nil) }
            func require(_ value: Bool, _ key: String) throws {
                report[key] = value
                if !value { throw LumaError.rejected(key) }
            }
            func pause() async throws { try await Task.sleep(for: .milliseconds(250)) }
            @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
            do {
                try await Task.sleep(for: .seconds(2))
                let executable = root.appendingPathComponent("bin/brew")
                let appURL = root.appendingPathComponent("Applications/Fixture.app")
                let cask = root.appendingPathComponent("Caskroom/fixture-cask/1")
                for directory in [executable.deletingLastPathComponent(), appURL.appendingPathComponent("Contents"), cask] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.lumatest.brew"], format: .xml, options: 0).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
                try FileManager.default.createSymbolicLink(at: cask.appendingPathComponent("Original.app"), withDestinationURL: appURL)
                let script = #"""
                #!/bin/bash
                case "$*" in
                  --prefix) /usr/bin/dirname "$(/usr/bin/dirname "$0")" ;;
                  'info --json=v2 --installed') /usr/bin/printf '%s' '{"formulae":[{"full_name":"git","installed":[{"installed_on_request":true}]},{"full_name":"orphan-lib","installed":[{"installed_on_request":false}]}],"casks":[{"token":"fixture-cask","installed":"1"},{"token":"font-only","installed":"1"}]}' ;;
                  'autoremove --dry-run') /usr/bin/printf '==> Would autoremove 1 unneeded formula:\norphan-lib\n' ;;
                  'cleanup --dry-run') /usr/bin/printf 'Would remove: /fixture/cache (1MB)\n' ;;
                  *) exit 99 ;;
                esac
                """#
                try Data((script + "\n").utf8).write(to: executable)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
                let provider = HomebrewProvider(executables: [executable])
                model.homebrewReader = { try provider.inventory() }
                let journal = try CleanupJournal(home: root, trashMover: { _ in throw LumaError.rejected("No fixture move expected") })
                try await model.installFixtureJournal(journal)
                let app = ApplicationRecord(url: appURL, name: "Brew Fixture", bundleID: "org.lumatest.brew", version: "1", bytes: 0)
                model.applications = [app]; model.completedScans.insert(.applications)
                model.storageSelection = ["preserved-unrelated-selection"]
                model.openMain(.maintenance)
                guard let window = model.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { throw LumaError.rejected("No window") }
                window.setContentSize(NSSize(width: 900, height: 850)); window.makeKeyAndOrderFront(nil); NSApp.activate()
                try await pause()
                guard let refresh = window.contentView.flatMap({ descendants($0).first { $0.identifier?.rawValue == "luma-check-homebrew-refresh" } }) else { throw LumaError.rejected("No Homebrew refresh control") }
                refresh.scrollToVisible(refresh.bounds); try await pause()
                let frame = refresh.convert(refresh.bounds, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: frame.midX, y: frame.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw LumaError.rejected("No refresh event") }
                    NSApp.postEvent(event, atStart: false)
                }
                let deadline = Date().addingTimeInterval(10)
                while (model.homebrewInventory == nil || model.homebrewLoading) && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                try require(!model.homebrewLoading && model.homebrewInventory?.issues.isEmpty == true, "fixtureProviderSucceeded")
                try require(model.homebrewInventory?.unneededDependencies == ["orphan-lib"] && model.homebrewInventory?.manualPackages.contains("git (formula)") == true, "separateUsageStates")
                try require(model.homebrewInventory?.cleanupSuggestions?.count == 1, "staleSuggestions")
                try require(model.storageSelection == ["preserved-unrelated-selection"], "unrelatedSelectionPreserved")
                try await pause()
                if let marker = window.contentView.flatMap({ descendants($0).first { $0.identifier?.rawValue == "luma-check-homebrew-section" } }) { marker.scrollToVisible(marker.bounds) }
                try await pause(); try saveScanCheckWindow(window, path: output + "-maintenance.png")
                model.openCore(.applications); try await pause()
                try require(model.homebrewCask(app) == "fixture-cask", "verifiedAppsBadge")
                try require(model.uninstallUnavailableReason(app)?.contains("Homebrew") == true, "nativeTrashDisabled")
                model.uninstall(app)
                try require(!model.operationBusy && model.history.isEmpty && FileManager.default.fileExists(atPath: appURL.path), "blockedActionCannotMove")
                try saveScanCheckWindow(window, path: output + "-apps.png")
                model.homebrewReader = { throw LumaError.rejected("Injected broken Brew") }
                model.refreshHomebrew()
                while model.homebrewLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
                try require(model.homebrewInventory == nil && model.homebrewStatus.contains("Injected broken Brew"), "failedRefreshHonest")
            } catch { report["error"] = error.localizedDescription }
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
}
#endif
