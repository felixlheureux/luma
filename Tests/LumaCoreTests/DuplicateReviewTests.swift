import Foundation
import Testing
import Darwin
@testable import LumaCore

private struct DuplicateReviewFixture {
    let home: URL
    var root: URL { home.appendingPathComponent("Data") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/compare-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, text: String = "identical local text\n", date: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }
    func scan() throws -> [DuplicateGroup] { try DuplicateScanner(root: root).scan().0 }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite("Exact duplicate comparison and keeper proposals") struct DuplicateReviewTests {
    @Test func completeGroupFiltersAndStableDateTies() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try f.file("z/one.txt", date: date); try f.file("a/two.txt", date: date); try f.file("b/three.txt", date: date.addingTimeInterval(50))
        let group = try #require(f.scan().first)
        #expect(DuplicateReview.keeper(in: group, preference: .oldest)?.url.lastPathComponent == "two.txt")
        #expect(DuplicateReview.keeper(in: group, preference: .newest)?.url.lastPathComponent == "three.txt")
        #expect(DuplicateReview.groups([group], query: "/z/").first?.items.count == 3)
        #expect(DuplicateReview.groups([group], minimumBytes: group.recoverable + 1).isEmpty)
        #expect(DuplicateReview.groups([group], query: "no-match").isEmpty)
        let reversed = DuplicateGroup(id: group.id, items: group.items.reversed())
        #expect(DuplicateReview.keeper(in: group, preference: .oldest)?.id == DuplicateReview.keeper(in: reversed, preference: .oldest)?.id)
        #expect(DuplicateReview.members(group).map(\.id) == DuplicateReview.members(reversed).map(\.id))
    }

    @Test func groupOrderingDoesNotDependOnScanEnumeration() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("a/one.txt", text: "small"); try f.file("a/two.txt", text: "small")
        try f.file("z/one.txt", text: "a larger group of bytes"); try f.file("z/two.txt", text: "a larger group of bytes")
        let groups = try f.scan()
        for order in DuplicateOrder.allCases {
            #expect(DuplicateReview.groups(groups, order: order).map(\.id) == DuplicateReview.groups(groups.reversed(), order: order).map(\.id))
        }
        #expect(DuplicateReview.groups(groups, order: .path).first?.items.first?.url.path.contains("/a/") == true)
        #expect(DuplicateReview.groups(groups, order: .savings).first?.items.first?.url.path.contains("/z/") == true)
    }

    @Test func proposalIsReadOnlyAndChangedKeeperInvalidatesApplication() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("two.txt")
        let group = try #require(f.scan().first), keeper = group.items[0]
        let choice = try DuplicateKeeperChoice(group: group, keeperID: keeper.id)
        try choice.validate()
        #expect(choice.removals.map(\.id) == [group.items[1].id])
        #expect(group.items.allSatisfy { FileManager.default.fileExists(atPath: $0.id) })
        try Data("changed local text!!\n".utf8).write(to: keeper.url)
        #expect(throws: (any Error).self) { try choice.validate() }
    }

    @Test func missingRenamedIgnoredAndStaleCopiesRejectChoice() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("nested/two.txt")
        let group = try #require(f.scan().first)
        let choice = try DuplicateKeeperChoice(group: group, keeperID: group.items[0].id)
        #expect(throws: (any Error).self) { try choice.validate(ignoredPaths: [f.root.appendingPathComponent("nested").path]) }
        #expect(throws: (any Error).self) { try choice.validate(now: Date().addingTimeInterval(1_801)) }
        try FileManager.default.moveItem(at: choice.keeper.url, to: choice.keeper.url.appendingPathExtension("renamed"))
        #expect(throws: (any Error).self) { try choice.validate() }
    }

    @Test func forgedDigestAndSameSizeSameDateChangesCannotApply() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("two.txt")
        let group = try #require(f.scan().first)
        let forged = DuplicateGroup(id: String(repeating: "0", count: 64), items: group.items)
        #expect(throws: (any Error).self) { try DuplicateKeeperChoice(group: forged, keeperID: forged.items[0].id).validate() }
        let choice = try DuplicateKeeperChoice(group: group, keeperID: group.items[0].id)
        try Data(repeating: 88, count: Int(choice.keeper.bytes)).write(to: choice.keeper.url)
        try FileManager.default.setAttributes([.modificationDate: choice.keeper.identity.modified], ofItemAtPath: choice.keeper.id)
        #expect(throws: (any Error).self) { try choice.validate() }
    }

    @Test func exactComparisonDoesNotGroupSameNamesOrDifferentEncodings() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("a/same.txt", text: "one"); try f.file("b/same.txt", text: "two")
        try f.file("composed.txt", text: "é"); try f.file("decomposed.txt", text: "e\u{301}")
        #expect(try f.scan().isEmpty)
    }

    @Test func hardLinksCountOnceAndComparisonExplainsSharedBytes() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        let first = try f.file("one.txt"); try f.file("two.txt")
        let groups = try f.scan(), group = try #require(groups.first)
        try FileManager.default.linkItem(at: first, to: f.root.appendingPathComponent("hard.txt"))
        let rescanned = try #require(f.scan().first)
        #expect(rescanned.items.count == 2)
        let linked = try #require(rescanned.items.first { $0.identity.inode == group.items.first { $0.id == first.path }?.identity.inode })
        let comparison = try DuplicateComparison.read(linked)
        #expect(comparison.linkCount == 2)
        guard case .unavailable = comparison.preview else { Issue.record("Shared-file preview should be unavailable"); return }
        try DuplicateKeeperChoice(group: rescanned, keeperID: linked.id).validate()
        let aliases = DuplicateGroup(id: group.id, items: [linked, linked])
        #expect(throws: (any Error).self) { try DuplicateKeeperChoice(group: aliases, keeperID: linked.id) }
    }

    @Test func comparisonSupportsTextAndExplicitUnsupportedState() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("two.bin")
        let group = try #require(f.scan().first)
        for item in group.items {
            let result = try DuplicateComparison.read(item)
            #expect(result.linkCount == 1 && result.modified == item.identity.modified)
            if item.url.pathExtension == "txt" {
                guard case .text(let text, let truncated) = result.preview else { Issue.record("Missing text preview"); return }
                #expect(text == "identical local text\n" && !truncated)
            } else {
                guard case .unavailable = result.preview else { Issue.record("Unsupported type opened"); return }
            }
        }
    }

    @Test func providerAndDeniedCopiesCannotApplyAChoice() throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("two.txt")
        let group = try #require(f.scan().first)
        let choice = try DuplicateKeeperChoice(group: group, keeperID: group.items[0].id)
        for capability in [FilesystemCapability.providerManaged, .dataless, .network, .unknown] {
            FilesystemAccess.$restriction.withValue({ url in url == choice.keeper.url ? capability : .local }) {
                #expect(throws: (any Error).self) { try choice.validate() }
            }
        }
        let removal = try #require(choice.removals.first)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: removal.id)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: removal.id) }
        #expect(throws: (any Error).self) { try choice.validate() }
    }

    @Test func symlinkSubstitutionAndCancelledChoiceNeverApply() async throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("nested/two.txt")
        let group = try #require(f.scan().first)
        let choice = try DuplicateKeeperChoice(group: group, keeperID: group.items[0].id)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try choice.validate() }
        }
        await task.value
        let parent = f.root.appendingPathComponent("nested"), moved = f.root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        #expect(throws: (any Error).self) { try choice.validate() }
    }

    @Test func explicitChoiceStillUsesCoreKeepOneAndFixtureJournalRestore() async throws {
        let f = try DuplicateReviewFixture(); defer { f.remove() }
        try f.file("one.txt"); try f.file("two.txt"); try f.file("three.txt")
        let group = try #require(f.scan().first)
        let choice = try DuplicateKeeperChoice(group: group, keeperID: group.items[0].id)
        try choice.validate()
        #expect(throws: (any Error).self) { try CleanupPlan(items: group.items, authorizedRoots: [f.root], duplicateGroups: [group], source: .duplicates) }
        let plan = try CleanupPlan(items: choice.removals, authorizedRoots: [f.root], duplicateGroups: [group], source: .duplicates)
        let trash = f.home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        let records = try await journal.execute(plan, context: { CleanupExecutionContext() })
        #expect(FileManager.default.fileExists(atPath: choice.keeper.id))
        #expect(choice.removals.allSatisfy { !FileManager.default.fileExists(atPath: $0.id) })
        for record in records { try await journal.restore(record) }
        #expect(group.items.allSatisfy { FileManager.default.fileExists(atPath: $0.id) })
    }
}
