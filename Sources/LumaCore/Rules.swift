import Foundation

public struct CleanupRule: Sendable {
    public let id: String
    public let relativePath: String
    public let category: ItemCategory
    public let explanation: String
    public let consequence: String
    public let owner: String?
}

public enum Rules {
    public static let generated: [CleanupRule] = [
        .init(id: "developer.xcode.derived-data", relativePath: "Library/Developer/Xcode/DerivedData", category: .developer,
              explanation: "Xcode build products and indexes. Source projects and archives are excluded.",
              consequence: "Xcode will rebuild these files. Your next build and indexing pass may take longer.", owner: "com.apple.dt.Xcode"),
        .init(id: "developer.swiftpm.cache", relativePath: "Library/Caches/org.swift.swiftpm", category: .developer,
              explanation: "Downloaded Swift package build caches.", consequence: "Packages may need to be downloaded and built again.", owner: "com.apple.dt.Xcode"),
        .init(id: "browser.chrome.cache", relativePath: "Library/Caches/Google/Chrome", category: .caches,
              explanation: "Google Chrome generated cache. Cookies, history, passwords and sessions are excluded.",
              consequence: "Web content will be fetched again. Close Chrome before cleaning.", owner: "com.google.Chrome"),
        .init(id: "app.spotify.cache", relativePath: "Library/Caches/com.spotify.client", category: .caches,
              explanation: "Spotify's generated application cache. Offline downloads in Application Support are excluded.",
              consequence: "Spotify may download cached content again.", owner: "com.spotify.client"),
        .init(id: "browser.safari.cache", relativePath: "Library/Caches/com.apple.Safari", category: .caches,
              explanation: "Safari generated cache. Browser history and website data are excluded.",
              consequence: "Pages may load more slowly on their next visit. Close Safari first.", owner: "com.apple.Safari"),
        .init(id: "developer.homebrew.cache", relativePath: "Library/Caches/Homebrew", category: .developer,
              explanation: "Downloaded Homebrew package artifacts, separate from installed packages.",
              consequence: "Future installs may download packages again. Do not clean during a Homebrew operation.", owner: nil)
    ]
}
