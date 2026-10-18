import Foundation
import Testing
@testable import LumaCore

private struct LeftoverFixture {
    let home: URL
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    func file(_ path: String, content: String = "fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func app(_ path: String, id: String) throws {
        _ = try file(path + "/Contents/Info.plist", content: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(id)</string></dict></plist>")
    }
    func scanner() -> LeftoverScanner {
        LeftoverScanner(home: home, applicationRoots: [home.appendingPathComponent("Applications")], lookup: { _ in false })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("App leftover ownership") struct LeftoverTests {
    @Test func orphanIdentifiersAreReviewOnly() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Caches/org.lumatest.removed/cache")
        _ = try f.file("Library/Preferences/org.lumatest.removed.plist")
        let report = try await f.scanner().scan()
        #expect(report.items.count == 2)
        #expect(report.isComplete)
        #expect(report.items.allSatisfy { $0.safety == .review && $0.ownerBundleID == "org.lumatest.removed" })
        #expect(report.items.allSatisfy { LeftoverScanner.matches($0, home: f.home) })
    }
    @Test func installedAppDataExcluded() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        try f.app("Applications/Installed.app", id: "org.lumatest.installed")
        _ = try f.file("Library/Caches/org.lumatest.installed/cache")
        #expect(try await f.scanner().scan().items.isEmpty)
    }
    @Test func embeddedAndNamespacedHelpersExcluded() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        try f.app("Applications/Installed.app", id: "org.lumatest.installed")
        try f.app("Applications/Installed.app/Contents/Library/LoginItems/Helper.app", id: "org.different.helper")
        _ = try f.file("Library/Caches/org.different.helper/cache")
        _ = try f.file("Library/Caches/org.lumatest.installed.child/cache")
        #expect(try await f.scanner().scan().items.isEmpty)
    }
    @Test func nestedApplicationFolderIncluded() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        try f.app("Applications/Vendor/Installed.app", id: "org.lumatest.installed")
        _ = try f.file("Library/Preferences/org.lumatest.installed.plist")
        #expect(try await f.scanner().scan().items.isEmpty)
    }
    @Test func launchServicesOwnerOutsideApplicationFoldersExcluded() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Preferences/org.lumatest.external.plist")
        let scanner = LeftoverScanner(home: f.home, applicationRoots: [], lookup: { $0 == "org.lumatest.external" })
        #expect(try await scanner.scan().items.isEmpty)
    }
    @Test func appleSharedAndFuzzyNamesExcluded() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        for name in ["com.apple.important", "group.org.lumatest.shared", "My Old App", "com.vendor"] {
            _ = try f.file("Library/Application Support/\(name)/state")
        }
        _ = try f.file("Library/Group Containers/org.lumatest.shared/state")
        _ = try f.file("Documents/org.lumatest.personal")
        #expect(try await f.scanner().scan().items.isEmpty)
    }
    @Test func containerRequiresMatchingMetadata() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Containers/org.lumatest.unknown/state")
        let metadata = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>MCMMetadataIdentifier</key><string>org.lumatest.known</string></dict></plist>"
        _ = try f.file("Library/Containers/org.lumatest.known/.com.apple.containermanagerd.metadata.plist", content: metadata)
        let report = try await f.scanner().scan()
        #expect(report.items.count == 1)
        #expect(report.items.first?.ownerBundleID == "org.lumatest.known")
    }
    @Test func symlinkEscapeExcludedWithCoverageNotice() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        let target = try f.file("Documents/personal")
        let link = f.home.appendingPathComponent("Library/Caches/org.lumatest.escape")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        let report = try await f.scanner().scan()
        #expect(report.items.isEmpty)
        #expect(!report.notices.isEmpty)
    }
    @Test func reinstalledOwnerBlocksOldPlan() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Preferences/org.lumatest.reinstalled.plist")
        let report = try await f.scanner().scan()
        let item = try #require(report.items.first)
        try SafetyEngine(home: f.home).validate(item)
        try f.app("Applications/Back.app", id: "org.lumatest.reinstalled")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
    }
    @Test func forgedLeftoverRuleCannotSelectPersonalFiles() throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        let url = try f.file("Documents/org.lumatest.personal")
        let item = try Filesystem.item(url, category: .related, safety: .review, explanation: "test", consequence: "test", rule: "application.leftover.exact-identifier", owner: "org.lumatest.personal")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
    }
    @Test func ignoredLeftoverIsRejected() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Preferences/org.lumatest.ignored.plist")
        let item = try #require(try await f.scanner().scan().items.first)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home, ignoredPaths: [item.id]).validate(item) }
    }
    @Test func knownSupportFoldersUseExplicitRulesWithoutFuzzyMatches() async throws {
        let f = try LeftoverFixture(); defer { f.remove() }
        _ = try f.file("Library/Application Support/Spotify/offline-content")
        _ = try f.file("Library/Application Support/Spotify Backup/keep")
        _ = try f.file("Library/Application Support/obsidian/settings")
        let report = try await f.scanner().scan()
        #expect(report.items.count == 2)
        #expect(report.isComplete)
        #expect(report.items.allSatisfy { $0.safety == .review && LeftoverScanner.matches($0, home: f.home) })
        #expect(report.items.contains { $0.ownerBundleID == "md.obsidian" })
        #expect(!report.items.contains { $0.name == "Spotify Backup" })
    }
}
