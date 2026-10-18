import Foundation

public enum ResetCategory: String, CaseIterable, Sendable {
    case caches = "Caches and logs"
    case preferences = "Preferences and settings"
    case savedState = "Saved application state"
    case otherData = "Other app data · review separately"

    public var consequence: String {
        switch self {
        case .caches: "Caches may be rebuilt or downloaded. Logs may contain useful diagnostics."
        case .preferences: "Custom settings will be lost. Some apps store account choices here; this is not a complete sign-out."
        case .savedState: "Window restoration and unsaved session recovery may be lost."
        case .otherData: "May remove documents, offline content, extensions, credentials or sessions and require signing in again. Select only data you intend to reset."
        }
    }
    public static func category(for relationship: ApplicationRelationship) -> Self? {
        guard relationship.category != .bundle else { return nil }
        if relationship.category == .settings && relationship.url.exactDeletingLastPathComponent().lastPathComponent == "Preferences" { return .preferences }
        if relationship.category == .settings && relationship.url.exactDeletingLastPathComponent().lastPathComponent == "Saved Application State" { return .savedState }
        return relationship.category == .generated ? .caches : .otherData
    }
}

/// Reset is a distinct plan intent: the bundle is never an eligible target.
public enum ApplicationReset {
    public static func validateSelection(_ items: [CleanupItem], app: ApplicationRecord) throws {
        guard ApplicationRelationships.supports(app.bundleID), !items.isEmpty,
              items.allSatisfy({ $0.ruleID == "application.exact-related" && $0.category == .related
                  && $0.safety == .review && $0.ownerBundleID == app.bundleID
                  && !Filesystem.isWithin($0.url, root: app.url) }) else {
            throw LumaError.rejected("Reset accepts only explicitly reviewed data for this app. The application bundle cannot be reset.")
        }
    }

    public static func knownOwners(app: ApplicationRecord, home: URL) throws -> Set<String> {
        try NonMaterializingIO.perform {
            guard app.url.pathExtension == "app", ApplicationRelationships.supports(app.bundleID),
                  [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains(where: {
                      Filesystem.samePath(app.url.exactDeletingLastPathComponent(), $0)
                  }), try Filesystem.applicationIdentifier(at: app.url) == app.bundleID else {
                throw LumaError.rejected("Application ownership is unavailable or changed. Inspect again before reset.")
            }
            let owners = try ApplicationPresence.bundleIdentifiers(home: home, matchingOwner: app.bundleID)
            guard owners.contains(app.bundleID.lowercased()) else { throw LumaError.rejected("Application ownership could not be confirmed.") }
            return owners
        }
    }

    public static func validateActivity(app: ApplicationRecord, home: URL, context: CleanupExecutionContext) throws {
        let owners = try knownOwners(app: app, home: home)
        guard let paths = context.processPaths else {
            throw LumaError.rejected("Running processes could not be checked. Reset is blocked; try checking again.")
        }
        let owner = app.bundleID.lowercased()
        guard !context.runningBundleIDs.contains(where: {
            let id = $0.lowercased()
            return owners.contains(id) || id == owner || id.hasPrefix(owner + ".") || owner.hasPrefix(id + ".")
        }), !paths.contains(where: { Filesystem.isWithin(URL(fileURLWithPath: $0), root: app.url) }) else {
            throw LumaError.rejected("Quit the application and its known helpers, then check again before reset.")
        }
    }
}
