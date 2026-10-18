import Foundation
import Darwin
import Testing
@testable import LumaCore

private struct CacheFixture {
    let home: URL
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, text: String = "fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Audited generated data coverage") struct GeneratedDataTests {
    @Test func firefoxAndZenOnlyIncludeLocalCacheLeaves() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        _ = try f.file("Library/Caches/zen/Profiles/abcdefgh.Default (release)/cache2/entries/cache")
        _ = try f.file("Library/Caches/Firefox/Profiles/ijklmnop.default/startupCache/cache")
        _ = try f.file("Library/Caches/zen/Profiles/abcdefgh.Default (release)/storage/default/offline-document")
        _ = try f.file("Library/Application Support/zen/Profiles/abcdefgh.Default (release)/cookies.sqlite")
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.items.count == 2)
        #expect(report.items.allSatisfy { ["cache2", "startupCache"].contains($0.url.lastPathComponent) })
        for item in report.items { try SafetyEngine(home: f.home).validate(item) }
    }

    @Test func chromiumProfilesExcludeSessionsAndWebsiteStorage() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        _ = try f.file("Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data")
        _ = try f.file("Library/Caches/Microsoft Edge/Profile 2/Code Cache/data")
        _ = try f.file("Library/Caches/BraveSoftware/Brave-Browser/Default/Service Worker/CacheStorage/offline")
        _ = try f.file("Library/Caches/Microsoft Edge/Profile 2/Sessions/open-tabs")
        _ = try f.file("Library/Caches/Microsoft Edge/Personal/Cache/unsupported")
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.items.count == 2)
        for item in report.items { try SafetyEngine(home: f.home).validate(item) }
    }

    @Test func hiddenActiveMozillaCacheProfilesAreIncluded() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        let file = try f.file("Library/Caches/zen/Profiles/0c12beqk.Default (release)/cache2/entries/cache")
        let profile = file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(chflags(profile.path, UInt32(UF_HIDDEN)) == 0)
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.items.count == 1)
        #expect(report.items.first?.ruleID == "browser.zen.profile-cache")
    }

    @Test func forgedProfileRulesCannotSelectBroaderDataOrSpoofOwner() throws {
        let f = try CacheFixture(); defer { f.remove() }
        let cache = try f.file("Library/Caches/zen/Profiles/abcdefgh.Default/cache2/data").deletingLastPathComponent()
        let rule = try #require(Rules.generated.first { $0.id == "browser.zen.profile-cache" })
        let root = cache.deletingLastPathComponent()
        let forged = try Filesystem.item(root, category: .caches, safety: .safe, explanation: "test", consequence: "test", rule: rule.id, owner: rule.owner)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(forged) }
        let spoofed = try Filesystem.item(cache, category: .caches, safety: .safe, explanation: "test", consequence: "test", rule: rule.id)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(spoofed, runningBundleIDs: ["app.zen-browser.zen"]) }
    }

    @Test func packageRulesExcludeSharedStoresAndProjectCaches() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        _ = try f.file(".npm/_cacache/content-v2/package")
        _ = try f.file(".npm/_logs/install.log")
        _ = try f.file("Library/Caches/Yarn/v6/package")
        _ = try f.file("Library/Caches/pnpm/metadata-v1.3/package.json")
        _ = try f.file("Library/pnpm/store/v11/links/referenced-package")
        _ = try f.file("Projects/example/.yarn/cache/offline.zip")
        _ = try f.file("Projects/example/node_modules/package/index.js")
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.items.count == 4)
        for item in report.items { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [])) }
        let item = try #require(report.items.first)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [.packageManager])) }
    }

    @Test func activeOrUnknownSimulatorStateBlocksCleanup() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        _ = try f.file("Library/Developer/CoreSimulator/Caches/dyld/cache")
        _ = try f.file("Library/Developer/CoreSimulator/Devices/device/data/Documents/important")
        let report = try await GeneratedDataScanner(home: f.home).scan()
        let item = try #require(report.items.first)
        #expect(item.safety == .review)
        #expect(report.items.count == 1)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [], simulatorsBooted: true)) }
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [])) }
        try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [], simulatorsBooted: false))
    }

    @Test func symlinkedProfileCreatesAnExplicitExclusion() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        let personal = try f.file("Documents/offline/cache2/document").deletingLastPathComponent().deletingLastPathComponent()
        let profiles = f.home.appendingPathComponent("Library/Caches/zen/Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: profiles.appendingPathComponent("abcdefgh.default"), withDestinationURL: personal)
        _ = try f.file("Library/Caches/zen/Profiles/ijklmnop.default/cache2/good")
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.items.count == 1)
        #expect(!report.isComplete)
        #expect(report.coverage.contains { $0.ruleID == "browser.zen.profile-cache" && $0.state == .skipped })
    }

    @Test func missingEmptyAndDeniedRemainDistinct() async throws {
        let f = try CacheFixture(); defer { f.remove() }
        try FileManager.default.createDirectory(at: f.home.appendingPathComponent(".npm/_cacache"), withIntermediateDirectories: true)
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(report.coverage.contains { $0.ruleID == "developer.npm.cache" && $0.state == .empty })
        #expect(report.coverage.contains { $0.ruleID == "developer.npm.logs" && $0.state == .missing })
        #expect(report.isComplete)
        #expect(GeneratedDataScanner.failureState(NSError(domain: NSPOSIXErrorDomain, code: 13)) == .blocked)
        #expect(GeneratedDataScanner.failureState(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) == .blocked)
    }

    @Test func unreadableCacheIsReportedAsBlockedInsteadOfEmpty() async throws {
        guard geteuid() != 0 else { return }
        let f = try CacheFixture(); defer { f.remove() }
        let file = try f.file(".npm/_cacache/content-v2/package")
        let cache = file.deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cache.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path) }
        let report = try await GeneratedDataScanner(home: f.home).scan()
        #expect(!report.isComplete)
        #expect(report.coverage.contains { $0.ruleID == "developer.npm.cache" && $0.state == .blocked })
        #expect(!report.items.contains { $0.ruleID == "developer.npm.cache" })
    }

    @Test func packageManagerScriptsAndSimulatorProcessesAreRecognized() {
        let active = CleanupActivity.classify("/usr/local/bin/node /usr/local/lib/node_modules/npm/bin/npm-cli.js install\n/Applications/Xcode.app/Contents/MacOS/Xcode\n/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator")
        #expect(active == [.packageManager, .xcode, .simulator, .projectBuild])
        #expect(CleanupActivity.classify("/usr/bin/other /tmp/npm-project/document").isEmpty)
    }
}
