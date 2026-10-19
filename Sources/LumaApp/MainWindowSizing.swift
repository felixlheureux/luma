import AppKit

@MainActor enum MainWindowSizing {
    static let defaultSize = NSSize(width: 1200, height: 850)
    private static weak var configuredWindow: NSWindow?
    private static var qaMainObserver: NSObjectProtocol?

    static func attach(to window: NSWindow) {
        guard configuredWindow !== window else { return }
        configuredWindow = window
        if let qaMainObserver { NotificationCenter.default.removeObserver(qaMainObserver) }
        qaMainObserver = nil
        let arguments = CommandLine.arguments
        if arguments.contains(where: { $0.hasPrefix("--check-") }) {
            // Test windows must never overwrite the user's saved main-window frame.
            window.setFrameAutosaveName("")
            window.isRestorable = false
            qaMainObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { _ in
                Task { @MainActor in
                    window.setFrameAutosaveName("")
                    window.isRestorable = false
                }
            }
            // SwiftUI finishes configuring restoration after the representable
            // first attaches. Apply the QA-only policy after that setup as well.
            DispatchQueue.main.async {
                window.setFrameAutosaveName("")
                window.isRestorable = false
            }
        }
        if arguments.contains("--restore-window-size") {
            DispatchQueue.main.async { restoreDefault(window) }
        }
    }

    static func restoreDefault(_ window: NSWindow) {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let available = visible.map { window.contentRect(forFrameRect: $0).size } ?? defaultSize
        let size = NSSize(width: min(defaultSize.width, available.width), height: min(defaultSize.height, available.height))
        window.setContentSize(size)
        if let visible {
            var frame = window.frame
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
        if !window.frameAutosaveName.isEmpty { window.saveFrame(usingName: window.frameAutosaveName) }
    }
}
