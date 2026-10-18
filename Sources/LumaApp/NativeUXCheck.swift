#if DEBUG
import SwiftUI
import LumaCore

extension LumaAppDelegate {
    /// Own-window smoke review, with no scans, cleanup, app quits or permission changes.
    /// Records current system accommodations without changing system settings.
    /// Captures and timing samples do not substitute for a keyboard/VoiceOver session.
    func checkNativeUX(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            var report: [String: Any] = ["mutationInvoked": false, "manualAccessibilityVerified": false]
            var samples: [[String: Any]] = []
            do {
                try await Task.sleep(for: .seconds(2))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                    throw LumaError.rejected("No main window for native UX review.")
                }
                let samplesBefore = model.cpuHistory.count
                for appearance in ["light", "dark", "system"] {
                    for increasedContrast in [false, true] {
                        let dark = appearance == "dark" || (appearance == "system" && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
                        window.appearance = increasedContrast
                            ? NSAppearance(named: dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                            : appearance == "system" ? nil : NSAppearance(named: dark ? .darkAqua : .aqua)
                        guard let host = window.contentView else { throw LumaError.rejected("No native content view.") }
                        for destination in Destination.allCases {
                            let start = ContinuousClock.now
                            model.destination = destination
                            // Yield for a display opportunity, then flush layout. The elapsed
                            // value includes the requested 20 ms; it is not a GPU frame trace.
                            try await Task.sleep(for: .milliseconds(20))
                            host.layoutSubtreeIfNeeded()
                            let duration = start.duration(to: .now)
                            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                            samples.append(["appearance": appearance, "increasedContrast": increasedContrast,
                                            "page": destination.rawValue, "layoutSecondsIncludingYield": seconds])
                            guard window.isVisible, host.bounds.width > 0, host.bounds.height > 0 else {
                                throw LumaError.rejected("A reviewed page lost its visible window.")
                            }
                        }
                        model.destination = .overview
                        try await Task.sleep(for: .milliseconds(100))
                        try saveScanCheckWindow(window, path: output + "-\(appearance)-\(increasedContrast ? "contrast" : "standard").png")
                    }
                }
                report["pageSamples"] = samples
                report["pageCount"] = Destination.allCases.count
                report["monitoringContinued"] = model.cpuHistory.count > samplesBefore
                report["menuVisible"] = scanCheckMenuVisible()
                report["windowVisible"] = window.isVisible
                report["nothingSelected"] = model.selected.isEmpty
                report["accessibilityTrusted"] = AXIsProcessTrusted()
                report["reduceMotion"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                report["reduceTransparency"] = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            } catch { report["error"] = error.localizedDescription }
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: output), options: .atomic)
            } catch { NSLog("Native UX report failed: %@", error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
}
#endif
