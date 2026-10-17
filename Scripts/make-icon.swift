import AppKit

// An original vector-drawn icon. No assets are taken from the reference app.
@main struct IconGenerator {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try LumaBrand.svg().write(to: root.appendingPathComponent("Luma.svg"), atomically: true, encoding: .utf8)
        let folder = root.appendingPathComponent("Luma.iconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            let size = CGFloat(pixels)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let rect = NSRect(x: size * 0.055, y: size * 0.055, width: size * 0.89, height: size * 0.89)
            let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
            NSGradient(colors: [NSColor(red: 0.66, green: 0.65, blue: 1, alpha: 1), NSColor(red: 0.31, green: 0.30, blue: 0.77, alpha: 1)])!.draw(in: tile, angle: -65)
            LumaBrand.drawGlyph(in: NSRect(x: 0, y: 0, width: size, height: size), tint: NSColor.white.withAlphaComponent(0.94), shaded: true)
            NSGraphicsContext.restoreGraphicsState()
            let data = rep.representation(using: .png, properties: [:])!
            var names: [String] = []
            if [16, 32, 128, 256, 512].contains(pixels) { names.append("icon_\(pixels)x\(pixels).png") }
            if [32, 64, 256, 512, 1024].contains(pixels) { names.append("icon_\(pixels / 2)x\(pixels / 2)@2x.png") }
            for name in names { try data.write(to: folder.appendingPathComponent(name)) }
        }

    }
}
