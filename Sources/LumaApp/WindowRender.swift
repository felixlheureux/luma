import AppKit
import LumaCore

/// Render only views owned by this process. No display capture, audio access,
/// WindowServer image APIs or screen-recording permission is involved.
/// Native window chrome and composited glass are outside this render's scope.
@MainActor func saveWindowRender(_ window: NSWindow, path: String) throws {
    guard let view = window.contentView else { throw LumaError.rejected("No application content to render.") }
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw LumaError.rejected("Application content could not be rendered.")
    }
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    let image = NSImage(size: view.bounds.size, flipped: false) { rect in
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            bitmap.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        throw LumaError.rejected("Application render could not be encoded.")
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}
