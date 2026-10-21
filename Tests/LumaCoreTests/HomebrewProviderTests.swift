import Foundation
import Testing
@testable import LumaCore

struct BrewFixture {
    let root: URL
    let executable: URL
    init(script: String = "exit 0") throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/brew-\(UUID())")
        executable = root.appendingPathComponent("bin/brew")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(("#!/bin/bash\n" + script + "\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func installApp() throws -> ApplicationRecord {
        let app = root.appendingPathComponent("Applications/Renamed.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.lumatest.brew"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let version = root.appendingPathComponent("Caskroom/exact-cask/1")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: version.appendingPathComponent("Original.app"), withDestinationURL: app)
        return ApplicationRecord(url: app, name: "Renamed", bundleID: "org.lumatest.brew", version: "1", bytes: 0)
    }
}

@Suite("Read-only Homebrew inventory") struct HomebrewProviderTests {
    static let json = #"{"formulae":[{"full_name":"app","installed":[{"installed_on_request":true}]},{"full_name":"lib","installed":[{"installed_on_request":false}]},{"full_name":"orphan-lib","installed":[{"installed_on_request":false}]},{"full_name":"git","installed":[{"installed_on_request":true}]}],"casks":[{"token":"font-fixture","installed":"1"}]}"#
    @Test func dependencyAndUsageStatesAreDistinct() throws {
        let result = try HomebrewProvider.decode(Self.json)
        #expect(result.manualPackages.contains("git (formula)"))
        #expect(result.manualPackages.contains("font-fixture (cask; installation intent unknown)"))
        #expect(try HomebrewProvider.parseAutoremove("==> Would autoremove 1 unneeded formula:\norphan-lib\n", formulae: result.formulae, manual: result.manualPackages) == ["orphan-lib"])
        #expect(throws: (any Error).self) { try HomebrewProvider.parseAutoremove("Would autoremove 1 unneeded formula:\ngit\n", formulae: result.formulae, manual: result.manualPackages) }
        #expect(throws: (any Error).self) { try HomebrewProvider.parseAutoremove("orphan-lib", formulae: result.formulae, manual: result.manualPackages) }
        #expect(throws: (any Error).self) { try HomebrewProvider.parseAutoremove("Would autoremove 2 unneeded formulae:\norphan-lib\n", formulae: result.formulae, manual: result.manualPackages) }
        #expect(throws: (any Error).self) { try HomebrewProvider.decode("{\"formulae\":[],\"casks\":[{}]}") }
        #expect(throws: (any Error).self) { try HomebrewProvider.decode("invalid JSON") }
        #expect(throws: (any Error).self) { try HomebrewProvider.decode(Self.json.replacingOccurrences(of: "true", with: "1")) }
    }
    @Test func cleanupOutputIsObservationOnlyAndStrict() throws {
        let output = "Would remove: /test/Cellar/old/1 (3 files, 2MB)\nWould remove (broken link): /test/bin/old\n==> This operation would free approximately 2MB of disk space.\n"
        #expect(try HomebrewProvider.parseCleanup(output).count == 2)
        #expect(try HomebrewProvider.parseCleanup("").isEmpty)
        #expect(throws: (any Error).self) { try HomebrewProvider.parseCleanup("Removing /test/old") }
    }
    @Test func processUsesOnlyFixedDryRunsAndPreservesPartialFailure() throws {
        let f = try BrewFixture(script: """
        case "$*" in
          --prefix) /usr/bin/dirname "$(/usr/bin/dirname "$0")" ;;
          'info --json=v2 --installed') /bin/cat "$(/usr/bin/dirname "$0")/inventory.json" ;;
          'autoremove --dry-run') /usr/bin/printf '==> Would autoremove 1 unneeded formula:\\norphan-lib\\n' ;;
          'cleanup --dry-run') /usr/bin/printf 'active service; cannot inspect\\n' >&2; exit 7 ;;
          *) exit 99 ;;
        esac
        """)
        defer { f.remove() }
        try Data(Self.json.utf8).write(to: f.executable.deletingLastPathComponent().appendingPathComponent("inventory.json"))
        let result = try HomebrewProvider(executables: [f.executable]).inventory()
        #expect(result.unneededDependencies == ["orphan-lib"])
        #expect(result.cleanupSuggestions == nil)
        #expect(result.issues.contains { $0.contains("exit 7") && $0.contains("active service") })
        #expect(result.manualPackages.contains("git (formula)"))
    }
    @Test func missingBrokenDeniedTimeoutAndOutputLimit() throws {
        let missing = try HomebrewProvider(executables: [URL(fileURLWithPath: "/luma-missing/bin/brew")]).inventory()
        #expect(!missing.issues.isEmpty && missing.unneededDependencies == nil)
        let denied = try BrewFixture(); defer { denied.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.executable.path)
        #expect(throws: (any Error).self) { try HomebrewProvider(executables: [denied.executable]).installation() }
        let broken = try BrewFixture(script: "exit 42"); defer { broken.remove() }
        #expect(throws: (any Error).self) { try HomebrewProvider(executables: [broken.executable]).inventory() }
        let slow = try BrewFixture(script: "exec /bin/sleep 10"); defer { slow.remove() }
        let start = Date()
        #expect(throws: (any Error).self) { try HomebrewProvider(timeout: 0.1).query(.prefix, executable: slow.executable) }
        #expect(Date().timeIntervalSince(start) < 2)
        let huge = try BrewFixture(script: "exec /usr/bin/yes overflow"); defer { huge.remove() }
        #expect(throws: (any Error).self) { try HomebrewProvider(timeout: 5).query(.inventory, executable: huge.executable) }
    }
    @Test func cancellationKillsTheQuery() async throws {
        let f = try BrewFixture(script: "exec /bin/sleep 10"); defer { f.remove() }
        let worker = Task.detached { try HomebrewProvider().query(.prefix, executable: f.executable) }
        try await Task.sleep(for: .milliseconds(50)); worker.cancel()
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
    @Test func exactInstalledLinkBlocksNativeTrashAndRechecksChanges() throws {
        let f = try BrewFixture(); defer { f.remove() }
        let app = try f.installApp()
        try HomebrewProvider.$fixtureExecutables.withValue([f.executable]) {
            #expect(try HomebrewProvider.nativeUninstallBlock(app.url)?.contains("exact-cask") == true)
            #expect(try HomebrewProvider.nativeUninstallBlock(f.root.appendingPathComponent("Other/Renamed.app")) == nil)
            #expect(throws: (any Error).self) { try ApplicationUninstall.prepare(app, home: f.root) }
            #expect(throws: (any Error).self) { try ApplicationUninstall.validateTrashRights(app.url) }
            let link = f.root.appendingPathComponent("Caskroom/exact-cask/1/Original.app")
            try FileManager.default.removeItem(at: link)
            #expect(try HomebrewProvider.nativeUninstallBlock(app.url) == nil)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app.url)
            #expect(throws: (any Error).self) { try ApplicationUninstall.validateTrashRights(app.url) }
        }
    }
    @Test func caskInstalledAfterPlanPreventsEveryMove() async throws {
        let f = try BrewFixture(); defer { f.remove() }
        let app = try f.installApp()
        let link = f.root.appendingPathComponent("Caskroom/exact-cask/1/Original.app")
        try FileManager.default.removeItem(at: link)
        try await HomebrewProvider.$fixtureExecutables.withValue([f.executable]) {
            try await ApplicationUninstall.$fixtureInstallationRoots.withValue([f.root.appendingPathComponent("Applications")]) {
                try await ApplicationUninstall.$fixtureRegisteredURLs.withValue([]) {
                    let plan = try ApplicationUninstall.prepare(app, home: f.root)
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app.url)
                    let journal = try CleanupJournal(home: f.root, trashMover: { _ in throw LumaError.rejected("Mover must not be reached") })
                    await #expect(throws: (any Error).self) { try await journal.execute(plan, context: { CleanupExecutionContext(processPaths: []) }) }
                    #expect(await journal.snapshot().records.isEmpty)
                    #expect(await journal.snapshot().sessions.first?.detail?.contains("Homebrew") == true)
                    #expect(FileManager.default.fileExists(atPath: app.url.path))
                }
            }
        }
    }

}
