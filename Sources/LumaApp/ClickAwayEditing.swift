import SwiftUI
import AppKit

/// Observe only this host's window content. Never consume, delay or repost a click.
/// The main host and Search popover each own and remove their own recognizer.
struct ClickAwayEditing: NSViewRepresentable {
    #if DEBUG
    static var lastClick: [String: String] = [:]
    #endif
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) {}
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.detach() }

    final class Host: NSView {
        private let observer = EditingClickObserver(target: nil, action: nil)
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let content = window?.contentView else { return }
            observer.delaysPrimaryMouseButtonEvents = false
            content.addGestureRecognizer(observer)
        }
        func detach() { observer.view?.removeGestureRecognizer(observer) }
    }
}

private final class EditingClickObserver: NSGestureRecognizer {
    override func mouseDown(with event: NSEvent) {
        defer { state = .failed }
        #if DEBUG
        ClickAwayEditing.lastClick = ["point": NSStringFromPoint(event.locationInWindow), "state": String(describing: state)]
        #endif
        guard let view, let window = view.window, event.window === window,
              let editor = window.firstResponder as? NSTextView, editor.isEditable else { return }
        // AppKit hitTest expects the receiver's superview coordinates.
        let point = view.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        var hit = view.hitTest(point)
        while let candidate = hit {
            #if DEBUG
            ClickAwayEditing.lastClick["hit"] = (ClickAwayEditing.lastClick["hit"] ?? "") + candidate.className + " > "
            #endif
            // Leave text selection, insertion and transfers between fields to AppKit.
            if let field = candidate as? NSTextField, field.isEditable { return }
            if let text = candidate as? NSTextView, text.isEditable { return }
            hit = candidate.superview
        }
        let ended = window.makeFirstResponder(nil)
        #if DEBUG
        ClickAwayEditing.lastClick["ended"] = String(ended)
        ClickAwayEditing.lastClick["responder"] = String(describing: window.firstResponder)
        #endif
    }
    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool { false }
}
