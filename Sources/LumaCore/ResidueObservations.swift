import Foundation

/// Saved display observations never authorize cleanup. Fresh evidence is obtained for
/// precisely the captured selection, then validated again by the journal.
public struct ResidueObservations: Codable, Sendable {
    public let items: [CleanupItem]
    public let savedAt: Date
    public let complete: Bool
    public let notices: [String]
    public init(items: [CleanupItem], savedAt: Date = Date(), complete: Bool, notices: [String] = []) {
        self.items = Array(items.prefix(4_000)); self.savedAt = savedAt
        self.complete = complete && items.count <= 4_000
        self.notices = Array(notices.prefix(200)) + (items.count > 4_000 ? ["Saved display limited to 4,000 observations. Refresh for current discovery."] : [])
    }

    public static func prepare(_ observations: [CleanupItem], home: URL, ignoredPaths: Set<String>) throws -> CleanupPlan {
        let fresh = try observations.map { old in
            guard LeftoverScanner.matches(old, home: home) else { throw LumaError.rejected("Unsupported residue: \(old.displayPath)") }
            let item = try Filesystem.item(old.url, category: .related, safety: .review,
                explanation: old.explanation, consequence: old.consequence,
                rule: "application.leftover.exact-identifier", owner: old.ownerBundleID)
            guard item.identity == old.identity, item.identity.location == old.identity.location else {
                throw LumaError.rejected("This residue changed: \(old.displayPath). Refresh its observation before trying again.")
            }
            return item
        }
        return try CleanupPlan(items: fresh, ignoredPaths: ignoredPaths, source: .leftovers)
    }
}

public actor ResidueObservationStore {
    private let url: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = home.appendingPathComponent("Library/Application Support/Luma/residue-observations.json")
    }
    public func load() throws -> ResidueObservations? {
        try NonMaterializingIO.perform {
            do {
                let data = try Filesystem.readMetadata(url, limit: 8_388_608)
                let value = try JSONDecoder().decode(ResidueObservations.self, from: data)
                guard value.items.count <= 4_000 else { return nil }
                return value
            } catch {
                if GeneratedDataScanner.failureState(error) == .missing { return nil }
                throw error
            }
        }
    }
    public func save(_ value: ResidueObservations) throws {
        try NonMaterializingIO.perform {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try Filesystem.validatePath(parent)
            let data = try JSONEncoder().encode(value)
            guard data.count <= 8_388_608 else { throw LumaError.rejected("Residue observations exceed the saved display limit.") }
            try data.write(to: url, options: .atomic)
        }
    }
}
