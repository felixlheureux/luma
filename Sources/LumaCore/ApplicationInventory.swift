import Foundation

/// Display scope is intentionally smaller than fail-closed ownership discovery.
public enum ApplicationInventory {
    public static func contains(_ url: URL, home: URL) -> Bool {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains { root in
            guard Filesystem.isWithin(url, root: root), url.pathExtension == "app" else { return false }
            let relative = url.pathComponents.dropFirst(root.pathComponents.count)
            return (1...3).contains(relative.count) && relative.dropLast().allSatisfy {
                ($0 as NSString).pathExtension.isEmpty && !$0.hasPrefix(".")
            }
        }
    }

    static func urls(in root: URL, onFailure: (URL, Error) -> Void) throws -> [URL] {
        var result: [URL] = []
        var visited = 0
        func visit(_ directory: URL, depth: Int) throws {
            try Filesystem.validatePath(directory)
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isPackageKey], options: [.skipsHiddenFiles]) {
                try Task.checkCancellation()
                visited += 1
                guard visited <= 10_000 else { throw LumaError.rejected("This Applications folder exceeds the inventory limit.") }
                do {
                    let attributes = try Filesystem.attributes(url)
                    guard attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
                    try Filesystem.validatePath(url)
                    if url.pathExtension == "app" { result.append(url) }
                    else if depth < 2, url.pathExtension.isEmpty, try url.resourceValues(forKeys: [.isPackageKey]).isPackage != true {
                        try visit(url, depth: depth + 1)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { onFailure(url, error) }
            }
        }
        try visit(root, depth: 0)
        return result
    }

    /// Require both an exact identifier association and a named installed product.
    /// Independent removal utilities remain ordinary apps; names alone never hide rows.
    static func isCompanion(_ app: ApplicationRecord, among apps: [ApplicationRecord]) -> Bool {
        apps.contains { product in
            product.id != app.id && app.bundleID.lowercased() == product.bundleID.lowercased() + ".uninstaller"
                && app.name.caseInsensitiveCompare("Uninstall " + product.name) == .orderedSame
                && Filesystem.samePath(app.url.deletingLastPathComponent(), product.url.deletingLastPathComponent())
        }
    }
}
