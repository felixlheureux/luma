#if DEBUG
import SwiftUI
import AppKit
import LumaCore

extension LumaAppDelegate {
    /// Native pointer/keyboard events with disposable observations. No cleanup.
    func checkOverviewInput(output: String) {
        Task { @MainActor in
            let model = AppModel.shared
            let args = CommandLine.arguments
            let rootFlag = args.firstIndex(of: "--overview-fixture-root")
            let root = rootFlag.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                ?? FileManager.default.currentDirectoryPath + "/.build/Fixtures"
            let home = URL(fileURLWithPath: root).appendingPathComponent("overview-input-\(UUID())")
            var report: [String: Any] = ["mutationInvoked": false, "personalFoldersScanned": false]
            let originalCollector = model.monitoringCollector
            let originalAppearance = UserDefaults.standard.object(forKey: "luma.appearance")
            var checkedWindow: NSWindow?
            var originalFrame: NSRect?
            defer {
                if let checkedWindow, let originalFrame { checkedWindow.setFrame(originalFrame, display: true) }
                model.monitoringCollector = originalCollector
                if let originalAppearance { UserDefaults.standard.set(originalAppearance, forKey: "luma.appearance") }
                else { UserDefaults.standard.removeObject(forKey: "luma.appearance") }
                try? FileManager.default.removeItem(at: home)
                NSApp.terminate(nil)
            }
            @MainActor func require(_ value: Bool, _ name: String) throws {
                report[name] = value
                guard value else { throw LumaError.rejected(name) }
            }
            @MainActor func pause() async throws { try await Task.sleep(for: .milliseconds(200)) }
            @MainActor func waitFor(_ predicate: @MainActor () -> Bool) async throws {
                let deadline = Date().addingTimeInterval(3)
                while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
            }
            @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
            @MainActor func click(_ window: NSWindow, _ point: NSPoint) throws {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw LumaError.rejected("No pointer event") }
                    NSApp.postEvent(event, atStart: false)
                }
            }
            @MainActor func clickElement(_ window: NSWindow, label: String) throws {
                guard let view = window.contentView.flatMap({ descendants($0).first { $0.identifier?.rawValue == "luma-check-" + label } }) else {
                    throw LumaError.rejected("No native control marker: " + label)
                }
                let frame = view.convert(view.bounds, to: nil)
                try click(window, NSPoint(x: frame.midX, y: frame.midY))
            }
            @MainActor func key(_ window: NSWindow, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = [], application: Bool = false) throws {
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw LumaError.rejected("No keyboard event") }
                if application { NSApp.sendEvent(event) } else { window.sendEvent(event) }
            }
            @MainActor func searchWindow() async throws -> NSWindow {
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.className == "_NSPopoverWindow" }) { return window }
                    try await Task.sleep(for: .milliseconds(30))
                }
                throw LumaError.rejected("No Search window")
            }
            @MainActor func editing(_ window: NSWindow) -> Bool { (window.firstResponder as? NSTextView)?.isEditable == true }
            @MainActor func focusField(_ window: NSWindow) async throws -> NSTextField {
                if !window.isKeyWindow || !NSApp.isActive {
                    window.makeKeyAndOrderFront(nil); NSRunningApplication.current.activate(options: [])
                    try await waitFor { window.isKeyWindow && NSApp.isActive }
                }
                try require(window.isKeyWindow && NSApp.isActive, "inputWindowActive")
                guard let content = window.contentView,
                      let field = descendants(content).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }) else {
                    throw LumaError.rejected("No editable field")
                }
                let rect = field.convert(field.bounds, to: nil)
                try click(window, NSPoint(x: rect.midX, y: rect.midY))
                try await pause()
                try require(editing(window), "fieldFocused-\(model.destination?.rawValue ?? "Search")")
                return field
            }
            do {
                try require(model.destination == .overview, "launchOverview")
                try require(Destination.core == [.overview, .storage, .applications, .residues, .maintenance, .system], "primaryRouteOrder")
                try await Task.sleep(for: .seconds(2))
                guard let window = model.mainWindow else { throw LumaError.rejected("No main window") }
                checkedWindow = window; originalFrame = window.frame
                window.setContentSize(NSSize(width: 1100, height: 850)); window.makeKeyAndOrderFront(nil); NSRunningApplication.current.activate(options: [])
                model.openCore(.overview); try await pause()
                try require(model.destination == .overview && model.storageDiscovery.session == nil, "explicitOverviewIdle")
                try clickElement(window, label: "overview-Storage"); try await pause()
                try require(model.destination == .storage && model.storageDiscovery.session == nil, "overviewStorageShortcutIdle")
                for page in Destination.core where page != .overview {
                    model.openCore(.overview); try await pause()
                    try clickElement(window, label: "overview-" + page.id); try await pause()
                    try require(model.destination == page, "overviewLink-" + page.id)
                }
                for (offset, page) in (Destination.core + [.history]).enumerated() {
                    let character = page == .history ? "9" : String(offset + 1)
                    guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                        characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 18) else { throw LumaError.rejected("No route key event") }
                    NSApp.sendEvent(event); try await pause()
                    try require(model.destination == page, "command-" + character)
                }
                try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches/org.lumatest.focus"), withIntermediateDirectories: true)
                try Data("disposable".utf8).write(to: home.appendingPathComponent("Library/Caches/org.lumatest.focus/data"))
                model.uninstallHome = home
                let item = try Filesystem.item(home.appendingPathComponent("Library/Caches/org.lumatest.focus"), category: .related, safety: .review,
                    explanation: "Exact disposable owner path", consequence: "The fixture app would regenerate this cache.", rule: "application.leftover.exact-identifier", owner: "org.lumatest.focus")
                model.leftovers = [item]; model.didScanLeftovers = true
                model.applications = [ApplicationRecord(url: home.appendingPathComponent("Fixture.app"), name: "Fixture", bundleID: "org.lumatest.fixture", version: "1", bytes: 20)]
                model.completedScans.insert(.applications)
                let scanned = try await ScanEngine.run(.init(.storage, root: home), home: home, applicationRoots: [])
                guard let index = scanned.storageIndex else { throw LumaError.rejected("No fixture Storage index") }
                model.publishStorage(index)
                for appearance in ["light", "dark", "system"] {
                    UserDefaults.standard.set(appearance, forKey: "luma.appearance")
                    for page in [Destination.applications, .residues, .storage] {
                        model.openCore(page); try await pause()
                        let field = try await focusField(window)
                        (window.firstResponder as? NSTextView)?.insertText("focus", replacementRange: NSRange(location: 0, length: field.stringValue.count))
                        try await pause()
                        let value = field.stringValue
                        try click(window, NSPoint(x: window.contentView!.bounds.width - 30, y: window.contentView!.bounds.height - 95))
                        try await waitFor { !editing(window) }
                        if editing(window) || field.stringValue != value {
                            report["focusFailure"] = ["before": value, "after": field.stringValue, "responder": String(describing: window.firstResponder),
                                "observers": window.contentView?.gestureRecognizers.map { $0.className } ?? [],
                                "key": window.isKeyWindow, "active": NSApp.isActive, "click": ClickAwayEditing.lastClick]
                            try saveScanCheckWindow(window, path: output + "-focus-failure.png")
                        }
                        try require(!editing(window) && field.stringValue == value, "\(appearance)-\(page.rawValue)-backgroundPreservesValue")
                        _ = try await focusField(window)
                        if page == .residues {
                            guard let group = LeftoverGroup.groups(for: model.visibleResidues).first else { throw LumaError.rejected("No residue group") }
                            model.residueSelection = [:]
                            try clickElement(window, label: "residue-group-" + group.id); try await pause()
                            try require(!editing(window) && model.residueSelection.count == 1, "\(appearance)-checkboxFirstClick")
                            model.residueSelection = [:]
                        } else {
                            try clickElement(window, label: "Activity"); try await pause()
                            try require(model.destination == .history && !editing(window), "\(appearance)-\(page.rawValue)-buttonFirstClick")
                        }
                        model.applicationSearch = ""; model.storageSearch = ""
                    }
                    model.openCore(.overview); model.showingSearch = false
                    window.makeKeyAndOrderFront(nil); NSRunningApplication.current.activate(options: []); try await pause()
                    model.search = ""
                    try key(window, code: 40, characters: "k", modifiers: .command, application: true)
                    let search = try await searchWindow(); try await pause()
                    try require(model.showingSearch, "\(appearance)-commandK")
                    try require(editing(search), "\(appearance)-searchOpeningFocus")
                    (search.firstResponder as? NSTextView)?.insertText("Over", replacementRange: NSRange(location: NSNotFound, length: 0)); try await pause()
                    try click(search, NSPoint(x: 380, y: 25))
                    try await waitFor { !editing(search) }
                    if editing(search) || model.search != "Over" {
                        report["focusFailure"] = ["search": model.search, "click": ClickAwayEditing.lastClick,
                            "key": search.isKeyWindow, "active": NSApp.isActive]
                    }
                    try require(!editing(search) && model.search == "Over", "\(appearance)-searchBackground")
                    _ = try await focusField(search)
                    try clickElement(search, label: "search-page:Overview"); try await pause()
                    try require(!model.showingSearch && model.destination == .overview, "\(appearance)-searchResultFirstClick")
                    model.search = ""; model.showingSearch = true; try await pause()
                    let keyboardSearch = try await searchWindow()
                    try key(keyboardSearch, code: 125, characters: "\u{F701}"); try key(keyboardSearch, code: 36, characters: "\r"); try await pause()
                    try require(!model.showingSearch && model.destination == .storage, "\(appearance)-searchArrowReturn")
                    model.showingSearch = true; try await pause()
                    if let search = NSApp.windows.first(where: { $0.isVisible && $0.className == "_NSPopoverWindow" }) {
                        try key(search, code: 48, characters: "\t"); try key(search, code: 48, characters: "\t", modifiers: .shift)
                        try key(search, code: 53, characters: "\u{1b}")
                    }
                    try await pause(); try require(!model.showingSearch, "\(appearance)-searchEscapeAfterTab")
                    window.setContentSize(NSSize(width: 760, height: 650))
                    model.openCore(.residues); try await pause()
                    try saveScanCheckWindow(window, path: output + "-\(appearance)-residues.png")
                    model.openCore(.storage); try await pause()
                    try saveScanCheckWindow(window, path: output + "-\(appearance)-footer.png")
                    model.openCore(.overview); try await pause()
                    try saveScanCheckWindow(window, path: output + "-\(appearance)-overview.png")
                    window.setContentSize(NSSize(width: 1100, height: 850))
                }
                let collecting = SystemSample()
                model.monitoringCollector = { _, _ in collecting }
                model.system = collecting; model.openCore(.overview); try await pause()
                try saveScanCheckWindow(window, path: output + "-collecting.png")
                var unavailable = SystemSample(); unavailable.sampledAt = Date().addingTimeInterval(-60)
                let stale = unavailable
                model.monitoringCollector = { _, _ in stale }
                model.system = stale; try await pause()
                try saveScanCheckWindow(window, path: output + "-unavailable-stale.png")
                // Run the separate AppKit fixture last: closing its key window can
                // yield activation to another app, outside the main-view checks.
                let inputWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
                inputWindow.isReleasedWhenClosed = false
                let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 160))
                let first = NSTextField(frame: NSRect(x: 20, y: 100, width: 260, height: 24))
                let second = NSTextField(frame: NSRect(x: 20, y: 50, width: 260, height: 24))
                let host = ClickAwayEditing.Host()
                content.addSubview(first); content.addSubview(second); content.addSubview(host)
                inputWindow.contentView = content; inputWindow.makeKeyAndOrderFront(nil)
                try await pause()
                try click(inputWindow, NSPoint(x: 100, y: 112)); try await pause()
                (inputWindow.firstResponder as? NSTextView)?.insertText("kept", replacementRange: NSRange(location: NSNotFound, length: 0))
                try click(inputWindow, NSPoint(x: 100, y: 62)); try await pause()
                try require(second.currentEditor() === inputWindow.firstResponder && first.stringValue == "kept", "fieldTransferFirstClick")
                host.removeFromSuperview()
                try require(content.gestureRecognizers.isEmpty, "observerRemovedWithHost")
                inputWindow.close()
                model.openCore(.storage)
                window.close(); model.openMain(); try await pause()
                try require(model.destination == .storage && window.isVisible, "reopenPreservesRoute")
            } catch { report["error"] = error.localizedDescription }
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
}
#endif
