import Foundation
import Darwin

public struct SafetyEngine: Sendable {
    public let home: URL
    public let ignoredPaths: Set<String>
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, ignoredPaths: Set<String> = []) {
        self.home = home; self.ignoredPaths = ignoredPaths
    }

    /// Metadata-free scope check for enabling explicit manual selections. Full
    /// filesystem, ownership and identity validation still happens in validate.
    public func permitsManualSelection(at url: URL, authorizedRoots: [URL]) -> Bool {
        let protected = [home] + ["Documents", "Desktop", "Pictures", "Movies", "Music", "Downloads", "Library", "Applications", ".Trash"].map { home.appendingPathComponent($0) }
        return Filesystem.isWithin(url, root: home)
            && !["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev", "/Volumes"].contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }
            && !protected.contains { Filesystem.samePath($0, url) }
            && !Filesystem.isWithin(url, root: home.appendingPathComponent("Library"))
            && !Filesystem.isWithin(url, root: home.appendingPathComponent(".Trash"))
            && !ignoredPaths.contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }
            && authorizedRoots.contains { !Filesystem.samePath(url, $0) && Filesystem.isWithin(url, root: $0) }
    }

    public func validate(_ item: CleanupItem, authorizedRoots: [URL] = [], runningBundleIDs: Set<String> = [], activity: CleanupActivity? = nil) throws {
        let url = item.url.exactStandardizedFileURL
        try Filesystem.validatePath(item.url)
        guard Date().timeIntervalSince(item.scannedAt) < 1800 else { throw LumaError.rejected("Scan is over 30 minutes old. Scan again before cleaning.") }
        guard !ignoredPaths.contains(where: { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }) else {
            throw LumaError.rejected("This item is on your ignore list.")
        }
        if let owner = item.ownerBundleID, runningBundleIDs.contains(owner) {
            throw LumaError.rejected("Quit the owning application before cleaning its files.")
        }
        let critical = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev", "/Volumes"]
        guard !critical.contains(where: { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }) else {
            throw LumaError.rejected("System and external-volume paths are protected in this version.")
        }
        let protectedRoots = [home] + ["Documents", "Desktop", "Pictures", "Movies", "Music", "Downloads", "Library", "Applications", ".Trash"].map { home.appendingPathComponent($0) }
        guard !protectedRoots.contains(where: { Filesystem.samePath($0, url) }), url.path != "/Applications" else { throw LumaError.rejected("This folder is protected.") }
        if item.ruleID == "application.exact-bundle" {
            guard item.ownerBundleID != "app.luma.mac", item.ownerBundleID?.hasPrefix("com.apple.") == false,
                  url.pathExtension == "app", [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains(where: { Filesystem.samePath($0, url.exactDeletingLastPathComponent()) }),
                  (try? Filesystem.applicationIdentifier(at: url)) == item.ownerBundleID else { throw LumaError.rejected("Application identity could not be validated or is protected.") }
        } else if item.ruleID == "application.exact-related" {
            guard let owner = item.ownerBundleID, item.safety == .review else { throw LumaError.rejected("Protected application data or unsupported safety classification.") }
            _ = try ApplicationRelationships.resolve(url: url, owner: owner, home: home)
        } else if item.ruleID == "application.leftover.exact-identifier" {
            guard LeftoverScanner.matches(item, home: home), let owner = item.ownerBundleID else {
                throw LumaError.rejected("The leftover path does not match its ownership evidence.")
            }
            _ = try ApplicationRelationships.resolve(url: url, owner: owner, home: home)
            let installed = try ApplicationPresence.bundleIdentifiers(home: home)
            guard !ApplicationPresence.hasOwner(owner, installed: installed) else {
                throw LumaError.rejected("An owning app or helper is now installed. Scan again before reviewing this data.")
            }
        } else if let rule = Rules.generated.first(where: { $0.id == item.ruleID }) {
            guard rule.matches(url, home: home), item.ownerBundleID == rule.owner, item.safety == rule.safety else { throw LumaError.rejected("Path or ownership no longer matches the cleanup rule.") }
            try VerifiedGeneratedOwner.validate(rule, home: home)
            if let owner = rule.owner, runningBundleIDs.contains(where: { $0 == owner || $0.hasPrefix(owner + ".") }) {
                throw LumaError.rejected("Quit the owning application and its helpers before cleaning these files.")
            }
            var requiredTools = rule.tools
            if rule.id == "developer.homebrew.cache" { requiredTools.insert(.packageManager) }
            if rule.id.hasPrefix("developer.xcode.") || rule.id == "developer.swiftpm.cache" { requiredTools.insert(.xcode) }
            if !requiredTools.isEmpty {
                let snapshot = activity ?? CleanupActivity.collect(checkSimulators: requiredTools.contains(.simulator))
                guard let tools = snapshot.tools else { throw LumaError.rejected("Running tools could not be checked. No cleanup was performed.") }
                guard tools.isDisjoint(with: requiredTools) else {
                    if requiredTools.contains(.visualStudioCode) {
                        throw LumaError.rejected("Quit Visual Studio Code and its background helpers before cleaning these files.")
                    }
                    throw LumaError.rejected("Stop active package managers, builds, or simulators before cleaning these files.")
                }
                if requiredTools.contains(.simulator), snapshot.simulatorsBooted != false {
                    throw LumaError.rejected("Luma could not confirm that every simulator is shut down. Shut down devices in Xcode before cleaning simulator data.")
                }
            }
        } else {
            guard ["manual.folder-review", "duplicates.sha256"].contains(item.ruleID), item.safety == .userData,
                  permitsManualSelection(at: url, authorizedRoots: authorizedRoots) else {
                throw LumaError.rejected("This item requires an explicitly chosen folder inside your home directory.")
            }
        }
        if ["application.exact-bundle", "application.exact-related", "application.leftover.exact-identifier"].contains(item.ruleID),
           let owner = item.ownerBundleID, !runningBundleIDs.isEmpty {
            let helpers = try ApplicationPresence.bundleIdentifiers(home: home, matchingOwner: owner)
            let running = Set(runningBundleIDs.map { $0.lowercased() })
            let normalized = owner.lowercased()
            guard helpers.isDisjoint(with: running), !running.contains(where: {
                $0 == normalized || $0.hasPrefix(normalized + ".") || normalized.hasPrefix($0 + ".")
            }) else { throw LumaError.rejected("Quit the owning app and its helpers before cleaning these files.") }
        }
        let a = try Filesystem.attributes(url)
        guard (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw LumaError.rejected("This item belongs to another user.") }
        guard let location = item.identity.location else { throw LumaError.rejected("This scan uses older identity evidence. Scan again before cleanup.") }
        let pinned = try PinnedPath(url)
        try pinned.revalidate(expected: location)
        let current = try Filesystem.inspect(url).1
        try pinned.revalidate(expected: location)
        guard current == item.identity else { throw LumaError.rejected("Files changed since scanning. Scan again to review their current contents.") }
        let homeDevice = (try Filesystem.attributes(home)[.systemNumber] as? NSNumber)?.uint64Value
        guard current.device == homeDevice else { throw LumaError.rejected("This item is on a different volume.") }
    }

}
