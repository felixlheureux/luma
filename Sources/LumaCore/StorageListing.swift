import Foundation

/// Display filtering runs on captured metadata, independently of filesystem discovery.
public struct StorageListingQuery: Equatable, Sendable {
    public var largestFiles: Bool
    public var directory: String?
    public var filter: String
    public var showHidden: Bool
    public var search: String
    public var location: String
    public var sort: String
    public var selection: Set<String>
    public var pinnedOrder: [String]
    public init(largestFiles: Bool, directory: String?, filter: String, showHidden: Bool, search: String,
                location: String, sort: String, selection: Set<String>, pinnedOrder: [String] = []) {
        self.largestFiles = largestFiles; self.directory = directory; self.filter = filter
        self.showHidden = showHidden; self.search = search; self.location = location
        self.sort = sort; self.selection = selection; self.pinnedOrder = pinnedOrder
    }
}

extension StorageIndex {
    public func listing(_ query: StorageListingQuery) throws -> [StorageNode] {
        let source = query.filter == "Selected" ? query.selection.compactMap { nodes[$0] }
            : query.largestFiles ? Array(nodes.values) : children(of: query.directory ?? rootID, showHidden: true)
        let location = query.location == "All locations" ? nil : URL(fileURLWithPath: query.location)
        let old = Date().addingTimeInterval(-365 * 86400)
        var rows: [StorageNode] = []
        for (i, node) in source.enumerated() {
            if i % 256 == 0 { try Task.checkCancellation() }
            guard (query.filter == "Selected" || !query.largestFiles || !node.isDirectory),
                  (query.showHidden || !node.hidden || query.filter == "Selected"),
                  query.search.isEmpty || node.url.path.localizedCaseInsensitiveContains(query.search),
                  location.map({ Filesystem.isWithin(node.url, root: $0) }) ?? true else { continue }
            switch query.filter {
            case "Over 100 MB": if node.bytes <= 100_000_000 { continue }
            case "Older than a year": if node.modified.map({ $0 < old }) != true { continue }
            case "Installers": if node.isDirectory || !["dmg", "pkg", "iso"].contains(node.url.pathExtension.lowercased()) { continue }
            default: break
            }
            rows.append(node)
        }
        let positions = Dictionary(query.pinnedOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var comparisons = 0
        return try rows.sorted {
            comparisons += 1
            if comparisons % 256 == 0 { try Task.checkCancellation() }
            let a = positions[$0.id] ?? Int.max, b = positions[$1.id] ?? Int.max
            if a != b { return a < b }
            if query.sort == "Size", $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            if query.sort == "Modified", $0.modified != $1.modified { return ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
