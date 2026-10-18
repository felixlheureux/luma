import Foundation
import ImageIO
import Darwin

public enum DownloadPreview: Sendable {
    case text(String, truncated: Bool)
    case png(Data)
    case unavailable(String)
}

public enum DownloadPreviewReader {
    /// Only pinned local bytes reach built-in text/ImageIO decoders. No Quick
    /// Look extensions, URL renderers, package handlers or file-path image loads.
    public static func read(_ file: DownloadFile) throws -> DownloadPreview {
        guard let item = file.item, file.kind != .incomplete else {
            return .unavailable("This excluded or possibly incomplete file cannot be previewed.")
        }
        let ext = file.url.pathExtension.lowercased()
        let textTypes: Set<String> = ["txt", "md", "csv", "log", "json", "yaml", "yml", "swift", "rs", "js", "ts", "css"]
        let rasterTypes: Set<String> = ["png", "jpg", "jpeg"]
        guard textTypes.contains(ext) || rasterTypes.contains(ext) else {
            return .unavailable("No inline preview for this type. Installers, archives, HTML and executable content are never opened by this preview.")
        }
        guard Date().timeIntervalSince(item.scannedAt) < 1_800 else { throw LumaError.rejected("Scan again before previewing this file.") }
        return try NonMaterializingIO.perform {
            let pin = try PinnedPath(file.url)
            guard let location = item.identity.location else { throw LumaError.rejected("Scan again before previewing this file.") }
            try pin.revalidate(expected: location)
            guard pin.value.st_mode & S_IFMT == S_IFREG, pin.value.st_nlink == 1,
                  try Filesystem.inspect(file.url).1 == item.identity else { throw LumaError.rejected("This file changed. Scan again before previewing.") }
            let limit = textTypes.contains(ext) ? 65_536 : 10_000_000
            if rasterTypes.contains(ext), pin.value.st_size > limit { return .unavailable("Image exceeds the 10 MB inline preview limit.") }
            let handle = FileHandle(fileDescriptor: try pin.openReadableRegularFile(), closeOnDealloc: true)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: limit) ?? Data()
            try Task.checkCancellation()
            try pin.revalidate(expected: item.identity.location)
            guard try Filesystem.inspect(file.url).1 == item.identity else { throw LumaError.rejected("The file changed while previewing. Scan again.") }
            if textTypes.contains(ext) {
                var prefix = data
                // A byte limit may cut the final UTF-8 scalar. Remove only that
                // incomplete suffix, never reinterpret binary as readable text.
                var text = String(data: prefix, encoding: .utf8)
                for _ in 0..<3 where text == nil && !prefix.isEmpty && item.bytes > data.count {
                    prefix.removeLast(); text = String(data: prefix, encoding: .utf8)
                }
                guard let text, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && ![9, 10, 13].contains($0.value) }) else {
                    return .unavailable("This file does not contain supported plain UTF-8 text.")
                }
                return .text(text, truncated: item.bytes > prefix.count)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_384, height <= 16_384,
                  Int64(width) * Int64(height) <= 100_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return .unavailable("This image format or dimensions are unsupported for inline preview.") }
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, "public.png" as CFString, 1, nil) else { return .unavailable("Preview unavailable.") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return .unavailable("Preview unavailable.") }
            return .png(result as Data)
        }
    }
}
