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

@Suite("Hidden home app data") struct HiddenHomeResidueTests {
    private func home() throws -> URL {
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/hidden-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
    private func write(_ relative: String, home: URL) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic app data".utf8).write(to: url)
    }
    private func catalog(_ paths: [(String, String)] = [(".vendor-app", "org.lumatest.vendor"), (".config/editor-a", "org.lumatest.editora"), (".config/editor-b", "org.lumatest.editorb")]) throws -> RuleCatalog {
        let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/LumaCore/Resources/CleanupRules.yaml")
        var yaml = try String(contentsOf: source, encoding: .utf8)
        for (path, owner) in paths {
            yaml += """

            - relativePath: \(path)
              owner: \(owner)
              classification: review
              cliNames: [fixture-cli]
              explanation: Exact synthetic ownership mapping.
              consequence: Removes synthetic user settings.
              provenance: [Disposable fixture only]
              reviewedOn: '2026-10-21'

            """
        }
        return try RuleLoader.load(data: Data(yaml.utf8))
    }
    @Test func stagedUnknownAndInstalledOwnersStaySeparate() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        for path in [".vendor-app/data", ".mystery/data", ".config/editor-a/settings", ".config/editor-b/settings", ".ssh/key", ".aws/credentials", ".local/share/unknown/data", ".zshrc"] { try write(path, home: home) }
        let catalog = try catalog()
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { $0 == "org.lumatest.editorb" }, toolLookup: { _, _ in .absent }).scan()
            #expect(Set(report.items.map { $0.url.lastPathComponent }) == [".vendor-app", "editor-a"])
            let unknown = try #require(report.hiddenAppData.first { $0.url.lastPathComponent == ".mystery" })
            #expect(unknown.owner == nil && unknown.state == .unknown && unknown.bytes == nil)
            #expect(report.hiddenAppData.first { $0.url.lastPathComponent == "editor-b" }?.state == .present)
            #expect(report.hiddenAppData.first { $0.url.lastPathComponent == ".config" }?.owner == nil)
            #expect(!report.hiddenAppData.contains { $0.url.lastPathComponent == ".zshrc" })
            #expect(report.hiddenAppData.first { $0.url.lastPathComponent == ".ssh" }?.bytes == nil)
            #expect(LeftoverGroup.groups(for: report.items).allSatisfy { $0.id != "Unknown owner" })
            let store = ResidueObservationStore(home: home)
            try await store.save(.init(items: report.items, complete: report.isComplete, hiddenAppData: report.hiddenAppData))
            #expect(try await store.load()?.hiddenAppData?.count == report.hiddenAppData.count)
        }
    }
    @Test func toolUnknownSharedOwnerAndRunningHelperRejectMutation() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        try write(".vendor-app/data", home: home)
        let catalog = try catalog()
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            for state in [HiddenOwnerState.present, .unknown] {
                let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in state }).scan()
                #expect(report.items.isEmpty)
                #expect(report.hiddenAppData.first { $0.url.lastPathComponent == ".vendor-app" }?.state == state)
            }
            let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in .absent }).scan()
            let item = try #require(report.items.first)
            #expect(!SafetyEngine(home: home).permitsManualSelection(at: item.url, authorizedRoots: [home]))
            #expect(!SafetyEngine(home: home).permitsManualSelection(at: item.url.appendingPathComponent("data"), authorizedRoots: [home]))
            for state in [HiddenOwnerState.present, .unknown] {
                HiddenAppData.$toolPresenceOverride.withValue(state) {
                    #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(item, authorizedRoots: [], runningBundleIDs: [], activity: nil, preflightOwners: [], progress: { _ in }) }
                }
            }
            try HiddenAppData.$toolPresenceOverride.withValue(.absent) {
                try SafetyEngine(home: home).validate(item, authorizedRoots: [], runningBundleIDs: [], activity: nil, preflightOwners: [], progress: { _ in })
                #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(item, authorizedRoots: [], runningBundleIDs: ["org.lumatest.vendor.helper"], activity: nil, preflightOwners: [], progress: { _ in }) }
                #expect(throws: (any Error).self) { try SafetyEngine(home: home, ignoredPaths: [item.url.appendingPathComponent("data").path]).validate(item, authorizedRoots: [], runningBundleIDs: [], activity: nil, preflightOwners: [], progress: { _ in }) }
            }
        }
    }
    @Test func replacedLinkedDeniedAndLargeCandidatesNeverAuthorizeCleanup() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        try write(".vendor-app/data", home: home)
        let catalog = try catalog()
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in .absent }).scan()
            let item = try #require(report.items.first)
            let url = home.appendingPathComponent(".vendor-app")
            try FileManager.default.moveItem(at: url, to: home.appendingPathComponent("old"))
            try write(".vendor-app/data", home: home)
            #expect(throws: (any Error).self) { try ResidueObservations.prepare([item], home: home, ignoredPaths: []) }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: home.appendingPathComponent("old"))
            let linked = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in .absent }).scan()
            #expect(linked.items.isEmpty)
            #expect(linked.hiddenAppData.first { $0.url.path == url.path }?.state == .unknown)
            try FileManager.default.removeItem(at: url)
            try write(".vendor-app/data", home: home)
            let denied = try await FilesystemAccess.$restriction.withValue({ candidate in
                Filesystem.isWithin(candidate, root: url) ? .unknown : .local
            }) { try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in .absent }).scan() }
            #expect(denied.items.isEmpty)
            #expect(denied.hiddenAppData.first { $0.url.path == url.path }?.bytes == nil)
            for n in 0..<2_001 { try write(".vendor-app/file-\(n)", home: home) }
            let large = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, toolLookup: { _, _ in .absent }).scan()
            #expect(large.items.isEmpty && !large.isComplete)
            #expect(large.hiddenAppData.first { $0.url.path == url.path }?.bytes == nil)
        }
    }
    @Test func targetedRefreshDoesNotEnumerateHomeOrOtherLeaves() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        for path in [".vendor-app/data", ".config/editor-a/settings", ".config/editor-b/settings", ".mystery/data"] { try write(path, home: home) }
        let catalog = try catalog()
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, owners: ["org.lumatest.editora"], toolLookup: { _, _ in .absent }).scan()
            #expect(report.hiddenAppData.count == 1 && report.items.count == 1)
            #expect(report.items.first?.url.lastPathComponent == "editor-a")
            #expect(!report.coverage.contains { $0.ruleID == "hidden.inventory" })
        }
    }
    @Test func verifiedHiddenLeafUsesJournalTrashAndUndo() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        try write(".vendor-app/data", home: home)
        try write(".config/editor-b/keep", home: home)
        let catalog = try catalog()
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            try await HiddenAppData.$toolPresenceOverride.withValue(.absent) {
                let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { _ in false }, owners: ["org.lumatest.vendor"]).scan()
                let item = try #require(report.items.first)
                let trash = home.appendingPathComponent(".Trash")
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let journal = try CleanupJournal(home: home, trashMover: { source in
                    let destination = trash.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at: source, to: destination)
                    return destination
                })
                let plan = try ResidueObservations.prepare([item], home: home, ignoredPaths: [])
                let records = try await journal.execute(plan, context: { CleanupExecutionContext() })
                #expect(records.count == 1 && !FileManager.default.fileExists(atPath: item.url.path))
                #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/editor-b/keep").path))
                try await journal.undo(try await journal.reviewUndo(sessionID: plan.id))
                #expect(FileManager.default.fileExists(atPath: item.url.appendingPathComponent("data").path))
                #expect(LeftoverScanner.owner(at: item.url, home: home) == "org.lumatest.vendor")
            }
        }
    }
    @Test func catalogRejectsProtectedRootsAndCredentials() throws {
        for path in [".ssh", ".ssh/keys", ".aws", ".config", ".cache", ".local", ".config/git", ".config/.ssh", ".local/share/.aws", ".config/.zsh_sessions", ".config/luma", ".local/share/keychains", ".zshrc", ".git-credentials", ".codex"] {
            #expect(throws: (any Error).self) { try catalog([(path, "org.lumatest.vendor")]) }
        }
    }
    @Test func cliLinksAndSharedAppVariantsKeepShippingData() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        try write(".vscode/extensions/data", home: home)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home.appendingPathComponent("bin/code").path, withDestinationPath: "/missing/standalone-cli")
        let mapping = try #require(ApplicationRelationships.knownPaths.first { $0.relativePath == ".vscode" })
        #expect(HiddenAppData.toolPresence(mapping, home: home) != .absent)
        let report = try await LeftoverScanner(home: home, applicationRoots: [], lookup: { $0 == "com.microsoft.VSCodeInsiders" }, toolLookup: { _, _ in .absent }).scan()
        #expect(!report.items.contains { $0.url.lastPathComponent == ".vscode" })
        #expect(report.hiddenAppData.first { $0.url.lastPathComponent == ".vscode" }?.state == .present)
    }
}
