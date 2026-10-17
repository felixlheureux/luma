import Foundation
import CryptoKit
import Darwin

public enum Filesystem {
    public static func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    /// Reject links in any component, including a replaced parent directory.
    public static func validatePath(_ url: URL) throws {
        guard url.isFileURL, url.path != "/" else { throw LumaError.rejected("Protected or invalid path.") }
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
            guard values.isSymbolicLink != true, values.isAliasFile != true else {
                throw LumaError.rejected("Links and aliases are excluded: \(cursor.lastPathComponent)")
            }
            cursor.deleteLastPathComponent()
        }
    }

    static func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    public static func inspect(_ url: URL, limit: Int = 250_000, progress: (@Sendable (Int, Int64) -> Void)? = nil) throws -> (Int64, FileIdentity) {
        try Task.checkCancellation()
        try validatePath(url)
        let root = try attributes(url)
        let device = (root[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        var size: Int64 = 0
        var records: [String] = []
        var seen: Set<String> = []
        var count = 0
        var lastUpdate = ContinuousClock.now
        let bundleLinksAllowed = url.pathExtension == "app" && Bundle(url: url) != nil
        func visit(_ child: URL) throws {
            try Task.checkCancellation()
            let a = try attributes(child)
            if a[.type] as? FileAttributeType == .typeSymbolicLink {
                // Framework version links are common inside application bundles. Moving
                // the enclosing bundle does not traverse them; external targets are rejected.
                guard bundleLinksAllowed, isWithin(child.resolvingSymlinksInPath(), root: url) else {
                    throw LumaError.rejected("Contains a symbolic link outside an application bundle; excluded from cleanup.")
                }
                records.append("link|\(child.path.replacingOccurrences(of: url.path, with: "", options: .anchored))|\(try FileManager.default.destinationOfSymbolicLink(atPath: child.path))")
                return
            }
            let dev = (a[.systemNumber] as? NSNumber)?.uint64Value ?? 0
            guard dev == device else { throw LumaError.rejected("A volume boundary was encountered.") }
            let inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let bytes = (a[.size] as? NSNumber)?.int64Value ?? 0
            let date = a[.modificationDate] as? Date ?? .distantPast
            records.append("\(child.path.replacingOccurrences(of: url.path, with: "", options: .anchored))|\(dev)|\(inode)|\(bytes)|\(date.timeIntervalSince1970)|\(a[.type] ?? "")")
            if a[.type] as? FileAttributeType == .typeRegular, seen.insert("\(dev):\(inode)").inserted {
                size += bytes
            }
            count += 1
            if count == 1 || (count % 128 == 0 && lastUpdate.duration(to: .now) >= .milliseconds(120)) {
                progress?(count, size); lastUpdate = .now
            }
            guard count <= limit else { throw LumaError.rejected("Item exceeds the current scan limit; narrow your selection.") }
        }
        try visit(url)
        if root[.type] as? FileAttributeType == .typeDirectory {
            var failure: Error?
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in failure = error; return false }) else {
                throw LumaError.rejected("This folder could not be read.")
            }
            for case let child as URL in walker { try visit(child) }
            if let failure { throw failure }
        }
        progress?(count, size)
        let digest = SHA256.hash(data: Data(records.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return (size, FileIdentity(device: device, inode: (root[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                                   size: (root[.size] as? NSNumber)?.int64Value ?? 0,
                                   modified: root[.modificationDate] as? Date ?? .distantPast, treeDigest: digest))
    }

    public static func item(_ url: URL, category: ItemCategory, safety: SafetyLevel,
                            explanation: String, consequence: String, rule: String,
                            owner: String? = nil, progress: (@Sendable (Int, Int64) -> Void)? = nil) throws -> CleanupItem {
        let (size, identity) = try inspect(url, progress: progress)
        return CleanupItem(url: url, bytes: size, category: category, safety: safety,
                           explanation: explanation, consequence: consequence, ruleID: rule,
                           ownerBundleID: owner, identity: identity, scannedAt: Date())
    }

    public static func hash(_ url: URL, partial: Bool = false) throws -> String {
        try validatePath(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: partial ? 65_536 : 1_048_576), !data.isEmpty else { break }
            digest.update(data: data)
            if partial { break }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
