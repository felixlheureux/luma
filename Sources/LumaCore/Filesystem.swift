import Foundation
import CryptoKit
import Darwin

struct FileObjectID: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    init(_ identity: FileIdentity) { device = identity.device; inode = identity.inode }
    init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }
}

public enum Filesystem {
    static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        Data(lhs.exactStandardizedFileURL.path.utf8) == Data(rhs.exactStandardizedFileURL.path.utf8)
    }

    public static func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.exactStandardizedFileURL.path
        let base = root.exactStandardizedFileURL.path
        return Data(path.utf8) == Data(base.utf8) || Data(path.utf8).starts(with: Data((base + "/").utf8))
    }

    /// Reject links in any component, including a replaced parent directory.
    public static func validatePath(_ url: URL) throws {
        let pinned = try PinnedPath(url)
        try pinned.revalidate()
    }

    static func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        try NonMaterializingIO.perform {
            try FilesystemAccess.requireLocal(url)
            return try FileManager.default.attributesOfItem(atPath: url.path)
        }
    }

    public static func inspect(_ url: URL, limit: Int = 250_000, progress: (@Sendable (Int, Int64) -> Void)? = nil) throws -> (Int64, FileIdentity) {
        try inspect(url, limit: limit, progress: progress, onFile: nil)
    }

    /// The plan uses the same inspection to count content once across separate
    /// selected trees. This callback is synchronous and never escapes inspection.
    static func inspect(_ url: URL, limit: Int = 250_000, progress: (@Sendable (Int, Int64) -> Void)? = nil,
                        onFile: ((FileObjectID, Int64) throws -> Void)?, legacyFingerprint: Bool = false) throws -> (Int64, FileIdentity) {
        return try NonMaterializingIO.perform {
            try Task.checkCancellation()
            let pinned = try PinnedPath(url)
            let root = pinned.value
            let device = UInt64(UInt32(bitPattern: root.st_dev))
            var size: Int64 = 0
            var records: [Data] = []
            var legacyRecords: [String] = []
            var seen: Set<FileObjectID> = []
            var count = 0
            var lastUpdate = ContinuousClock.now
            let bundleLinksAllowed = url.pathExtension == "app" && (try? applicationIdentifier(at: url)) != nil

            // Length-prefixed fields and byte sorting preserve delimiters, newlines,
            // case, and canonically equivalent Unicode names without String equality.
            func record(_ fields: [Data]) {
                var data = Data()
                for field in fields {
                    var length = UInt64(field.count).bigEndian
                    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                    data.append(field)
                }
                records.append(data)
            }
            func visit(_ fd: Int32, info: stat, relative: String, path: URL, depth: Int) throws {
                try Task.checkCancellation()
                try FilesystemAccess.check(path, metadata: info, descriptor: fd)
                guard depth <= 256 else { throw LumaError.rejected("This tree is too deep; narrow your selection.") }
                guard UInt64(UInt32(bitPattern: info.st_dev)) == device else {
                    throw LumaError.rejected("A volume boundary was encountered.")
                }
                guard info.st_uid == root.st_uid else { throw LumaError.rejected("This tree contains an item owned by another user.") }
                guard try path.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile != true else {
                    throw LumaError.rejected("Finder aliases are excluded from cleanup.")
                }
                if legacyFingerprint {
                    let a = try attributes(path)
                    let date = a[.modificationDate] as? Date ?? .distantPast
                    legacyRecords.append("\(relative)|\(device)|\(info.st_ino)|\(info.st_size)|\(date.timeIntervalSince1970)|\(a[.type] ?? "")")
                }
                count += 1
                guard count <= limit else { throw LumaError.rejected("Item exceeds the current scan limit; narrow your selection.") }
                record([Data(relative.utf8)] + ["object-v2", String(info.st_dev), String(info.st_ino), String(info.st_size),
                    String(info.st_mtimespec.tv_sec), String(info.st_mtimespec.tv_nsec), String(info.st_mode), String(info.st_uid)].map { Data($0.utf8) })
                let object = FileObjectID(device: device, inode: info.st_ino)
                if info.st_mode & S_IFMT == S_IFREG, seen.insert(object).inserted {
                    size += info.st_size
                    try onFile?(object, info.st_size)
                }
                if count == 1 || (count % 128 == 0 && lastUpdate.duration(to: .now) >= .milliseconds(120)) {
                    progress?(count, size); lastUpdate = .now
                }
                if info.st_mode & S_IFMT == S_IFDIR {
                    for name in try PinnedPath.names(in: fd) {
                        let child = path.exactAppendingPathComponent(name)
                        let childRelative = relative + "/" + name
                        var metadata = stat()
                        guard fstatat(fd, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw PinnedPath.posixError() }
                        if metadata.st_mode & S_IFMT == S_IFLNK {
                            count += 1
                            guard count <= limit, bundleLinksAllowed,
                                  UInt64(UInt32(bitPattern: metadata.st_dev)) == device,
                                  metadata.st_uid == root.st_uid else {
                                throw LumaError.rejected("Contains an unsupported symbolic link; excluded from cleanup.")
                            }
                            var bytes = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
                            let length = readlinkat(fd, name, &bytes, bytes.count)
                            guard length > 0, length < bytes.count else { throw LumaError.rejected("An application link could not be inspected.") }
                            let target = child.resolvingSymlinksInPath()
                            guard isWithin(target, root: url) else { throw LumaError.rejected("An application link points outside its bundle.") }
                            let targetPin = try PinnedPath(target)
                            guard UInt64(UInt32(bitPattern: targetPin.value.st_dev)) == device else {
                                throw LumaError.rejected("An application link crosses a volume boundary.")
                            }
                            try targetPin.revalidate()
                            if legacyFingerprint {
                                legacyRecords.append("link|\(childRelative)|\(try FileManager.default.destinationOfSymbolicLink(atPath: child.path))")
                            }
                            var current = stat()
                            guard fstatat(fd, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                                  FileLocation.Component(current) == FileLocation.Component(metadata),
                                  current.st_size == metadata.st_size,
                                  current.st_mtimespec.tv_sec == metadata.st_mtimespec.tv_sec,
                                  current.st_mtimespec.tv_nsec == metadata.st_mtimespec.tv_nsec else {
                                throw LumaError.rejected("An application link changed during inspection.")
                            }
                            record([Data(childRelative.utf8), Data("link-v2".utf8), Data(bytes.prefix(length))]
                                + [String(metadata.st_dev), String(metadata.st_ino), String(metadata.st_uid), String(metadata.st_mode),
                                   String(metadata.st_mtimespec.tv_sec), String(metadata.st_mtimespec.tv_nsec)].map { Data($0.utf8) })
                            continue
                        }
                        let (childFD, childInfo) = try PinnedPath.openChild(fd, name: name)
                        defer { close(childFD) }
                        try visit(childFD, info: childInfo, relative: childRelative, path: child, depth: depth + 1)
                        var current = stat()
                        guard fstatat(fd, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                              FileLocation.Component(current) == FileLocation.Component(childInfo) else {
                            throw LumaError.rejected("A tree entry was replaced during inspection. Scan again.")
                        }
                    }
                }
                var after = stat()
                guard fstat(fd, &after) == 0,
                      FileLocation.Component(after) == FileLocation.Component(info),
                      after.st_size == info.st_size, after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                      after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else {
                    throw LumaError.rejected("Files changed during inspection. Scan again.")
                }
            }
            try visit(pinned.descriptor, info: root, relative: "", path: url, depth: 0)
            try pinned.revalidate()
            progress?(count, size)
            var digest = SHA256()
            for record in records.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                var length = UInt64(record.count).bigEndian
                withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
                digest.update(data: record)
            }
            let fingerprint = legacyFingerprint
                ? SHA256.hash(data: Data(legacyRecords.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
                : digest.finalize().map { String(format: "%02x", $0) }.joined()
            return (size, FileIdentity(device: device, inode: root.st_ino, size: root.st_size,
                modified: Date(timeIntervalSince1970: Double(root.st_mtimespec.tv_sec) + Double(root.st_mtimespec.tv_nsec) / 1_000_000_000),
                treeDigest: fingerprint, location: pinned.location))
        }
    }

    public static func item(_ url: URL, category: ItemCategory, safety: SafetyLevel,
                            explanation: String, consequence: String, rule: String,
                            owner: String? = nil, progress: (@Sendable (Int, Int64) -> Void)? = nil) throws -> CleanupItem {
        let (size, identity) = try inspect(url, progress: progress)
        return CleanupItem(url: url, bytes: size, category: category, safety: safety,
                           explanation: explanation, consequence: consequence, ruleID: rule,
                           ownerBundleID: owner, identity: identity, scannedAt: Date())
    }

    /// Read metadata through the same pinned capability gate as hashes.
    static func readMetadata(_ url: URL, limit: Int = 16_777_216) throws -> Data {
        try NonMaterializingIO.perform {
            let pinned = try PinnedPath(url)
            guard pinned.value.st_size <= Int64(limit) else { throw LumaError.rejected("Metadata exceeds the inspection limit.") }
            let fd = try pinned.openReadableRegularFile()
            defer { close(fd) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw LumaError.rejected("Metadata exceeds the inspection limit.") }
            try pinned.revalidate()
            return data
        }
    }

    static func applicationMetadata(at bundle: URL) throws -> [String: Any] {
        let data = try readMetadata(bundle.exactAppendingPathComponent("Contents/Info.plist"), limit: 1_048_576)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LumaError.rejected("Application metadata could not be verified.")
        }
        return plist
    }

    static func applicationIdentifier(at bundle: URL) throws -> String {
        guard let identifier = try applicationMetadata(at: bundle)["CFBundleIdentifier"] as? String, !identifier.isEmpty else {
            throw LumaError.rejected("Application identity could not be verified.")
        }
        return identifier
    }

    public static func hash(_ url: URL, partial: Bool = false, progress: (@Sendable (Int64) -> Void)? = nil) throws -> String {
        return try NonMaterializingIO.perform {
            let pinned = try PinnedPath(url)
            guard pinned.value.st_mode & S_IFMT == S_IFREG else { throw LumaError.rejected("Only regular files can be hashed.") }
            let readable = try pinned.openReadableRegularFile()
            defer { close(readable) }
            let handle = FileHandle(fileDescriptor: readable, closeOnDealloc: false)
            var digest = SHA256()
            var bytesRead: Int64 = 0
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: partial ? 65_536 : 1_048_576), !data.isEmpty else { break }
                digest.update(data: data)
                bytesRead += Int64(data.count); progress?(bytesRead)
                if partial { break }
            }
            try pinned.revalidate()
            var after = stat()
            guard fstat(readable, &after) == 0, after.st_size == pinned.value.st_size,
                  after.st_mtimespec.tv_sec == pinned.value.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == pinned.value.st_mtimespec.tv_nsec else {
                throw LumaError.rejected("The file changed while hashing. Scan again.")
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
