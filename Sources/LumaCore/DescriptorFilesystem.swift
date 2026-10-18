import Foundation
import Darwin

/// Stable, byte-exact location evidence, separate from the movable object's identity.
/// Ancestor timestamps are deliberately excluded: moving siblings changes them.
public struct FileLocation: Codable, Sendable, Equatable {
    public struct Component: Codable, Sendable, Equatable {
        let device: UInt64
        let inode: UInt64
        let owner: UInt32
        let kind: UInt16
        init(_ value: stat) {
            device = UInt64(UInt32(bitPattern: value.st_dev)); inode = value.st_ino
            owner = value.st_uid; kind = UInt16(value.st_mode & S_IFMT)
        }
    }
    let path: Data
    let chain: [Component]
}

/// Pins every component from / without following links. Tokens are never an
/// authorization: callers still apply ownership, volume and cleanup rules.
final class PinnedPath {
    let url: URL
    let location: FileLocation
    let descriptors: [Int32]
    var descriptor: Int32 { descriptors[descriptors.count - 1] }
    let value: stat

    init(_ input: URL) throws {
        guard input.isFileURL else { throw LumaError.rejected("Only local filesystem paths are supported.") }
        let url = input.exactStandardizedFileURL
        guard input.host?.isEmpty != false, input.query == nil, input.fragment == nil, !input.path.utf8.contains(0),
              Data(input.path.utf8) == Data(url.path.utf8) else {
            throw LumaError.rejected("Use a canonical local path without dot components or a remote host.")
        }
        guard url.path != "/" else { throw LumaError.rejected("The filesystem root is protected.") }
        var opened: [Int32] = []
        do {
            let root = open("/", O_SEARCH | O_CLOEXEC)
            guard root >= 0 else { throw Self.posixError() }
            opened.append(root)
            var initial = stat()
            guard fstat(root, &initial) == 0 else { throw Self.posixError() }
            var chain = [FileLocation.Component(initial)]
            var cursor = URL(fileURLWithPath: "/", isDirectory: true)
            let names = url.pathComponents.dropFirst()
            var last = initial
            for (index, name) in names.enumerated() {
                try Task.checkCancellation()
                let parent = opened[opened.count - 1]
                let isParent = index < names.count - 1
                let (fd, info) = try Self.openChild(parent, name: name, directory: isParent)
                opened.append(fd)
                cursor = cursor.exactAppendingPathComponent(name)
                // Finder aliases are regular files; they must be excluded too.
                guard try cursor.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile != true else {
                    throw LumaError.rejected("Finder aliases are excluded from cleanup.")
                }
                chain.append(FileLocation.Component(info)); last = info
            }
            self.url = url; self.descriptors = opened; self.value = last
            self.location = FileLocation(path: Data(url.path.utf8), chain: chain)
        } catch { for fd in opened.reversed() { close(fd) }; throw error }
    }

    deinit { for fd in descriptors.reversed() { close(fd) } }

    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    static func openChild(_ parent: Int32, name: String, directory: Bool = false) throws -> (Int32, stat) {
        var before = stat()
        guard fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        let kind = before.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR, !directory || kind == S_IFDIR else {
            throw LumaError.rejected("Links and unsupported filesystem objects are excluded.")
        }
        // Event-only descriptors avoid opening special-device data streams if a
        // regular file is replaced after fstatat. Search-only directory handles
        // preserve access to known children without requiring directory listing.
        let fd = openat(parent, name, O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (kind == S_IFDIR ? O_SEARCH : O_EVTONLY))
        guard fd >= 0 else { throw posixError() }
        var after = stat()
        guard fstat(fd, &after) == 0 else { let error = posixError(); close(fd); throw error }
        guard FileLocation.Component(before) == FileLocation.Component(after) else {
            close(fd); throw LumaError.rejected("A filesystem object changed while it was being opened. Scan again.")
        }
        return (fd, after)
    }

    func openReadableRegularFile() throws -> Int32 {
        guard value.st_mode & S_IFMT == S_IFREG else { throw LumaError.rejected("Only regular files may be read.") }
        let parent = descriptors[descriptors.count - 2]
        let readable = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard readable >= 0 else { throw Self.posixError() }
        var opened = stat()
        guard fstat(readable, &opened) == 0,
              FileLocation.Component(opened) == FileLocation.Component(value) else {
            close(readable); throw LumaError.rejected("The file was replaced before reading.")
        }
        return readable
    }

    func revalidate(expected: FileLocation? = nil) throws {
        let fresh = try PinnedPath(url)
        guard fresh.location == location, expected == nil || expected == location else {
            throw LumaError.rejected("The item or one of its parent folders was replaced. Scan again before continuing.")
        }
    }

    static func validateParent(of url: URL, expected: FileLocation) throws -> PinnedPath {
        guard expected.path == Data(url.exactStandardizedFileURL.path.utf8), expected.chain.count > 1 else {
            throw LumaError.rejected("The stored location does not match this path.")
        }
        let parent = try PinnedPath(url.exactDeletingLastPathComponent())
        guard parent.location.chain == Array(expected.chain.dropLast()) else {
            throw LumaError.rejected("The original parent folder was replaced. Restore through Finder to choose a location.")
        }
        return parent
    }

    static func names(in descriptor: Int32, limit: Int = 250_000) throws -> [String] {
        // openat creates an independent directory stream (dup shares offsets).
        let copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard copy >= 0 else { throw posixError() }
        guard let stream = fdopendir(copy) else { let error = posixError(); close(copy); throw error }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            try Task.checkCancellation()
            guard result.count <= limit else { throw LumaError.rejected("This directory exceeds the current inspection limit; narrow your selection.") }
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw posixError() }; break
            }
            let length = Int(entry.pointee.d_namlen)
            let bytes = withUnsafeBytes(of: entry.pointee.d_name) { Data($0.prefix(length)) }
            guard let name = String(data: bytes, encoding: .utf8) else {
                throw LumaError.rejected("A filename cannot be represented safely. Review this folder in Finder.")
            }
            if bytes != Data(".".utf8), bytes != Data("..".utf8) { result.append(name) }
        }
        return result.sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
    }
}

// Foundation's fileURLWithPath/appendingPathComponent/standardizedFileURL
// normalize Unicode on macOS. Descriptor identity must keep the supplied bytes.
extension URL {
    static func exactFileURL(path: String) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%?#"))
        return URL(string: "file://" + path.addingPercentEncoding(withAllowedCharacters: allowed)!)!
    }

    var exactStandardizedFileURL: URL {
        guard isFileURL else { return self }
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !components.isEmpty { components.removeLast() }; continue }
            components.append(component)
        }
        return .exactFileURL(path: "/" + components.joined(separator: "/"))
    }

    func exactAppendingPathComponent(_ component: String) -> URL {
        .exactFileURL(path: (path == "/" ? "" : path) + "/" + component)
    }

    func exactDeletingLastPathComponent() -> URL {
        let value = path
        guard let separator = value.lastIndex(of: "/"), separator != value.startIndex else { return .exactFileURL(path: "/") }
        return .exactFileURL(path: String(value[..<separator]))
    }
}
