import AppKit

enum LumaBrand {
    static let symbol = "circle.lefthalf.filled"
    static let rotation = -35.0

    @MainActor static func menuBarImage() -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: "Luma")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) else { return nil }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            // AppKit's Y axis points up; SwiftUI's points down.
            transform.rotate(byDegrees: -rotation)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            symbol.draw(in: rect.insetBy(dx: 1, dy: 1), from: .zero, operation: .sourceOver,
                        fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Luma"
        return image
    }
}
