import Foundation
import Darwin

/// Immutable observation. Only the system-resolved current user's local Trash is
/// available publicly; tests inject disposable roots through the internal seam.
public struct TrashReview: Sendable {
    public let id: UUID
    public let root: URL
    public let bytes: Int64
    public let excluded: Int
    public var count: Int { trees.count }
    let location: FileLocation
    let trees: [[TrashEntry]]

    public static func currentUser() throws -> Self {
        let root = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard root.exactStandardizedFileURL == home.appendingPathComponent(".Trash").exactStandardizedFileURL else {
            throw LumaError.rejected("Only the current user's local home Trash is supported. Open other Trash bins in Finder.")
        }
        return try capture(root: root)
    }

    #if DEBUG
    public static func generatedFixture(root: URL) throws -> Self {
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures")
        guard Filesystem.isWithin(root, root: fixtures), root.lastPathComponent == ".Trash" else {
            throw LumaError.rejected("Trash QA requires a generated .build/Fixtures home.")
        }
        return try capture(root: root)
    }
    #endif

    static func capture(root: URL, limit: Int = 20_000) throws -> Self {
        try NonMaterializingIO.perform {
            let pin = try PinnedPath(root)
            guard pin.value.st_uid == getuid(), pin.value.st_mode & S_IFMT == S_IFDIR else {
                throw LumaError.rejected("Trash ownership or directory could not be verified.")
            }
            var trees: [[TrashEntry]] = [], excluded = 0, visited = 0
            var bytes: Int64 = 0, seen: Set<FileObjectID> = []
            for name in try PinnedPath.names(in: pin.descriptor, limit: limit) {
                try Task.checkCancellation()
                do {
                    let tree = try entries(at: root.exactAppendingPathComponent(name), device: pin.value.st_dev,
                                           visited: &visited, limit: limit)
                    trees.append(tree)
                    for entry in tree where !entry.directory {
                        let key = FileObjectID(device: UInt64(UInt32(bitPattern: entry.device)), inode: entry.inode)
                        if seen.insert(key).inserted { bytes += entry.size }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { excluded += 1 }
            }
            try pin.revalidate()
            return Self(id: UUID(), root: root, bytes: bytes, excluded: excluded, location: pin.location, trees: trees)
        }
    }

    static func entries(at url: URL, device: dev_t, visited: inout Int, limit: Int, depth: Int = 0) throws -> [TrashEntry] {
        try Task.checkCancellation()
        visited += 1
        guard visited <= limit, depth < 128 else { throw LumaError.rejected("Trash inspection limit reached; remaining entries are excluded.") }
        let pin = try PinnedPath(url)
        guard pin.value.st_uid == getuid(), pin.value.st_dev == device else {
            throw LumaError.rejected("Foreign ownership or another volume is excluded.")
        }
        let entry = TrashEntry(url: url, value: pin.value, location: pin.location)
        var result: [TrashEntry] = []
        if entry.directory {
            for name in try PinnedPath.names(in: pin.descriptor, limit: limit) {
                result += try entries(at: url.exactAppendingPathComponent(name), device: device, visited: &visited, limit: limit, depth: depth + 1)
            }
        }
        try pin.revalidate()
        result.append(entry) // Children first; directories are removed only with rmdir.
        return result
    }
}

struct TrashEntry: Sendable, Equatable {
    let url: URL
    let device: dev_t
    let inode: ino_t
    let size: Int64
    let seconds: Int
    let nanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    let mode: mode_t
    let flags: UInt32
    let birthSeconds: Int
    let birthNanos: Int
    let directory: Bool
    let location: FileLocation
    func matchesRemovalIdentity(_ current: Self) -> Bool {
        if !directory { return self == current }
        return location == current.location && mode == current.mode && flags == current.flags
            && birthSeconds == current.birthSeconds && birthNanos == current.birthNanos
    }
    init(url: URL, value: stat, location: FileLocation) {
        self.url = url; device = value.st_dev; inode = value.st_ino; size = value.st_size
        seconds = value.st_mtimespec.tv_sec; nanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        mode = value.st_mode; flags = value.st_flags
        birthSeconds = value.st_birthtimespec.tv_sec; birthNanos = value.st_birthtimespec.tv_nsec
        directory = value.st_mode & S_IFMT == S_IFDIR; self.location = location
    }
}

public struct TrashRemovalOutcome: Codable, Sendable {
    public let path: URL
    public var state: String
    public var detail: String
}

public struct TrashRemovalSession: Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let root: URL
    public var outcomes: [TrashRemovalOutcome]
    public var finished: Bool
    public var phase: String? = nil
    public var summary: String {
        let removed = outcomes.filter { $0.state == "removed" }.count
        let skipped = outcomes.filter { $0.state == "skipped" }.count
        let failed = outcomes.filter { $0.state == "failed" }.count
        let unknown = outcomes.filter { $0.state == "interrupted" || $0.state == "deleting" }.count
        return "\(removed) entries permanently removed · \(skipped) skipped · \(failed) failed · \(unknown) unconfirmed · \(phase ?? (finished ? "completed" : "interrupted; not retried"))"
    }
}
