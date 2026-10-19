import Foundation

public struct LeftoverGroup: Identifiable, Sendable {
    public let id: String
    public let items: [CleanupItem]
    public var bytes: Int64 { Self.logicalBytes(items) }

    public static func logicalBytes(_ items: [CleanupItem]) -> Int64 {
        var seen: Set<String> = []
        var total: Int64 = 0
        for item in items {
            let contents = item.observedContents ?? ["\(item.identity.device):\(item.identity.inode)": item.bytes]
            for (object, bytes) in contents where seen.insert(object).inserted {
                let (next, overflow) = total.addingReportingOverflow(bytes)
                total = overflow ? .max : next
            }
        }
        return total
    }

    public static func groups(for items: [CleanupItem], largestFirst: Bool = false, search: String = "") -> [Self] {
        Dictionary(grouping: items, by: { $0.ownerBundleID ?? "Unknown owner" }).compactMap { owner, items in
            guard search.isEmpty || owner.localizedCaseInsensitiveContains(search)
                || items.contains(where: { $0.url.path.localizedCaseInsensitiveContains(search) }) else { return nil }
            return Self(id: owner, items: items.sorted {
                ($0.category.rawValue, $0.url.path) < ($1.category.rawValue, $1.url.path)
            })
        }.sorted {
            if largestFirst && $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
