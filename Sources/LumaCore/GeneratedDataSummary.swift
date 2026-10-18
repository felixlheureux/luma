import Foundation

/// Read-only content evidence from the completed scan. Totals for any subset
/// count hard-linked content once without doing filesystem work in a view.
public struct GeneratedDataAccounting: Sendable {
    private struct Entry: Sendable {
        let identity: FileIdentity
        let objects: [FileObjectID: Int64]
    }
    private var entries: [String: Entry] = [:]

    mutating func inspect(_ url: URL, rule: CleanupRule,
                          progress: (@Sendable (Int, Int64) -> Void)?) throws -> CleanupItem {
        var objects: [FileObjectID: Int64] = [:]
        let (size, identity) = try Filesystem.inspect(url, progress: progress, onFile: { objects[$0] = $1 })
        entries[url.path] = Entry(identity: identity, objects: objects)
        return CleanupItem(url: url, bytes: size, category: rule.category, safety: rule.safety,
            explanation: rule.explanation, consequence: rule.consequence, ruleID: rule.id,
            ownerBundleID: rule.owner, identity: identity, scannedAt: Date())
    }

    public func bytes(for items: [CleanupItem]) -> Int64 {
        var seen: Set<FileObjectID> = []
        var total: Int64 = 0
        for item in items {
            guard let entry = entries[item.url.path], entry.identity == item.identity else {
                // Compatibility for synthetic/older reports without accounting.
                let (next, overflow) = total.addingReportingOverflow(item.bytes)
                total = overflow ? .max : next
                continue
            }
            for (object, bytes) in entry.objects where seen.insert(object).inserted {
                let (next, overflow) = total.addingReportingOverflow(bytes)
                total = overflow ? .max : next
            }
        }
        return total
    }
}

public struct GeneratedDataGroup: Identifiable, Sendable {
    public let id: String
    public let appName: String
    public let owner: String?
    public let category: ItemCategory
    public let items: [CleanupItem]

    public static func groups(for items: [CleanupItem]) -> [GeneratedDataGroup] {
        let rules = Dictionary(uniqueKeysWithValues: Rules.generated.map { ($0.id, $0) })
        let knownNames = ["com.apple.dt.Xcode": "Xcode", "com.apple.iphonesimulator": "Simulator",
            "com.google.Chrome": "Chrome", "com.apple.Safari": "Safari", "com.spotify.client": "Spotify",
            "org.mozilla.firefox": "Firefox", "app.zen-browser.zen": "Zen", "com.brave.Browser": "Brave",
            "com.microsoft.edgemac": "Microsoft Edge"]
        let buckets = Dictionary(grouping: items) { item in
            item.category.rawValue + ":" + (item.ownerBundleID ?? item.ruleID)
        }
        return buckets.map { key, values in
            let item = values[0]
            let name = rules[item.ruleID]?.appName ?? item.ownerBundleID.flatMap { knownNames[$0] } ?? rules[item.ruleID]?.title ?? item.name
            return GeneratedDataGroup(id: key, appName: name, owner: item.ownerBundleID,
                category: item.category, items: values.sorted { $0.url.path < $1.url.path })
        }.sorted { ($0.category.rawValue, $0.appName, $0.id) < ($1.category.rawValue, $1.appName, $1.id) }
    }
}
