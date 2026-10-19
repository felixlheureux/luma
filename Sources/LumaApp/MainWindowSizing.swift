import AppKit

@MainActor enum MainWindowSizing {
    static let defaultSize = NSSize(width: 1200, height: 850)
    private static weak var configuredWindow: NSWindow?
    private static var mainObserver: NSObjectProtocol?

    static func attach(to window: NSWindow) {
        guard configuredWindow !== window else { return }
        configuredWindow = window
        if let mainObserver { NotificationCenter.default.removeObserver(mainObserver) }
        mainObserver = nil
        // Never retain a temporary window size between launches or openings.
        window.setFrameAutosaveName("")
        window.isRestorable = false
        mainObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { [weak window] _ in
            Task { @MainActor in
                window?.setFrameAutosaveName("")
                window?.isRestorable = false
            }
        }
        // SwiftUI configures restoration after the representable first attaches.
        DispatchQueue.main.async {
            window.setFrameAutosaveName("")
            window.isRestorable = false
            restoreDefault(window)
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
    }
}
