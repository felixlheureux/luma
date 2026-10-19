import SwiftUI

extension View {
    /// A debug-only geometry marker. QA still delivers real native events to controls.
    @ViewBuilder func nativeCheckTarget(_ name: String) -> some View {
        #if DEBUG
        background(NativeCheckTarget(name: name).allowsHitTesting(false))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct NativeCheckTarget: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("luma-check-" + name)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { view.identifier = NSUserInterfaceItemIdentifier("luma-check-" + name) }
}
#endif
