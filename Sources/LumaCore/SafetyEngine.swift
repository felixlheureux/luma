import Foundation
import Darwin

public struct SafetyEngine: Sendable {
    public let home: URL
    public let ignoredPaths: Set<String>
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, ignoredPaths: Set<String> = []) {
        self.home = home; self.ignoredPaths = ignoredPaths
    }

    public func validate(_ item: CleanupItem, authorizedRoots: [URL] = [], runningBundleIDs: Set<String> = []) throws {
        let url = item.url.standardizedFileURL
        try Filesystem.validatePath(url)
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
        guard !protectedRoots.contains(url), url.path != "/Applications" else { throw LumaError.rejected("This folder is protected.") }
        if item.ruleID == "application.exact-bundle" {
            guard item.ownerBundleID != "app.luma.mac", item.ownerBundleID?.hasPrefix("com.apple.") == false,
                  url.pathExtension == "app", [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains(url.deletingLastPathComponent()),
                  Bundle(url: url)?.bundleIdentifier == item.ownerBundleID else { throw LumaError.rejected("Application identity could not be validated or is protected.") }
        } else if item.ruleID == "application.exact-related" {
            guard let owner = item.ownerBundleID, !owner.contains("/"), !owner.hasPrefix("com.apple.") else { throw LumaError.rejected("Protected application data.") }
            let paths = ["Library/Caches/\(owner)", "Library/Preferences/\(owner).plist", "Library/Saved Application State/\(owner).savedState", "Library/Application Support/\(owner)"]
            guard paths.map({ home.appendingPathComponent($0) }).contains(url) else { throw LumaError.rejected("Related path does not exactly match the bundle identifier.") }
        } else if item.ruleID == "application.leftover.exact-identifier" {
            guard LeftoverScanner.matches(item, home: home), let owner = item.ownerBundleID else {
                throw LumaError.rejected("The leftover path does not exactly match its bundle identifier.")
            }
            let installed = try ApplicationPresence.bundleIdentifiers(home: home)
            guard !ApplicationPresence.hasOwner(owner, installed: installed) else {
                throw LumaError.rejected("An owning app or helper is now installed. Scan again before reviewing this data.")
            }
            if url.deletingLastPathComponent() == home.appendingPathComponent("Library/Containers") {
                let data = try Data(contentsOf: url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
                let metadata = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                guard metadata?["MCMMetadataIdentifier"] as? String == owner else { throw LumaError.rejected("Container ownership evidence has changed.") }
            }
        } else if let rule = Rules.generated.first(where: { $0.id == item.ruleID }) {
            guard home.appendingPathComponent(rule.relativePath).standardizedFileURL == url else { throw LumaError.rejected("Path no longer matches the cleanup rule.") }
        } else {
            guard ["manual.folder-review", "duplicates.sha256"].contains(item.ruleID), item.safety == .userData,
                  Filesystem.isWithin(url, root: home), !Filesystem.isWithin(url, root: home.appendingPathComponent("Library")),
                  !Filesystem.isWithin(url, root: home.appendingPathComponent(".Trash")),
                  authorizedRoots.contains(where: { url != $0.standardizedFileURL && Filesystem.isWithin(url, root: $0) }) else {
                throw LumaError.rejected("This item requires an explicitly chosen folder inside your home directory.")
            }
        }
        let a = try Filesystem.attributes(url)
        guard (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw LumaError.rejected("This item belongs to another user.") }
        let current = try Filesystem.inspect(url).1
        guard current == item.identity else { throw LumaError.rejected("Files changed since scanning. Scan again to review their current contents.") }
        let homeDevice = (try Filesystem.attributes(home)[.systemNumber] as? NSNumber)?.uint64Value
        guard current.device == homeDevice else { throw LumaError.rejected("This item is on a different volume.") }
    }

    /// The only cleanup mutation API. A review confirmation is required by the UI.
    public func trash(_ item: CleanupItem, authorizedRoots: [URL], runningBundleIDs: Set<String>) throws -> CleanupRecord {
        try validate(item, authorizedRoots: authorizedRoots, runningBundleIDs: runningBundleIDs)
        var destination: NSURL?
        try FileManager.default.trashItem(at: item.url, resultingItemURL: &destination)
        guard let destination else { throw LumaError.rejected("macOS did not report the Trash location. Check Trash in Finder.") }
        return CleanupRecord(original: item.url, trashed: destination as URL, bytes: item.bytes)
    }
}
