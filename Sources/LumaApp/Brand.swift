import AppKit

/// One vector supplies the app icon, in-app mark, and menu-bar template.
enum LumaBrand {
    static let diagonal = NSPoint(x: 0.38, y: 0.435)
    // Opposite endpoints keep the diagonal through the circle's exact center.
    static let vertices: [(CGFloat, CGFloat)] = [
        (0.5 - diagonal.x, 0.5 - diagonal.y),
        (0.5 + diagonal.x, 0.5 + diagonal.y),
        (-0.5, 1.5)
    ]
    @MainActor static func drawGlyph(in rect: NSRect, tint: NSColor, shaded: Bool = false) {
        let side = rect.width
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + side * x, y: rect.minY + side * y)
        }
        let circle = NSBezierPath(ovalIn: NSRect(x: rect.minX + side * 0.235, y: rect.minY + side * 0.235, width: side * 0.53, height: side * 0.53))
        circle.lineWidth = side * 0.035
        tint.setStroke(); circle.stroke()
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        let moon = NSBezierPath()
        moon.move(to: point(vertices[0].0, vertices[0].1))
        for vertex in vertices.dropFirst() { moon.line(to: point(vertex.0, vertex.1)) }
        moon.close()
        if shaded {
            NSGradient(colors: [tint, tint.withAlphaComponent(0.48)])!.draw(in: moon, angle: -60)
        } else { tint.setFill(); moon.fill() }
        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor static func glyphImage(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Fit the same icon geometry into a compact glyph without its purple tile.
            let scale = (rect.width - 2) / 0.565
            let drawingRect = NSRect(x: rect.midX - scale / 2, y: rect.midY - scale / 2, width: scale, height: scale)
            drawGlyph(in: drawingRect, tint: template ? .black : .white)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Luma"
        return image
    }

    @MainActor static func menuBarImage() -> NSImage { glyphImage(size: 18, template: true) }

    static func svg() -> String {
        let coordinates = vertices.map { "\($0.0 * 128) \((1 - $0.1) * 128)" }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128" role="img" aria-label="Luma">
          <defs><linearGradient id="purple" x2="1" y2="1"><stop stop-color="#a8a6ff"/><stop offset="1" stop-color="#4f4cc4"/></linearGradient><clipPath id="moon"><circle cx="64" cy="64" r="33.92"/></clipPath></defs>
          <rect x="7.04" y="7.04" width="113.92" height="113.92" rx="28.16" fill="url(#purple)"/>
          <circle cx="64" cy="64" r="33.92" fill="none" stroke="#fff" stroke-width="4.48"/>
          <path d="M\(coordinates[0])L\(coordinates[1])L\(coordinates[2])Z" fill="#fff" clip-path="url(#moon)"/>
        </svg>
        """
    }
}
