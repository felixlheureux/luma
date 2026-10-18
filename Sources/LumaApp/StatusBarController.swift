import AppKit
import SwiftUI

/// AppKit owns the status item and popover lifecycle. SwiftUI owns panel content.
/// Keeping this outside the app's Scene graph avoids a macOS 27 MenuBarExtra
/// invalidation loop and prevents live samples from rebuilding scene menus.
@MainActor final class StatusBarController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var previousAppearance = ""

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuCompanion(dismiss: { [weak self] in self?.popover.close() }).environment(model))
        refresh()
        preferenceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh() {
        let preferences = UserDefaults.standard
        let enabled = preferences.bool(forKey: "luma.menuBar")
        if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "Luma.MenuBar"
            // The earlier MenuBarExtra used an automatically assigned name whose
            // persisted visibility could disagree with our own enabled setting.
            item.isVisible = true
            if let button = item.button {
                button.image = LumaBrand.menuBarImage()
                button.imagePosition = .imageOnly
                button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                button.target = self; button.action = #selector(togglePopover)
            }
            statusItem = item
        } else if !enabled, let item = statusItem {
            popover.close(); NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
        if enabled, let item = statusItem, !item.isVisible { item.isVisible = true }
        statusItem?.button?.title = ""
        statusItem?.button?.toolTip = "Luma · CPU \(Int(model.system.cpu))% · Memory pressure \(model.system.pressure)"
        statusItem?.button?.setAccessibilityLabel("Luma · CPU \(Int(model.system.cpu)) percent · Memory pressure \(model.system.pressure)")
        let appearance = preferences.string(forKey: "luma.appearance") ?? "system"
        if appearance != previousAppearance {
            popover.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
            previousAppearance = appearance
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func diagnostics() -> [String: Any] {
        ["enabled": UserDefaults.standard.bool(forKey: "luma.menuBar"),
         "created": statusItem != nil, "visible": statusItem?.isVisible ?? false,
         "autosaveName": statusItem?.autosaveName ?? "", "compact": statusItem?.length == NSStatusItem.squareLength,
         "hasImage": statusItem?.button?.image != nil,
         "frame": statusItem?.button?.window.map { NSStringFromRect($0.frame) } ?? "unavailable"]
    }

    func showForPreview() { if !popover.isShown { togglePopover() } }
    func hideForPreview() { popover.performClose(nil) }
    var previewWindow: NSWindow? { popover.contentViewController?.view.window }
}
