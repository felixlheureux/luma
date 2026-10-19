import Foundation
import Testing
@testable import LumaCore

private final class ResidueInventoryRows: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [ApplicationRecord] = []
    func receive(_ event: ScanEvent) { if case .application(let app) = event { lock.withLock { rows.append(app) } } }
    var applications: [ApplicationRecord] { lock.withLock { rows } }
}

@Suite("Residue display observations") struct ResidueObservationTests {
    private func fixture() throws -> (URL, CleanupItem) {
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/residues-\(UUID())")
        let url = home.appendingPathComponent("Library/Preferences/org.lumatest.absent.plist")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preferences".utf8).write(to: url)
        return (home, try Filesystem.item(url, category: .related, safety: .review, explanation: "Exact owner", consequence: "Settings lost", rule: "application.leftover.exact-identifier", owner: "org.lumatest.absent", captureContents: true))
    }
    @Test func relaunchAndFreshPlan() async throws {
        let (home, item) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let date = Date(timeIntervalSince1970: 1)
        try await ResidueObservationStore(home: home).save(.init(items: [item], savedAt: date, complete: false, notices: ["Access needed"]))
        let saved = try #require(try await ResidueObservationStore(home: home).load())
        #expect(saved.items == [item]); #expect(saved.savedAt == date); #expect(!saved.complete)
        let plan = try ResidueObservations.prepare(saved.items, home: home, ignoredPaths: [])
        #expect(plan.items.count == 1)
        #expect(plan.items[0].scannedAt >= item.scannedAt)
        #expect(plan.source == .leftovers)
    }
    @Test func replacedIgnoredAndPersonalPathsRejected() throws {
        let (home, item) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: (any Error).self) { try ResidueObservations.prepare([item], home: home, ignoredPaths: [item.id]) }
        try Data("changed settings".utf8).write(to: item.url)
        #expect(throws: (any Error).self) { try ResidueObservations.prepare([item], home: home, ignoredPaths: []) }
        let personal = home.appendingPathComponent("Documents/org.lumatest.absent")
        try FileManager.default.createDirectory(at: personal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: personal)
        let forged = try Filesystem.item(personal, category: .related, safety: .review, explanation: "", consequence: "", rule: item.ruleID, owner: item.ownerBundleID)
        #expect(throws: (any Error).self) { try ResidueObservations.prepare([forged], home: home, ignoredPaths: []) }
    }
    @Test func exactGroupsAndUniqueLogicalTotals() throws {
        let (home, first) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let secondURL = home.appendingPathComponent("Library/Preferences/org.lumatest.absent2.plist")
        try FileManager.default.linkItem(at: first.url, to: secondURL)
        let second = try Filesystem.item(secondURL, category: .related, safety: .review, explanation: "", consequence: "", rule: first.ruleID, owner: "org.lumatest.absent2", captureContents: true)
        let groups = LeftoverGroup.groups(for: [first, second])
        #expect(groups.count == 2)
        #expect(LeftoverGroup.logicalBytes([first, second]) == first.bytes)
        #expect(LeftoverGroup.groups(for: [first, second], search: "absent2").count == 1)
    }
    @Test func scopedRefreshInspectsOnlyChangedOwners() async throws {
        let (home, item) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let other = home.appendingPathComponent("Library/Preferences/org.lumatest.other.plist")
        try Data("unrelated".utf8).write(to: other)
        let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, owners: ["org.lumatest.absent"]).scan()
        #expect(report.items.map(\.id) == [item.id])
        #expect(report.visited == 1)
    }
    @Test func ownershipDiscoveryDoesNotPublishUnboundedDisplayRows() throws {
        let (home, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/Fixture.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": "org.lumatest.installed", "CFBundleName": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        let rows = ResidueInventoryRows()
        let owners = try ApplicationPresence.bundleIdentifiers(home: home, roots: [home.appendingPathComponent("Applications")], emit: { rows.receive($0) })
        #expect(owners.contains("org.lumatest.installed"))
        #expect(rows.applications.isEmpty)
        #expect(try ApplicationScanner.inventory(home: home, roots: [home.appendingPathComponent("Applications")]).applications.count == 1)
    }
    @Test func corruptSavedObservationsDoNotBecomeResults() async throws {
        let (home, _) = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let store = ResidueObservationStore(home: home)
        #expect(try await store.load() == nil)
        let url = home.appendingPathComponent("Library/Application Support/Luma/residue-observations.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await store.load() }
    }
}
