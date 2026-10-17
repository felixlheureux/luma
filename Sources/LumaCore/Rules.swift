import Foundation

public struct CleanupRule: Sendable {
    public let id: String
    public let relativePath: String
    public let category: ItemCategory
    public let explanation: String
    public let consequence: String
    public let owner: String?
    public var title: String { name ?? URL(fileURLWithPath: relativePath).lastPathComponent }
    public var name: String? = nil
    public var profileLeaves: [String] = []
    public var chromiumProfiles = false
    public var safety: SafetyLevel = .safe
    public var tools: Set<CleanupTool> = []

    public func matches(_ url: URL, home: URL) -> Bool {
        let root = home.appendingPathComponent(relativePath).standardizedFileURL
        let candidate = url.standardizedFileURL
        if profileLeaves.isEmpty { return candidate == root }
        guard candidate.deletingLastPathComponent().deletingLastPathComponent() == root,
              profileLeaves.contains(candidate.lastPathComponent) else { return false }
        return acceptsProfile(candidate.deletingLastPathComponent().lastPathComponent)
    }

    public func acceptsProfile(_ name: String) -> Bool {
        if chromiumProfiles { return name == "Default" || name.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil }
        return name.count <= 255 && name.range(of: "^[A-Za-z0-9]{8,}\\..+$", options: .regularExpression) != nil && !name.contains("/")
    }
}

public enum Rules {
    public static let generated: [CleanupRule] = [
        .init(id: "developer.xcode.derived-data", relativePath: "Library/Developer/Xcode/DerivedData", category: .developer,
              explanation: "Xcode build products and indexes. Source projects and archives are excluded.",
              consequence: "Xcode will rebuild these files. Your next build and indexing pass may take longer.", owner: "com.apple.dt.Xcode", name: "Xcode Derived Data"),
        .init(id: "developer.swiftpm.cache", relativePath: "Library/Caches/org.swift.swiftpm", category: .developer,
              explanation: "Downloaded Swift package build caches.", consequence: "Packages may need to be downloaded and built again.", owner: "com.apple.dt.Xcode", name: "Swift package cache"),
        .init(id: "browser.chrome.cache", relativePath: "Library/Caches/Google/Chrome", category: .caches,
              explanation: "Google Chrome generated cache. Cookies, history, passwords and sessions are excluded.",
              consequence: "Web content will be fetched again. Close Chrome before cleaning.", owner: "com.google.Chrome", name: "Chrome cache"),
        .init(id: "app.spotify.cache", relativePath: "Library/Caches/com.spotify.client", category: .caches,
              explanation: "Spotify's generated application cache. Offline downloads in Application Support are excluded.",
              consequence: "Spotify may download cached content again.", owner: "com.spotify.client", name: "Spotify cache"),
        .init(id: "browser.safari.cache", relativePath: "Library/Caches/com.apple.Safari", category: .caches,
              explanation: "Safari generated cache. Browser history and website data are excluded.",
              consequence: "Pages may load more slowly on their next visit. Close Safari first.", owner: "com.apple.Safari", name: "Safari cache"),
        .init(id: "developer.homebrew.cache", relativePath: "Library/Caches/Homebrew", category: .developer,
              explanation: "Downloaded Homebrew package artifacts, separate from installed packages.",
              consequence: "Future installs may download packages again. Do not clean during a Homebrew operation.", owner: nil, name: "Homebrew downloads")
    ] + expanded

    private static let expanded: [CleanupRule] = [
        browser("firefox", name: "Firefox", path: "Firefox/Profiles", owner: "org.mozilla.firefox"),
        browser("zen", name: "Zen", path: "zen/Profiles", owner: "app.zen-browser.zen"),
        browser("brave", name: "Brave", path: "BraveSoftware/Brave-Browser", owner: "com.brave.Browser", chromium: true),
        browser("edge", name: "Microsoft Edge", path: "Microsoft Edge", owner: "com.microsoft.edgemac", chromium: true),
        .init(id: "developer.npm.cache", relativePath: ".npm/_cacache", category: .developer,
              explanation: "npm's content-addressed download cache. Project dependencies and npm configuration are excluded.",
              consequence: "Future installs may download packages again. Offline installs may be unavailable until the cache is rebuilt.", owner: nil, name: "npm downloads", tools: [.packageManager]),
        .init(id: "developer.npm.npx", relativePath: ".npm/_npx", category: .developer,
              explanation: "Temporary packages downloaded by npx. Project node_modules and configuration are excluded.",
              consequence: "The next npx invocation may download its tools again. Offline use may be affected.", owner: nil, name: "npx tools", tools: [.packageManager]),
        .init(id: "developer.npm.logs", relativePath: ".npm/_logs", category: .logs,
              explanation: "npm diagnostic logs from previous commands.", consequence: "Previous install diagnostics will no longer be available here.", owner: nil, name: "npm logs", tools: [.packageManager]),
        .init(id: "developer.yarn.classic", relativePath: "Library/Caches/Yarn/v6", category: .developer,
              explanation: "Yarn Classic's global package cache. Project .yarn/cache, offline mirrors, configuration, and installed dependencies are excluded.",
              consequence: "Yarn may download packages again. Offline installs may need the cache restored.", owner: nil, name: "Yarn Classic downloads", tools: [.packageManager]),
        .init(id: "developer.pnpm.metadata", relativePath: "Library/Caches/pnpm/metadata-v1.3", category: .developer,
              explanation: "pnpm registry metadata cache. Its shared package store and project links are excluded.",
              consequence: "pnpm will fetch registry metadata again. No shared package store is removed.", owner: nil, name: "pnpm registry metadata", tools: [.packageManager]),
        .init(id: "developer.pnpm.metadata-v1.4", relativePath: "Library/Caches/pnpm/metadata-v1.4", category: .developer,
              explanation: "pnpm registry metadata cache. Its shared package store and project links are excluded.",
              consequence: "Registry metadata will be fetched again; offline installs may be affected.", owner: nil, name: "pnpm registry metadata", tools: [.packageManager]),
        .init(id: "developer.simulator.caches", relativePath: "Library/Developer/CoreSimulator/Caches", category: .developer,
              explanation: "Generated CoreSimulator caches. Devices, installed runtimes, app documents, and device backups are excluded.",
              consequence: "Simulator startup may take longer while caches rebuild. All simulators and developer tools must be stopped first.", owner: "com.apple.iphonesimulator", name: "Simulator caches", safety: .review, tools: [.simulator, .xcode]),
        .init(id: "developer.simulator.logs", relativePath: "Library/Logs/CoreSimulator", category: .logs,
              explanation: "CoreSimulator diagnostic logs. Device contents and runtimes are excluded.",
              consequence: "Previous Simulator diagnostics will no longer be available here. Stop simulators before cleaning.", owner: "com.apple.iphonesimulator", name: "Simulator logs", tools: [.simulator, .xcode])
    ]

    private static func browser(_ id: String, name: String, path: String, owner: String, chromium: Bool = false) -> CleanupRule {
        .init(id: "browser.\(id).profile-cache", relativePath: "Library/Caches/\(path)", category: .caches,
              explanation: "\(name) generated local profile caches. Only named cache folders are included; cookies, sessions, history, passwords, and website storage are excluded.",
              consequence: "Web content and scripts will be fetched or compiled again. Close \(name) before cleaning.", owner: owner, name: "\(name) web caches",
              profileLeaves: chromium ? ["Cache", "Code Cache", "GPUCache"] : ["cache2", "startupCache"], chromiumProfiles: chromium)
    }
}
