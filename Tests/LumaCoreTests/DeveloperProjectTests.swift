import Foundation
import Testing
@testable import LumaCore

private struct ProjectFixture {
    let home: URL
    var root: URL { home.appendingPathComponent("Projects") }
    init() throws {
        home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/projects-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    }
    @discardableResult func file(_ path: String, _ text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func node(_ name: String = "Node") throws {
        try file("\(name)/package.json", "{\"name\":\"fixture\",\"workspaces\":[\"packages/*\"]}")
        try file("\(name)/package-lock.json", "lockfile")
        try file("\(name)/src/index.ts", "valuable source")
        try file("\(name)/node_modules/dependency/index.js", "locally modified dependency")
        try file("\(name)/node_modules/dependency/package.json", "{}")
    }
    func rust(_ name: String = "Rust") throws {
        try file("\(name)/Cargo.toml", "[package]\nname = \"fixture\"\nversion = \"1.0.0\"")
        try file("\(name)/src/main.rs", "fn main() {}")
        try file("\(name)/Cargo.lock", "lockfile")
        try file("\(name)/target/debug/fixture", "build product")
    }
    func swift() throws {
        try file("Swift/Package.swift", "// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"Fixture\")")
        try file("Swift/Sources/main.swift", "source")
        try file("Swift/.build/arm64-apple-macosx/debug/product", "build product")
        try file("Swift/.build/checkouts/Dependency/source.swift", "valuable dependency edit")
        try file("Swift/.build/repositories/repo/source", "repository")
        try file("Swift/.build/build.db", "build state kept")
    }
    func inventory(ignored: Set<String> = []) throws -> ProjectInventory { try DeveloperProjects.scan(root: root, ignoredPaths: ignored) }
    func plan(_ items: [CleanupItem]) throws -> CleanupPlan { try CleanupPlan(items: items, authorizedRoots: [root], source: .developerProjects) }
    func journal() throws -> CleanupJournal {
        let trash = home.appendingPathComponent(".Trash")
        return try CleanupJournal(home: home, trashMover: { source in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
private let idleProjectContext = CleanupExecutionContext(activity: CleanupActivity(tools: []))
private actor ProjectCounter {
    var count = 0
    func next() -> Int { count += 1; return count }
}

@Suite("Chosen developer projects") struct DeveloperProjectTests {
    @Test func supportedBreakdownsKeepSourceConfigurationAndUnknownData() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node(); try f.rust(); try f.swift()
        try f.file("Node/notes.txt", "valuable unknown data")
        let inventory = try f.inventory()
        #expect(inventory.projects.count == 3)
        #expect(inventory.report.items.count == 3)
        #expect(Set(inventory.report.items.map(\.ruleID)) == Set(ProjectRule.allCases.map(\.rawValue)))
        #expect(inventory.report.items.allSatisfy { $0.safety == .review && $0.projectEvidence != nil })
        let entries = inventory.projects.flatMap(\.entries)
        #expect(entries.contains { $0.url.lastPathComponent == "src" && $0.kind == .source && $0.item == nil })
        #expect(entries.contains { $0.url.lastPathComponent == "notes.txt" && $0.kind == .unknown && $0.item == nil })
        #expect(entries.contains { $0.url.lastPathComponent == "Cargo.lock" && $0.kind == .configuration && $0.item == nil })
        #expect(entries.contains { $0.url.lastPathComponent == "checkouts" && $0.kind == .excluded && $0.item == nil })
        #expect(inventory.report.items.allSatisfy { $0.consequence.contains("network") || $0.consequence.contains("Network") })
    }

    @Test func namesAloneInvalidManifestsAndCustomOutputsAreNotCandidates() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.file("Fake/node_modules/source", "valuable")
        try f.file("Fake/target/source", "valuable")
        try f.file("Invalid/package.json", "not JSON")
        try f.file("Invalid/Cargo.toml", "a = \"[package]\"")
        try f.file("Invalid/Package.swift", "arbitrary source")
        try f.rust()
        try f.file("Rust/custom-build/source", "valuable")
        let inventory = try f.inventory()
        #expect(inventory.projects.count == 1)
        #expect(inventory.report.items.count == 1)
        #expect(inventory.report.items.first?.url.lastPathComponent == "target")
        #expect(!inventory.report.notices.isEmpty)
    }

    @Test func nestedWorkspacesAreUniqueAndOutputTreesAreNotRediscovered() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node("Mono")
        try f.node("Mono/packages/A")
        try f.rust("Mono/packages/B")
        try f.file("Mono/node_modules/dependency/node_modules/nested/source")
        try f.file("Mono/vendor/Vendored/package.json", "{}")
        try f.file("Mono/vendor/Vendored/node_modules/dep/source")
        let inventory = try f.inventory()
        #expect(inventory.projects.count == 3)
        #expect(inventory.report.items.count == 3)
        #expect(Set(inventory.report.items.map(\.id)).count == 3)
        let plan = try f.plan(inventory.report.items)
        try plan.preflight(home: f.home, context: idleProjectContext)
        #expect(plan.logicalBytes == inventory.report.items.reduce(0) { $0 + $1.bytes })
        #expect(!inventory.report.items.contains { $0.url.path.contains("vendor") })
    }

    @Test func linkedDependenciesHardlinksAndSharedStoresAreExcluded() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node("Linked"); try f.node("Hardlinked"); try f.node("Pnpm")
        let outside = try f.file("Outside/source", "valuable external content")
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Linked/node_modules/dependency/link"), withDestinationURL: outside)
        try FileManager.default.linkItem(at: outside, to: f.root.appendingPathComponent("Hardlinked/node_modules/dependency/shared"))
        try f.file("Pnpm/node_modules/.pnpm/store/file")
        #expect(try f.inventory().report.items.isEmpty)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "valuable external content")
    }

    @Test func sensitiveAndVendoredContentsPreventWholeFolderCleanup() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.rust("Database"); try f.rust("Secrets"); try f.rust("Vendored"); try f.rust("Source")
        try f.file("Database/target/debug/local.sqlite", "valuable database")
        try f.file("Secrets/target/.env.local", "credential fixture")
        try f.file("Vendored/target/vendor/source.rs", "source")
        try f.file("Source/target/debug/copied-source.rs", "valuable source")
        #expect(try f.inventory().report.items.isEmpty)
    }

    @Test func ignoredRootsAndDescendantsBlockScanAndMutation() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node()
        let initial = try f.inventory()
        let project = f.root.appendingPathComponent("Node")
        #expect(try f.inventory(ignored: [project.path]).projects.isEmpty)
        let descendant = project.appendingPathComponent("node_modules/dependency/index.js")
        #expect(try f.inventory(ignored: [descendant.path]).report.items.isEmpty)
        let context = CleanupExecutionContext(ignoredPaths: [descendant.path], activity: CleanupActivity(tools: []))
        #expect(throws: (any Error).self) { try f.plan(initial.report.items).preflight(home: f.home, context: context) }
    }

    @Test func forgedRulesEvidenceScopeAndClassificationReject() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.rust()
        let item = try #require(f.inventory().report.items.first)
        let engine = SafetyEngine(home: f.home)
        #expect(throws: (any Error).self) { try engine.validate(item, activity: CleanupActivity(tools: [])) }
        var missing = item; missing.projectEvidence = nil
        #expect(throws: (any Error).self) { try f.plan([missing]) }
        let source = try f.file("Rust/src/secret.rs")
        let inspected = try Filesystem.inspect(source)
        let forged = CleanupItem(url: source, bytes: inspected.0, category: .developer, safety: .review, explanation: "", consequence: "", ruleID: item.ruleID, ownerBundleID: nil, identity: inspected.1, scannedAt: Date(), projectEvidence: item.projectEvidence)
        #expect(throws: (any Error).self) { try engine.validate(forged, authorizedRoots: [f.root], activity: CleanupActivity(tools: [])) }
    }

    @Test func sameSizeManifestEditsAndConcurrentOutputChangesReject() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node(); try f.rust()
        let inventory = try f.inventory()
        let plan = try f.plan(inventory.report.items)
        let manifest = f.root.appendingPathComponent("Node/package.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: manifest.path)
        let text = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "fixture", with: "changed")
        try Data(text.utf8).write(to: manifest)
        try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate]!], ofItemAtPath: manifest.path)
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: idleProjectContext) }
        let fresh = try f.plan(f.inventory().report.items)
        try f.file("Rust/target/debug/new-file", "concurrent build")
        #expect(throws: (any Error).self) { try fresh.preflight(home: f.home, context: idleProjectContext) }
    }

    @Test func activeAndUnknownToolsBlockEntirePlanAndRecheckBeforeNextMove() async throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node(); try f.rust()
        for tools: Set<CleanupTool>? in [nil, [.projectBuild], [.packageManager], [.xcode]] {
            let plan = try f.plan(f.inventory().report.items)
            let context = CleanupExecutionContext(activity: CleanupActivity(tools: tools))
            await #expect(throws: (any Error).self) { try await f.journal().execute(plan, context: { context }) }
            #expect(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        }
        let plan = try f.plan(f.inventory().report.items)
        let counter = ProjectCounter()
        let journal = try f.journal()
        await #expect(throws: (any Error).self) {
            try await journal.execute(plan, context: {
                let count = await counter.next()
                return count < 3 ? idleProjectContext : CleanupExecutionContext(activity: CleanupActivity(tools: [.projectBuild]))
            })
        }
        #expect(await journal.snapshot().records.count == 1)
        #expect(FileManager.default.fileExists(atPath: plan.items[1].url.path))
    }

    @Test func trashActivityAndRestoreKeepSourceLockfilesAndLocalEdits() async throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.node(); try f.rust(); try f.swift()
        let items = try f.inventory().report.items
        let plan = try f.plan(items)
        let journal = try f.journal()
        let records = try await journal.execute(plan, context: { idleProjectContext })
        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.planSource == .developerProjects })
        for path in ["Node/src/index.ts", "Node/package-lock.json", "Rust/Cargo.lock", "Swift/Sources/main.swift", "Swift/.build/checkouts/Dependency/source.swift"] {
            #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent(path).path))
        }
        let restarted = try f.journal()
        for record in records { try await restarted.restore(record) }
        #expect(try String(contentsOf: f.root.appendingPathComponent("Node/node_modules/dependency/index.js"), encoding: .utf8) == "locally modified dependency")
        #expect(await restarted.snapshot().records.allSatisfy(\.restored))
    }

    @Test func cargoWorkspaceAndMemberOutputsHaveSeparateBounds() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.file("Workspace/Cargo.toml", "[workspace]\nmembers = [\"member\"]")
        try f.file("Workspace/target/debug/workspace", "build")
        try f.rust("Workspace/member")
        let items = try f.inventory().report.items
        #expect(items.count == 2)
        try f.plan(items).preflight(home: f.home, context: idleProjectContext)
    }

    @Test func providerChangesAndReplacedProjectParentsRejectReviewedEvidence() throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.rust()
        let plan = try f.plan(f.inventory().report.items)
        let target = f.root.appendingPathComponent("Rust/target")
        try FilesystemAccess.$restriction.withValue({ url in Filesystem.isWithin(url, root: target) ? .providerManaged : .local }) { () throws -> Void in
            let inventory = try f.inventory()
            #expect(inventory.report.items.isEmpty)
            #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: idleProjectContext) }
        }
        try FileManager.default.moveItem(at: f.root.appendingPathComponent("Rust"), to: f.root.appendingPathComponent("Moved"))
        try f.rust()
        #expect(throws: (any Error).self) { try plan.preflight(home: f.home, context: idleProjectContext) }
    }

    @Test func changesAtFinalMutationCheckpointPreventTheMove() async throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.rust()
        let plan = try f.plan(f.inventory().report.items)
        let journal = try f.journal()
        let concurrent = plan.items[0].url.appendingPathComponent("concurrent-build-file")
        await journal.setMutationCheckpoint { try Data("new build".utf8).write(to: concurrent) }
        await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { idleProjectContext }) }
        #expect(await journal.snapshot().records.isEmpty)
        #expect(await journal.snapshot().unresolved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: plan.items[0].url.path))
    }

    @Test func processClassifierCoversBuildsRuntimesAndPackageManagers() {
        for name in ["cargo", "rustc", "rust-analyzer", "node", "swift", "swiftc", "clang", "make", "bun", "deno"] {
            #expect(CleanupActivity.classify("/usr/local/bin/\(name)").contains(.projectBuild))
        }
        #expect(CleanupActivity.classify("node /usr/local/lib/node_modules/npm/bin/npm-cli.js").contains(.packageManager))
    }

    @Test func scanEngineReturnsCompletedProjectInventoryAndCancellationStops() async throws {
        let f = try ProjectFixture(); defer { f.remove() }
        try f.rust()
        let result = try await ScanEngine.run(.init(.developerProjects, root: f.root))
        #expect(result.projectInventory?.projects.count == 1)
        #expect(result.report.items.count == 1)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try DeveloperProjects.scan(root: f.root) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
