import Foundation
import Darwin

public enum DuplicateOrder: String, CaseIterable, Sendable {
    case savings = "Largest savings", path = "Path", newest = "Recently modified"
}

public enum DuplicateKeeperPreference: String, CaseIterable, Sendable {
    case oldest = "Keep oldest modified", newest = "Keep newest modified"
}

/// Presentation policy never drops members from a matching group. Date ties
/// resolve by exact UTF-8 path, independent of enumeration order and locale.
public enum DuplicateReview {
    public static func groups(_ groups: [DuplicateGroup], query: String = "", minimumBytes: Int64 = 0,
                              order: DuplicateOrder = .savings) -> [DuplicateGroup] {
        groups.filter { group in
            group.recoverable >= minimumBytes && (query.isEmpty || group.items.contains { $0.url.path.localizedStandardContains(query) })
        }.sorted { a, b in
            switch order {
            case .savings:
                if a.recoverable != b.recoverable { return a.recoverable > b.recoverable }
            case .path:
                let left = members(a).first?.id ?? "", right = members(b).first?.id ?? ""
                if left != right { return pathBefore(left, right) }
            case .newest:
                let left = a.items.map(\.identity.modified).max() ?? .distantPast
                let right = b.items.map(\.identity.modified).max() ?? .distantPast
                if left != right { return left > right }
            }
            return pathBefore(a.id, b.id)
        }
    }

    public static func members(_ group: DuplicateGroup) -> [CleanupItem] {
        group.items.sorted { pathBefore($0.id, $1.id) }
    }

    public static func keeper(in group: DuplicateGroup, preference: DuplicateKeeperPreference) -> CleanupItem? {
        group.items.sorted {
            if $0.identity.modified != $1.identity.modified {
                return preference == .oldest ? $0.identity.modified < $1.identity.modified : $0.identity.modified > $1.identity.modified
            }
            return pathBefore($0.id, $1.id)
        }.first
    }

    private static func pathBefore(_ a: String, _ b: String) -> Bool {
        Data(a.utf8).lexicographicallyPrecedes(Data(b.utf8))
    }
}

/// An explicit, reviewable selection proposal, never a mutation authorization.
/// Verify every copy from current bytes when preparing AND applying the choice.
public struct DuplicateKeeperChoice: Sendable {
    public let group: DuplicateGroup
    public let keeper: CleanupItem
    public var removals: [CleanupItem] { DuplicateReview.members(group).filter { $0.id != keeper.id } }
    public init(group: DuplicateGroup, keeperID: String) throws {
        guard group.items.count >= 2, Set(group.items.map(\.id)).count == group.items.count,
              Set(group.items.map { FileObjectID($0.identity) }).count == group.items.count,
              let keeper = group.items.first(where: { $0.id == keeperID }) else {
            throw LumaError.rejected("Choose an independent copy from the complete duplicate group.")
        }
        self.group = group; self.keeper = keeper
    }

    public func validate(ignoredPaths: Set<String> = [], now: Date = Date()) throws {
        try NonMaterializingIO.perform {
            for item in group.items {
                try Task.checkCancellation()
                guard item.ruleID == "duplicates.sha256", item.safety == .userData,
                      now.timeIntervalSince(item.scannedAt) >= 0, now.timeIntervalSince(item.scannedAt) < 1_800,
                      !ignoredPaths.contains(where: { Filesystem.isWithin(item.url, root: URL(fileURLWithPath: $0)) }) else {
                    throw LumaError.rejected("This duplicate choice is stale or excluded. Scan again before choosing a keeper.")
                }
                let pin = try PinnedPath(item.url)
                guard let location = item.identity.location,
                      pin.value.st_mode & S_IFMT == S_IFREG,
                      try Filesystem.inspect(item.url).1 == item.identity else {
                    throw LumaError.rejected("A copy changed or is no longer independent. Scan again before choosing a keeper.")
                }
                try pin.revalidate(expected: location)
                guard try Filesystem.hash(item.url) == group.id,
                      try Filesystem.inspect(item.url).1 == item.identity else {
                    throw LumaError.rejected("Duplicate contents changed. Scan again before choosing a keeper.")
                }
                try pin.revalidate(expected: location)
            }
        }
    }
}

public struct DuplicateComparison: Sendable {
    public let created: Date
    public let modified: Date
    public let linkCount: UInt32
    public let preview: DownloadPreview

    public static func read(_ item: CleanupItem) throws -> Self {
        try NonMaterializingIO.perform {
            let pin = try PinnedPath(item.url)
            guard let location = item.identity.location, try Filesystem.inspect(item.url).1 == item.identity else {
                throw LumaError.rejected("This copy changed. Scan again before comparing.")
            }
            try pin.revalidate(expected: location)
            let created = Date(timeIntervalSince1970: Double(pin.value.st_birthtimespec.tv_sec) + Double(pin.value.st_birthtimespec.tv_nsec) / 1e9)
            let preview: DownloadPreview = pin.value.st_nlink > 1
                ? .unavailable("Hard-linked file: other paths share these bytes. Inline preview is unavailable; moving this path may reclaim no space.")
                : try DownloadPreviewReader.read(item)
            try pin.revalidate(expected: location)
            return Self(created: created, modified: item.identity.modified, linkCount: UInt32(pin.value.st_nlink), preview: preview)
        }
    }
}
