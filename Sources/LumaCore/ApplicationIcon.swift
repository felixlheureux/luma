import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Read bounded local resource bytes, never Finder/Quick Look or a service that
/// can fetch an app/provider icon on our behalf. Unsupported assets use a symbol.
public enum ApplicationIcon {
    static func png(bundle: URL, metadata: [String: Any]) throws -> Data? {
        do {
            return try NonMaterializingIO.perform {
                try Task.checkCancellation()
                let pin = try PinnedPath(bundle)
                guard let name = (metadata["CFBundleIconFile"] as? String) ?? (metadata["CFBundleIconName"] as? String), !name.isEmpty,
                      !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".") else { return nil }
                let filename = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
                let resource = bundle.exactAppendingPathComponent("Contents").exactAppendingPathComponent("Resources").exactAppendingPathComponent(filename)
                let data = try Filesystem.readMetadata(resource, limit: 16_777_216)
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 128 else { return nil }
                // ICNS can contain several representations. Prefer a source at
                // least as large as the display thumbnail over a tiny first image.
                var best: (index: Int, score: Int)?
                for index in 0..<CGImageSourceGetCount(source) {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 8192, height <= 8192 else { continue }
                    let side = max(width, height)
                    let score = abs(side - 96) + (side < 96 ? 8192 : 0)
                    if score < (best?.score ?? .max) { best = (index, score) }
                }
                guard let best, let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, best.index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 96,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary) else { return nil }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(destination, thumbnail, nil)
                guard CGImageDestinationFinalize(destination), output.length <= 131_072 else { return nil }
                try pin.revalidate()
                return output as Data
            }
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
}
