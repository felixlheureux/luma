import Foundation
import Darwin

public struct SafetyEngine: Sendable {
    public let home: URL
    public let ignoredPaths: Set<String>
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, ignoredPaths: Set<String> = []) {
        self.home = home; self.ignoredPaths = ignoredPaths
    }

    private static let protectedHomeEntries: Set<String> = ["documents", "desktop", "pictures", "movies", "music", "downloads", "library", "applications", ".trash"]
    private static let sensitiveHomeEntries: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".kube", ".config", ".cache", ".local", ".git", ".docker", ".azure",
        ".gitconfig", ".git-credentials", ".git-credential-cache", ".netrc", ".npmrc", ".pypirc",
        ".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".bash_history", ".bash_sessions", ".profile",
        ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".zlogout", ".zsh_history", ".zsh_sessions"
    ]

    /// Metadata-free scope check for enabling explicit manual selections. Full
    /// filesystem, ownership and identity validation still happens in validate.
    public func permitsManualSelection(at url: URL, authorizedRoots: [URL]) -> Bool {
        guard url.isFileURL, Filesystem.isWithin(url, root: home) else { return false }
        let relative = url.exactStandardizedFileURL.pathComponents.dropFirst(home.exactStandardizedFileURL.pathComponents.count)
        // Every protected configuration root is immediately below home, so the
        // only containing ancestor is home itself (the empty relative path).
        // Fold case conservatively for case-insensitive APFS path spellings.
        guard let first = relative.first?.lowercased(),
              !(relative.count == 1 && Self.protectedHomeEntries.contains(first)),
              !["library", ".trash"].contains(first), !Self.sensitiveHomeEntries.contains(first) else { return false }
        if ApplicationRelationships.knownPaths.contains(where: { mapping in
            mapping.relativePath.hasPrefix(".") && mapping.relativePath.split(separator: "/").first?.lowercased() == first
        }) { return false }
        return !["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev", "/Volumes"].contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }
            && !ignoredPaths.contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) || Filesystem.isWithin(URL(fileURLWithPath: $0), root: url) }
            && authorizedRoots.contains { !Filesystem.samePath(url, $0) && Filesystem.isWithin(url, root: $0) }
    }

    public static func validateIgnores(_ url: URL, ignoredPaths: Set<String>) throws {
        guard !ignoredPaths.contains(where: {
            let ignored = URL(fileURLWithPath: $0)
            return Filesystem.isWithin(url, root: ignored) || Filesystem.isWithin(ignored, root: url)
        }) else {
            throw LumaError.rejected("This item is ignored or contains an ignored path. Remove the ignore or choose a different item.")
        }
    }

    public func validate(_ item: CleanupItem, authorizedRoots: [URL] = [], runningBundleIDs: Set<String> = [], activity: CleanupActivity? = nil,
                         progress: @escaping @Sendable (ScanPulse) -> Void = { _ in }) throws {
        try validate(item, authorizedRoots: authorizedRoots, runningBundleIDs: runningBundleIDs, activity: activity, preflightOwners: nil, progress: progress)
    }

    // A shared inventory is allowed only for whole-plan preflight. The final
    // per-move call always enters through fresh ownership discovery above.
    func validate(_ item: CleanupItem, authorizedRoots: [URL], runningBundleIDs: Set<String>, activity: CleanupActivity?,
                  preflightOwners: Set<String>?, preflightHelpers: Set<String>? = nil, progress: @escaping @Sendable (ScanPulse) -> Void) throws {
        _ = try Rules.catalog()
        let url = item.url.exactStandardizedFileURL
        try Filesystem.validatePath(item.url)
        guard Date().timeIntervalSince(item.scannedAt) < 1800 else { throw LumaError.rejected("Scan is over 30 minutes old. Scan again before cleaning.") }
        try Self.validateIgnores(url, ignoredPaths: ignoredPaths)
        if let owner = item.ownerBundleID, runningBundleIDs.contains(owner) {
            throw LumaError.rejected("Quit the owning application before cleaning its files.")
        }
        let critical = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/dev", "/Volumes"]
        guard !critical.contains(where: { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }) else {
            throw LumaError.rejected("System and external-volume paths are protected in this version.")
        }
        let protectedRoots = [home] + ["Documents", "Desktop", "Pictures", "Movies", "Music", "Downloads", "Library", "Applications", ".Trash"].map { home.appendingPathComponent($0) }
        guard !protectedRoots.contains(where: { Filesystem.samePath($0, url) }), url.path != "/Applications" else { throw LumaError.rejected("This folder is protected.") }
        if Filesystem.isWithin(url, root: DeviceBackups.location(home: home)) || item.ruleID.hasPrefix("backup.") {
            throw LumaError.rejected(DeviceBackups.removalExplanation)
        }
        if item.ruleID == "application.exact-bundle" {
            guard item.ownerBundleID.map(ApplicationUninstall.supportsBundle) == true,
                  ApplicationInventory.contains(url, home: home),
                  (try? Filesystem.applicationIdentifier(at: url)) == item.ownerBundleID else { throw LumaError.rejected("Application identity could not be validated or is protected.") }
        } else if item.ruleID == "application.exact-related" {
            guard let owner = item.ownerBundleID, item.safety == .review else { throw LumaError.rejected("Protected application data or unsupported safety classification.") }
            _ = try ApplicationRelationships.resolve(url: url, owner: owner, home: home)
        } else if item.ruleID == "application.leftover.exact-identifier" {
            guard LeftoverScanner.matches(item, home: home), let owner = item.ownerBundleID else {
                throw LumaError.rejected("The leftover path does not match its ownership evidence.")
            }
            _ = try ApplicationRelationships.resolve(url: url, owner: owner, home: home)
            progress(.init("Checking installed owners", current: item.name))
            let installed = try preflightOwners ?? ApplicationPresence.bundleIdentifiers(home: home, emit: { event in
                if case .progress(let pulse) = event { progress(pulse) }
            })
            guard !ApplicationPresence.hasOwner(owner, installed: installed) else {
                throw LumaError.rejected("An owning app or helper is now installed. Scan again before reviewing this data.")
            }
        } else if item.ruleID.hasPrefix("project.") {
            try DeveloperProjects.validate(item, authorizedRoots: authorizedRoots, ignoredPaths: ignoredPaths, home: home, activity: activity)
        } else if let rule = Rules.generated.first(where: { $0.id == item.ruleID }) {
            guard rule.matches(url, home: home), item.ownerBundleID == rule.owner, item.safety == rule.safety else { throw LumaError.rejected("Path or ownership no longer matches the cleanup rule.") }
            try VerifiedGeneratedOwner.validate(rule, home: home)
            if let owner = rule.owner, runningBundleIDs.contains(where: { $0 == owner || $0.hasPrefix(owner + ".") }) {
                throw LumaError.rejected("Quit the owning application and its helpers before cleaning these files.")
            }
            let requiredTools = rule.tools
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
            try Filesystem.validateOutsidePackages(url)
        }
        if ["application.exact-bundle", "application.exact-related", "application.leftover.exact-identifier"].contains(item.ruleID),
           let owner = item.ownerBundleID, !runningBundleIDs.isEmpty {
            // Absence above already searched all apps and embedded helpers.
            // A second owner-specific walk cannot find an absent owner's helpers.
            let helpers: Set<String> = item.ruleID == "application.leftover.exact-identifier" ? []
                : try preflightHelpers ?? (item.ruleID == "application.exact-bundle"
                    ? ApplicationPresence.selectedInstallation(url)
                    : ApplicationPresence.bundleIdentifiers(home: home, matchingOwner: owner))
            let running = Set(runningBundleIDs.map { $0.lowercased() })
            let normalized = owner.lowercased()
            guard helpers.isDisjoint(with: running), !running.contains(where: {
                $0 == normalized || $0.hasPrefix(normalized + ".") || normalized.hasPrefix($0 + ".")
            }) else { throw LumaError.rejected("Quit the owning app and its helpers before cleaning these files.") }
        }
        if let mapping = HiddenAppData.mapping(for: url, home: home) {
            // App absence alone cannot establish absence of a CLI or shared installation.
            let installed = try preflightOwners ?? ApplicationPresence.bundleIdentifiers(home: home)
            guard !([mapping.owner] + mapping.otherOwners).contains(where: {
                ApplicationPresence.hasOwner($0, installed: installed)
            }), HiddenAppData.toolPresence(mapping, home: home) == .absent else {
                throw LumaError.rejected("A matching app, CLI or shared installation is present, or its absence could not be verified. Keep this hidden data.")
            }
            let owners = ([mapping.owner] + mapping.otherOwners).map { $0.lowercased() }
            guard !runningBundleIDs.contains(where: { running in owners.contains { running.lowercased() == $0 || running.lowercased().hasPrefix($0 + ".") } }) else {
                throw LumaError.rejected("Quit matching applications and helpers before reviewing this hidden data.")
            }
        }
        let a = try Filesystem.attributes(url)
        if item.ruleID == "application.exact-bundle" {
            try ApplicationUninstall.validateTrashRights(url)
        } else {
            guard (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw LumaError.rejected("This item belongs to another user.") }
        }
        guard let location = item.identity.location else { throw LumaError.rejected("This scan uses older identity evidence. Scan again before cleanup.") }
        let pinned = try PinnedPath(url)
        try pinned.revalidate(expected: location)
        progress(.init("Verifying current files", current: item.name))
        let current = try Filesystem.inspect(url, progress: { entries, bytes in
            progress(.init("Verifying current files", current: item.name, entries: entries, bytes: bytes))
        }, applicationBundle: item.ruleID == "application.exact-bundle", excludingPackages: item.ruleID == "manual.folder-review").1
        try pinned.revalidate(expected: location)
        guard current == item.identity else { throw LumaError.rejected("Files changed since scanning. Scan again to review their current contents.") }
        let homeDevice = (try Filesystem.attributes(home)[.systemNumber] as? NSNumber)?.uint64Value
        guard current.device == homeDevice else { throw LumaError.rejected("This item is on a different volume.") }
    }

}
