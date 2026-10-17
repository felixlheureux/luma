import Foundation
import Testing
@testable import LumaCore

private struct Fixture {
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
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Safety boundaries") struct SafetyTests {
    @Test func generatedRuleValidates() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.file("Library/Developer/Xcode/DerivedData/build.o")
        let rule = Rules.generated[0]
        let item = try Filesystem.item(f.home.appendingPathComponent(rule.relativePath), category: .developer, safety: .safe,
            explanation: rule.explanation, consequence: rule.consequence, rule: rule.id, owner: rule.owner)
        try SafetyEngine(home: f.home).validate(item, activity: .init(tools: []))
    }

    @Test func protectedHomeFolderRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.file("Documents/important.txt")
        let item = try Filesystem.item(f.home.appendingPathComponent("Documents"), category: .storage, safety: .userData,
            explanation: "test", consequence: "test", rule: "manual.folder-review")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, authorizedRoots: [f.home]) }
    }

    @Test func symlinkEscapeRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let personal = try f.file("Documents/important.txt")
        let cache = f.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("escape"), withDestinationURL: personal.deletingLastPathComponent())
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(cache) }
        #expect(try String(contentsOf: personal, encoding: .utf8) == "fixture")
    }

    @Test func parentSymlinkRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let target = try f.file("Documents/file.txt")
        let link = f.home.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(link.appendingPathComponent("file.txt")) }
    }

    @Test func staleTreeRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Downloads/review.txt", content: "old")
        let item = try Filesystem.item(url, category: .storage, safety: .userData, explanation: "test", consequence: "test", rule: "manual.folder-review")
        try Data("new content".utf8).write(to: url)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, authorizedRoots: [f.home.appendingPathComponent("Downloads")]) }
    }

    @Test func changedChildRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Library/Developer/Xcode/DerivedData/build.o")
        let item = try Filesystem.item(url.deletingLastPathComponent(), category: .developer, safety: .safe, explanation: "test", consequence: "test", rule: Rules.generated[0].id)
        _ = try f.file("Library/Developer/Xcode/DerivedData/another.o")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
    }

    @Test func ignoresOverrideRules() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Library/Developer/Xcode/DerivedData/build.o")
        let item = try Filesystem.item(url.deletingLastPathComponent(), category: .developer, safety: .safe, explanation: "test", consequence: "test", rule: Rules.generated[0].id)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home, ignoredPaths: [f.home.appendingPathComponent("Library/Developer").path]).validate(item) }
    }

    @Test func runningOwnerRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Library/Developer/Xcode/DerivedData/build.o")
        let item = try Filesystem.item(url.deletingLastPathComponent(), category: .developer, safety: .safe, explanation: "test", consequence: "test", rule: Rules.generated[0].id, owner: "com.apple.dt.Xcode")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, runningBundleIDs: ["com.apple.dt.Xcode"]) }
    }

    @Test func forgedRuleCannotSelectDocuments() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Documents/my-source.swift")
        let item = try Filesystem.item(url, category: .developer, safety: .safe, explanation: "test", consequence: "test", rule: Rules.generated[0].id)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
    }

    @Test func manualReviewRequiresChosenRoot() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Downloads/installer.dmg")
        let item = try Filesystem.item(url, category: .storage, safety: .userData, explanation: "test", consequence: "test", rule: "manual.folder-review")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
        try SafetyEngine(home: f.home).validate(item, authorizedRoots: [f.home.appendingPathComponent("Downloads")])
    }

    @Test func prefixCollisionRejected() {
        #expect(!Filesystem.isWithin(URL(fileURLWithPath: "/Users/person/Documents-backup"), root: URL(fileURLWithPath: "/Users/person/Documents")))
    }

    @Test func applicationInternalLinksAllowedExternalLinksRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        let bundle = f.home.appendingPathComponent("Applications/Example.app")
        _ = try f.file("Applications/Example.app/Contents/Info.plist", content: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.example.test</string></dict></plist>")
        let target = try f.file("Applications/Example.app/Contents/Frameworks/Versions/A/library")
        let link = bundle.appendingPathComponent("Contents/Frameworks/Versions/Current")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        _ = try Filesystem.inspect(bundle)
        let personal = try f.file("Documents/private.txt")
        try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("Contents/escape"), withDestinationURL: personal)
        #expect(throws: (any Error).self) { _ = try Filesystem.inspect(bundle) }
    }

    @Test func relatedIdentifierCannotMatchSimilarApplication() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Library/Preferences/org.example.similar.plist")
        let item = try Filesystem.item(url, category: .related, safety: .review, explanation: "test", consequence: "test", rule: "application.exact-related", owner: "org.example.app")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
    }

    @Test func partialScanNeverSelectsLinkedTree() async throws {
        let f = try Fixture(); defer { f.remove() }
        let target = try f.file("Documents/source.txt")
        let cache = f.home.appendingPathComponent(Rules.generated[0].relativePath)
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: target.deletingLastPathComponent())
        let result = try await GeneratedDataScanner(home: f.home).scan()
        #expect(result.items.isEmpty)
        #expect(result.notices.count == 1)
    }
}

@Suite("Content and size scanning") struct ScannerTests {
    @Test func duplicateContentNotNames() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.file("Downloads/one.txt", content: "identical bytes")
        _ = try f.file("Downloads/renamed.txt", content: "identical bytes")
        _ = try f.file("Downloads/other.txt", content: "different bytes")
        let (groups, _) = try DuplicateScanner(root: f.home.appendingPathComponent("Downloads")).scan()
        #expect(groups.count == 1)
        #expect(groups.first?.items.count == 2)
        #expect(groups.first?.recoverable == 15)
    }

    @Test func hardLinksCountedOnce() throws {
        let f = try Fixture(); defer { f.remove() }
        let url = try f.file("Downloads/one.txt", content: "content")
        try FileManager.default.linkItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("linked.txt"))
        #expect(try Filesystem.inspect(url.deletingLastPathComponent()).0 == 7)
        #expect(try DuplicateScanner(root: url.deletingLastPathComponent()).scan().0.isEmpty)
    }

    @Test func samePrefixDifferentTailNotDuplicate() throws {
        let f = try Fixture(); defer { f.remove() }
        let prefix = String(repeating: "a", count: 70_000)
        _ = try f.file("Downloads/one.bin", content: prefix + "1")
        _ = try f.file("Downloads/two.bin", content: prefix + "2")
        #expect(try DuplicateScanner(root: f.home.appendingPathComponent("Downloads")).scan().0.isEmpty)
    }

    @Test func downloadsAlwaysUserData() async throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.file("Downloads/old.dmg")
        let result = try await FolderScanner(root: f.home.appendingPathComponent("Downloads")).scan()
        #expect(result.items.count == 1)
        #expect(result.items.allSatisfy { $0.safety == .userData })
    }

    @Test func cancellationPropagates() async throws {
        let f = try Fixture(); defer { f.remove() }
        _ = try f.file("Downloads/file")
        let task = Task {
            try Task.checkCancellation()
            return try await FolderScanner(root: f.home.appendingPathComponent("Downloads")).scan()
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled scan returned results") }
        catch is CancellationError {}
    }

    @Test func rulePathsAreBoundedAndExplained() {
        for rule in Rules.generated {
            #expect(!rule.relativePath.contains(".."))
            #expect(!rule.relativePath.contains("*"))
            #expect(rule.relativePath.hasPrefix("Library/") || rule.relativePath.hasPrefix(".npm/"))
            #expect(!rule.explanation.isEmpty)
            #expect(!rule.consequence.isEmpty)
        }
        #expect(Set(Rules.generated.map(\.id)).count == Rules.generated.count)
    }
}
