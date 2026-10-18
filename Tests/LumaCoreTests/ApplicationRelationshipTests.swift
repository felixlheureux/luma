import Foundation
import Testing
@testable import LumaCore

private struct RelationshipFixture {
    let home: URL
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/relationships-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, _ content: String = "fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func app(_ owner: String = "com.microsoft.VSCode") throws -> ApplicationRecord {
        let path = "Applications/Fixture.app"
        try file(path + "/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(owner)</string></dict></plist>")
        return ApplicationRecord(url: home.appendingPathComponent(path), name: "Fixture", bundleID: owner, version: "1", bytes: 0)
    }
    func inspect(_ app: ApplicationRecord) throws -> ApplicationFootprint {
        try #require(ApplicationFootprintScanner.inspect(app, home: home).applicationFootprint)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Shared application relationships") struct ApplicationRelationshipTests {
    @Test func namedEvidenceAgreesForInstalledAndRemovedOwners() async throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        let data = try f.file("Library/Application Support/Code/Documents/keep", "valuable document")
        try f.file("Library/Application Support/Code Backup/keep")
        let footprint = try f.inspect(app)
        let entry = try #require(footprint.entries.first { $0.relationship.url.lastPathComponent == "Code" })
        #expect(entry.relationship.category == .userData)
        #expect(entry.item?.safety == .review)
        #expect(footprint.items.allSatisfy { $0.url.lastPathComponent != "Code Backup" })
        #expect(try await LeftoverScanner(home: f.home, applicationRoots: [f.home.appendingPathComponent("Applications")], lookup: { _ in false }).scan().items.isEmpty)
        try FileManager.default.removeItem(at: app.url)
        let leftovers = try await LeftoverScanner(home: f.home, applicationRoots: [], lookup: { _ in false }).scan()
        let item = try #require(leftovers.items.first { $0.url == data.deletingLastPathComponent().deletingLastPathComponent() })
        #expect(item.explanation.hasPrefix(entry.relationship.evidence))
        #expect(item.consequence == entry.relationship.consequence)
        #expect(LeftoverScanner.matches(item, home: f.home))
        // Launch Services may still have the real named product installed; discovery uses an injected lookup.
    }

    @Test func deniedRelationshipRetainsOthersAndNeverBecomesZero() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        try f.file("Library/Application Support/Code/keep")
        try f.file("Library/Caches/com.microsoft.VSCode/cache")
        let result = try ApplicationFootprintScanner.inspect(app, home: f.home, checkAccess: { url in
            if url.lastPathComponent == "Code" { throw CocoaError(.fileReadNoPermission) }
        })
        let footprint = try #require(result.applicationFootprint)
        let denied = try #require(footprint.entries.first { $0.relationship.url.lastPathComponent == "Code" })
        #expect(denied.state == .blocked && denied.bytes == nil && denied.item == nil)
        #expect(!footprint.isComplete && !result.report.isComplete)
        #expect(footprint.items.count == 2)
        #expect(footprint.entries.contains { $0.state == .missing && $0.bytes == nil })
    }

    @Test func overlappingMappingsAndHardLinksCountOnceLikeReview() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        let source = try f.file("Library/Application Support/Code/CachedData/data", "shared content")
        let cache = f.home.appendingPathComponent("Library/Caches/com.microsoft.VSCode")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: source, to: cache.appendingPathComponent("linked"))
        try f.file("Library/Preferences/com.microsoft.VSCode.plist", "settings")
        let footprint = try f.inspect(app)
        #expect(!footprint.items.contains { $0.url.lastPathComponent == "CachedData" })
        let plan = try CleanupPlan(items: footprint.items, source: .applications)
        #expect(footprint.inspectedBytes == plan.logicalBytes)
        #expect(FootprintCategory.allCases.reduce(Int64(0)) { $0 + footprint.bytes(in: $1) } == plan.logicalBytes)
        let dataOnly = footprint.items.filter { $0.category != .applications }
        #expect(footprint.accounting.bytes(for: dataOnly) == (try CleanupPlan(items: dataOnly, source: .applications)).logicalBytes)
    }

    @Test func containersRequireFreshExactMetadataAndSharedGroupsStayExcluded() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app("org.lumatest.container")
        let metadata = "Library/Containers/org.lumatest.container/.com.apple.containermanagerd.metadata.plist"
        try f.file(metadata, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>MCMMetadataIdentifier</key><string>org.lumatest.container</string></dict></plist>")
        try f.file("Library/Group Containers/group.org.lumatest.container/keep")
        let footprint = try f.inspect(app)
        let container = try #require(footprint.items.first { $0.url.lastPathComponent == app.bundleID })
        try SafetyEngine(home: f.home).validate(container)
        #expect(!footprint.items.contains { $0.url.path.contains("Group Containers") })
        try f.file(metadata, "changed")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(container) }
        #expect(ApplicationRelationships.candidates(owner: "group.org.lumatest.container", home: f.home).isEmpty)
    }

    @Test func similarlyNamedOwnersCannotClaimMappedDataAndSafeLabelCannotBeForged() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app("org.lumatest.Code")
        let url = try f.file("Library/Application Support/Code/keep").deletingLastPathComponent()
        #expect(!((try f.inspect(app)).items.contains { $0.url == url }))
        let forged = try Filesystem.item(url, category: .related, safety: .review, explanation: "", consequence: "", rule: "application.exact-related", owner: app.bundleID)
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(forged) }
        let unsafe = try Filesystem.item(url, category: .related, safety: .safe, explanation: "", consequence: "", rule: "application.exact-related", owner: "com.microsoft.VSCode")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(unsafe) }
    }

    @Test func verifiedHelperWithDifferentIdentifierBlocksRelatedRemoval() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app("org.lumatest.parent")
        try f.file("Applications/Fixture.app/Contents/Library/LoginItems/Helper.app/Contents/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.different.helper</string></dict></plist>")
        try f.file("Library/Caches/org.lumatest.parent/data")
        let item = try #require(try f.inspect(app).items.first { $0.category == .related })
        #expect(try ApplicationPresence.bundleIdentifiers(home: f.home, roots: [f.home.appendingPathComponent("Applications")], matchingOwner: app.bundleID).contains("org.different.helper"))
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, runningBundleIDs: ["org.different.helper"]) }
    }

    @Test func ambiguousOverlappingOwnersAreExcluded() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let parent = "Library/Application Support/Shared"
        let mappings = [KnownLeftoverPath(relativePath: parent, owner: "org.lumatest.one"),
                        KnownLeftoverPath(relativePath: parent + "/Child", owner: "org.lumatest.two")]
        #expect(!ApplicationRelationships.isUnambiguous(url: f.home.appendingPathComponent(parent), owner: "org.lumatest.one", home: f.home, mappings: mappings))
        #expect(!ApplicationRelationships.isUnambiguous(url: f.home.appendingPathComponent(parent + "/Child"), owner: "org.lumatest.two", home: f.home, mappings: mappings))
        #expect(ApplicationRelationships.isUnambiguous(url: f.home.appendingPathComponent(parent + " Backup"), owner: "org.lumatest.one", home: f.home, mappings: mappings))
    }

    @Test func providerChangesBlockDisplayedNamedCandidate() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        try f.file("Library/Application Support/Code/keep")
        let item = try #require(try f.inspect(app).items.first { $0.url.lastPathComponent == "Code" })
        FilesystemAccess.$restriction.withValue({ url in
            Filesystem.isWithin(url, root: item.url) ? .providerManaged : .local
        }) {
            #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
            #expect(throws: (any Error).self) { try CleanupPlan(items: [item], source: .applications) }
        }
    }

    @Test func namedRelationshipJournalRoundTripPreservesAdjacentData() async throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        let data = try f.file("Library/Application Support/Code/offline", "valuable content")
        let adjacent = try f.file("Library/Application Support/Code Backup/keep", "keep")
        let item = try #require(try f.inspect(app).items.first { $0.url.lastPathComponent == "Code" })
        let trash = f.home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        })
        let records = try await journal.execute(CleanupPlan(items: [item], source: .applications), context: { CleanupExecutionContext() })
        #expect(records.count == 1)
        #expect(!FileManager.default.fileExists(atPath: data.path))
        #expect(try String(contentsOf: adjacent, encoding: .utf8) == "keep")
        try await journal.restore(try #require(records.first))
        #expect(try String(contentsOf: data, encoding: .utf8) == "valuable content")
    }

    @Test func symlinkProviderAndChangedPathsRemainRejected() throws {
        let f = try RelationshipFixture(); defer { f.remove() }
        let app = try f.app()
        let personal = try f.file("Documents/keep")
        let support = f.home.appendingPathComponent("Library/Application Support/Code")
        try FileManager.default.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: support, withDestinationURL: personal.deletingLastPathComponent())
        #expect(!((try f.inspect(app)).items.contains { Filesystem.samePath($0.url, support) }))
        try FileManager.default.removeItem(at: support)
        try f.file("Library/Application Support/Code/keep")
        let item = try #require(try f.inspect(app).items.first { Filesystem.samePath($0.url, support) })
        try f.file("Library/Application Support/Code/new")
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item) }
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home, ignoredPaths: [support.path]).validate(item) }
    }
}
