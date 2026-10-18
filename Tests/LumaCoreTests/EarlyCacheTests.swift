import Foundation
import Darwin
import Testing
@testable import LumaCore

private struct EarlyCacheFixture {
    let home: URL
    let requirement: GeneratedOwnerRequirement
    var bundle: URL { home.appendingPathComponent("Applications/Visual Studio Code.app") }
    var data: URL { home.appendingPathComponent("Library/Application Support/Code") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/cache-\(UUID())")
        requirement = try #require(Rules.generated.first { $0.id == "app.vscode.bytecode" }?.requiredApplication)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    func install(version: String? = nil, bundleID: String? = nil, productName: String? = nil) throws {
        let info: [String: Any] = ["CFBundleIdentifier": bundleID ?? requirement.bundleID,
            "CFBundleShortVersionString": version ?? requirement.version]
        _ = try file("Applications/Visual Studio Code.app/Contents/Info.plist", data: PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
        _ = try file("Applications/Visual Studio Code.app/Contents/Resources/app/product.json", data: JSONSerialization.data(withJSONObject: ["darwinBundleIdentifier": bundleID ?? requirement.bundleID, "nameShort": productName ?? requirement.productName, "commit": requirement.commit]))
        _ = try file("Applications/Visual Studio Code.app/Contents/Resources/app/package.json", data: JSONSerialization.data(withJSONObject: ["version": version ?? requirement.version]))
    }
    @discardableResult func file(_ path: String, data: Data = Data("fixture".utf8)) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func populate() throws {
        for leaf in ["Cache", "GPUCache", "CachedData", "logs"] { try file("Library/Application Support/Code/\(leaf)/entry") }
        for leaf in ["User/settings.json", "User/globalStorage/credentials", "User/workspaceStorage/state", "User/History/revision", "Backups/unsaved", "Cookies", "Local Storage/document", "Session Storage/tabs", "Service Worker/CacheStorage/offline", "Extensions/extension", "Cache Backup/document"] {
            try file("Library/Application Support/Code/\(leaf)")
        }
        try file("Library/Group Containers/group.com.microsoft.VSCode/Cache/personal")
        try file("Library/Containers/com.microsoft.VSCode/Data/Library/Caches/personal")
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
    func scan() async throws -> ScanReport {
        try await VerifiedGeneratedOwner.$applicationRootsOverride.withValue([home.appendingPathComponent("Applications")]) {
            try await GeneratedDataScanner(home: home).scan()
        }
    }
    func validate(_ item: CleanupItem) throws {
        try VerifiedGeneratedOwner.$applicationRootsOverride.withValue([home.appendingPathComponent("Applications")]) {
            try SafetyEngine(home: home).validate(item, activity: .init(tools: []))
        }
    }
}

@Suite("Verified early application cache batch") struct EarlyCacheTests {
    @Test func installedLayoutExposesOnlyCompleteSupportedUnits() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let report = try await f.scan()
        #expect(report.isComplete)
        #expect(Set(report.items.map { $0.url.lastPathComponent }) == ["Cache", "GPUCache", "CachedData", "logs"])
        #expect(report.items.count == 4)
        #expect(report.items.first { $0.url.lastPathComponent == "logs" }?.safety == .review)
        for item in report.items { try f.validate(item) }
        let plan = try CleanupPlan(items: report.items, source: .generatedData)
        #expect(plan.logicalBytes == report.generatedAccounting.bytes(for: report.items))
        #expect(plan.logicalBytes == 28)
        #expect(GeneratedDataGroup.groups(for: report.items).count == 2)
        #expect(GeneratedDataGroup.groups(for: report.items).allSatisfy { $0.appName == "Visual Studio Code" })
    }

    @Test(arguments: ["missing", "identifier", "version", "product", "commit", "metadata link"])
    func unsupportedOwnersDoNotGrantCleanupAuthority(_ mismatch: String) async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.populate()
        if mismatch != "missing" {
            try f.install(version: mismatch == "version" ? "2.0.0" : nil,
                bundleID: mismatch == "identifier" ? "org.example.other" : nil,
                productName: mismatch == "product" ? "Code - Insiders" : nil)
        }
        if mismatch == "commit" {
            try f.file("Applications/Visual Studio Code.app/Contents/Resources/app/product.json", data: Data("{}".utf8))
        }
        if mismatch == "metadata link" {
            let plist = f.bundle.appendingPathComponent("Contents/Info.plist")
            try FileManager.default.moveItem(at: plist, to: plist.appendingPathExtension("saved"))
            try FileManager.default.createSymbolicLink(at: plist, withDestinationURL: plist.appendingPathExtension("saved"))
        }
        let report = try await f.scan()
        #expect(report.items.isEmpty)
        #expect(!report.isComplete)
        #expect(report.coverage.filter { $0.ruleID.hasPrefix("app.vscode.") }.allSatisfy { $0.state == .skipped })
        let rule = try #require(Rules.generated.first { $0.id == "app.vscode.bytecode" })
        let forged = try Filesystem.item(f.data.appendingPathComponent("CachedData"), category: rule.category,
            safety: rule.safety, explanation: "forged", consequence: "forged", rule: rule.id, owner: rule.owner)
        #expect(throws: (any Error).self) { try f.validate(forged) }
    }

    @Test(arguments: ["missing", "empty", "denied", "file"])
    func newRuleCoverageDistinguishesUnsupportedAndUnreadableLayouts(_ state: String) async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install()
        let cache = f.data.appendingPathComponent("Cache")
        if state == "file" { try f.file("Library/Application Support/Code/Cache") }
        else if state != "missing" { try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true) }
        if state == "denied" { try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cache.path) }
        defer { if state == "denied" { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path) } }
        let report = try await f.scan()
        let coverage = try #require(report.coverage.first { $0.ruleID == "app.vscode.http-cache" })
        let expected: CoverageState = state == "missing" ? .missing : state == "empty" ? .empty : state == "denied" ? .blocked : .skipped
        #expect(coverage.state == expected)
        #expect(coverage.bytes == 0)
        #expect(report.items.isEmpty)
        #expect(report.isComplete == (state == "missing" || state == "empty"))
    }

    @Test func changedCacheContentRequiresANewScan() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let item = try #require(try await f.scan().items.first { $0.url.lastPathComponent == "CachedData" })
        try f.file("Library/Application Support/Code/CachedData/changed")
        #expect(throws: (any Error).self) { try f.validate(item) }
    }

    @Test func ownersHelpersAndBackgroundProcessesBlockExecution() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let item = try #require(try await f.scan().items.first)
        for owner in ["com.microsoft.VSCode", "com.microsoft.VSCode.helper", "com.microsoft.VSCode.helper.GPU"] {
            #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, runningBundleIDs: [owner], activity: .init(tools: [])) }
        }
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: [.visualStudioCode])) }
        #expect(throws: (any Error).self) { try SafetyEngine(home: f.home).validate(item, activity: .init(tools: nil)) }
        #expect(CleanupActivity.classify("/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper") == [.visualStudioCode])
        #expect(CleanupActivity.classify("/tmp/CodeCache/file").isEmpty)
    }

    @Test func forgedParentsChildrenAndSensitiveSiblingsAreRejected() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let rule = try #require(Rules.generated.first { $0.id == "app.vscode.bytecode" })
        for path in ["Library/Application Support/Code", "Library/Application Support/Code/CachedData/entry", "Library/Application Support/Code/User", "Library/Containers/com.microsoft.VSCode/Data/Library/Caches", "Library/Group Containers/group.com.microsoft.VSCode/Cache"] {
            let forged = try Filesystem.item(f.home.appendingPathComponent(path), category: rule.category, safety: rule.safety, explanation: "forged", consequence: "forged", rule: rule.id, owner: rule.owner)
            #expect(throws: (any Error).self) { try f.validate(forged) }
        }
    }

    @Test func providerAncestorsAndLinkedLeavesStayUnavailable() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let parent = f.data.path
        try await FilesystemAccess.$restriction.withValue({ $0.path == parent ? .providerManaged : .local }) {
            let report = try await f.scan()
            #expect(report.items.isEmpty)
            #expect(report.coverage.contains { $0.accessCapability == .providerManaged })
        }
        let cache = f.data.appendingPathComponent("GPUCache")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: f.data.appendingPathComponent("User"))
        let report = try await f.scan()
        #expect(report.items.count == 3)
        #expect(report.coverage.contains { $0.ruleID == "app.vscode.gpu-cache" && $0.state == .skipped })
    }

    @Test func groupCategoryAndSelectedTotalsAgreeWithPlansForHardLinks() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let source = f.data.appendingPathComponent("CachedData/entry")
        let target = f.data.appendingPathComponent("logs/entry")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.linkItem(at: source, to: target)
        let report = try await f.scan()
        #expect(report.items.reduce(0) { $0 + $1.bytes } == 28)
        #expect(report.generatedAccounting.bytes(for: report.items) == 21)
        let groups = GeneratedDataGroup.groups(for: report.items)
        for subset in groups.map(\.items) + [report.items, Array(report.items.prefix(2))] {
            let plan = try CleanupPlan(items: subset, source: .generatedData)
            #expect(plan.logicalBytes == report.generatedAccounting.bytes(for: subset))
        }
    }

    @Test func ownerChangesAfterScanAreRevalidatedBeforeAnyMove() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let report = try await f.scan(), plan = try CleanupPlan(items: report.items, source: .generatedData)
        let trash = f.home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        await journal.setMutationCheckpoint { try f.install(version: "2.0.0") }
        await CleanupActivity.$collectionOverride.withValue(.init(tools: [])) {
            await #expect(throws: (any Error).self) { _ = try await journal.execute(plan, context: { .init() }) }
        }
        #expect(try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil).isEmpty)
        #expect(await journal.snapshot().unresolved.isEmpty)
    }

    @Test func fixtureCleanupAndRestoreLeaveAdjacentDataUntouched() async throws {
        let f = try EarlyCacheFixture(); defer { f.remove() }
        try f.install(); try f.populate()
        let report = try await f.scan(), plan = try CleanupPlan(items: report.items, source: .generatedData)
        let trash = f.home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = try CleanupJournal(home: f.home, trashMover: { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
        let records = try await CleanupActivity.$collectionOverride.withValue(.init(tools: [])) {
            try await journal.execute(plan, context: { .init() })
        }
        #expect(records.count == 4)
        #expect(try String(contentsOf: f.data.appendingPathComponent("Backups/unsaved"), encoding: .utf8) == "fixture")
        #expect(try String(contentsOf: f.data.appendingPathComponent("Service Worker/CacheStorage/offline"), encoding: .utf8) == "fixture")
        for record in records { try await journal.restore(record) }
        #expect(try await f.scan().items.count == 4)
    }
}
