import AppKit
import SwiftUI

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// AppKit owns the arrowless boundary and its scoped dismissal observers.
/// Content shares AppModel's existing monitor; showing it never opens main.
@MainActor final class StatusBarController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private let panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var hosting: NSHostingView<AnyView>!
    private var timer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var dismissalObservers: [NSObjectProtocol] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(model: AppModel) {
        self.model = model
        super.init()
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 18
        hosting = NSHostingView(rootView: AnyView(ScrollView { MenuCompanion(dismiss: { [weak self] in self?.hide() }).environment(model) }.scrollIndicators(.hidden)))
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        panel.contentView = glass
        refresh()
        preferenceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Preference/status refresh only; telemetry stays on the existing monitor.
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
            item.isVisible = true
            if let button = item.button {
                button.image = LumaBrand.menuBarImage()
                button.imagePosition = .imageOnly
                button.target = self; button.action = #selector(togglePanel)
            }
            statusItem = item
        } else if !enabled, let item = statusItem {
            hide(); NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
        if enabled, let item = statusItem, !item.isVisible { item.isVisible = true }
        let cpu = model.system.cpuAvailable ? "\(Int(model.system.cpu))%" : "Unavailable"
        statusItem?.button?.toolTip = "Luma · CPU \(cpu) · Memory pressure \(model.system.pressure)"
        statusItem?.button?.setAccessibilityLabel(statusItem?.button?.toolTip)
        let appearance = preferences.string(forKey: "luma.appearance") ?? "system"
        panel.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }

    /// Screen coordinates, including negative origins on secondary displays.
    static func frame(anchor: NSRect, contentSize: NSSize, visible: NSRect) -> NSRect {
        let bounds = NSRect(x: visible.minX + 8, y: visible.minY + 8, width: visible.width - 16, height: visible.height - 8)
        let size = NSSize(width: min(contentSize.width, bounds.width), height: min(contentSize.height, bounds.height))
        return NSRect(x: min(max(anchor.midX - size.width / 2, bounds.minX), bounds.maxX - size.width),
                      y: bounds.maxY - size.height, width: size.width, height: size.height)
    }

    @objc private func togglePanel() {
        if panel.isVisible { hide(); return }
        guard let button = statusItem?.button, let window = button.window, let screen = window.screen else { return }
        refresh() // Apply appearance before the first visible frame.
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let content = NSHostingView(rootView: MenuCompanion().environment(model))
        let size = content.fittingSize
        panel.setFrame(Self.frame(anchor: anchor, contentSize: size, visible: screen.visibleFrame), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hosting)
        installDismissalObservers()
    }

    private func installDismissalObservers() {
        removeDismissalObservers()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.hide(); return nil }
            if event.type != .keyDown, event.window !== self.panel, event.window !== self.statusItem?.button?.window { self.hide() }
            return event // Deliver the outside click to its original control.
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            dismissalObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            })
        }
    }

    private func removeDismissalObservers() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        for observer in dismissalObservers { NotificationCenter.default.removeObserver(observer) }
        dismissalObservers.removeAll()
    }

    private func hide() { panel.orderOut(nil); removeDismissalObservers() }

    func diagnostics() -> [String: Any] {
        ["enabled": UserDefaults.standard.bool(forKey: "luma.menuBar"),
         "created": statusItem != nil, "visible": statusItem?.isVisible ?? false,
         "autosaveName": statusItem?.autosaveName ?? "", "compact": statusItem?.length == NSStatusItem.squareLength,
         "hasImage": statusItem?.button?.image != nil, "panelVisible": panel.isVisible, "panelKey": panel.isKeyWindow,
         "dismissalObservers": dismissalObservers.count + (localMonitor == nil ? 0 : 1) + (globalMonitor == nil ? 0 : 1),
         "frame": statusItem?.button?.window.map { NSStringFromRect($0.frame) } ?? "unavailable"]
    }

    #if DEBUG
    func toggleForCheck() { statusItem?.button?.performClick(nil) }
    #endif

    func showForPreview() { if !panel.isVisible { togglePanel() } }
    func hideForPreview() { hide() }
    var previewWindow: NSWindow? { panel }
}
