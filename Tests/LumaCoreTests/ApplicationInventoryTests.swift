import Foundation
import Testing
import Darwin
@testable import LumaCore

@Suite("Application inventory corrections") struct ApplicationInventoryTests {
    private func fixture() throws -> URL {
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/inventory-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
    private func app(_ path: String, id: String, name: String, home: URL) throws -> ApplicationRecord {
        let url = home.appendingPathComponent("Applications/" + path)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleDisplayName": name], format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        return try ApplicationScanner.restoredRecord(at: url)
    }

    @Test func boundedVendorScopeAndCompanionsRemainInOwnershipOnly() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let product = try app("Vendor/Product.app", id: "org.fixture.product", name: "Product", home: home)
        let companion = try app("Vendor/Uninstall Product.app", id: "org.fixture.product.uninstaller", name: "Uninstall Product", home: home)
        let utility = try app("Uninstall Utility.app", id: "org.utility", name: "Uninstall Utility", home: home)
        _ = try app("Vendor/Product.app/Contents/Library/LoginItems/Helper.app", id: "org.fixture.helper", name: "Helper", home: home)
        _ = try app("Too/Deep/Inside/Hidden.app", id: "org.deep", name: "Hidden", home: home)
        let inventory = try ApplicationScanner.inventory(home: home, roots: [home.appendingPathComponent("Applications")])
        #expect(Set(inventory.applications.map(\.id)) == [product.id, utility.id])
        #expect(ApplicationInventory.contains(product.url, home: home))
        let owners = try ApplicationPresence.bundleIdentifiers(home: home, roots: [home.appendingPathComponent("Applications")])
        #expect(owners.contains(companion.bundleID))
        #expect(owners.contains("org.fixture.helper"))
        #expect(owners.contains("org.deep"))
    }

    @Test func twoComponentBundleAndSelectedHelperEvidenceAreIndependentOfUnrelatedTrees() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let chosen = try app("Vendor/Product.app", id: "org.product", name: "Product", home: home)
        let unrelated = try app("Other.app", id: "org.other.product", name: "Other", home: home)
        let denied = unrelated.url.appendingPathComponent("Contents/Library/LoginItems")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        let partial = try FilesystemAccess.$restriction.withValue({ Filesystem.isWithin($0, root: unrelated.url) ? .unknown : .local }) {
            try ApplicationScanner.inventory(home: home, roots: [home.appendingPathComponent("Applications")])
        }
        #expect(partial.applications.map(\.id) == [chosen.id])
        #expect(!partial.report.isComplete)
        try await FilesystemAccess.$restriction.withValue({ Filesystem.isWithin($0, root: denied) ? .unknown : .local }) {
            let plan = try ApplicationUninstall.prepare(chosen, home: home)
            #expect(plan.items.count == 1)
            #expect(!plan.retainedApplicationData.isEmpty)
            #expect(throws: (any Error).self) { try ApplicationPresence.bundleIdentifiers(home: home, roots: [home.appendingPathComponent("Applications")]) }
            try plan.preflight(home: home, context: .init(runningBundleIDs: ["org.unrelated.running"], processPaths: []))
            let trash = home.appendingPathComponent(".Trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let journal = try CleanupJournal(home: home, trashMover: { source in
                let destination = trash.appendingPathComponent("Product.app")
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            })
            _ = try await journal.execute(plan, context: { .init(runningBundleIDs: ["org.unrelated.running"], processPaths: []) })
            try await journal.undo(journal.reviewUndo(sessionID: plan.id))
            #expect(FileManager.default.fileExists(atPath: chosen.url.path))
        }
        let helper = try app("Vendor/Product.app/Contents/Library/LoginItems/Helper.app", id: "org.different.helper", name: "Helper", home: home)
        let plan = try ApplicationUninstall.prepare(chosen, home: home)
        #expect(throws: (any Error).self) { try plan.preflight(home: home, context: .init(runningBundleIDs: [helper.bundleID], processPaths: [])) }
        #expect(throws: (any Error).self) {
            try FilesystemAccess.$restriction.withValue({ Filesystem.isWithin($0, root: helper.url) ? .unknown : .local }) {
                try plan.preflight(home: home, context: .init(processPaths: []))
            }
        }
    }

    @Test func matchingEmbeddedOwnerUnderDifferentAppIsStillPresent() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        _ = try app("Other.app", id: "org.other", name: "Other", home: home)
        _ = try app("Other.app/Contents/Library/LoginItems/Owner.app", id: "org.chosen", name: "Owner", home: home)
        #expect(try ApplicationPresence.bundleIdentifiers(home: home, roots: [home.appendingPathComponent("Applications")], matchingOwner: "org.chosen").contains("org.chosen"))
        for id in ["com.apple", "com.apple.fixture", "app.luma.mac", "app.luma.mac.helper", "group.fixture", "bad/path"] { #expect(!ApplicationUninstall.supportsBundle(id)) }
        #expect(ApplicationUninstall.supportsBundle("org.chosen"))
    }

    @Test func ordinaryNativeTrashCapabilityReportsImmutableBundle() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let chosen = try app("Vendor/Product.app", id: "org.product", name: "Product", home: home)
        try ApplicationUninstall.validateTrashRights(chosen.url)
        #expect(chflags(chosen.url.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { _ = chflags(chosen.url.path, 0) }
        do {
            try ApplicationUninstall.validateTrashRights(chosen.url)
            Issue.record("An immutable application must not offer ordinary Trash.")
        } catch { #expect(error.localizedDescription.contains("ordinary Trash rights")) }
    }

    @Test func metadataMergesKeepOnlySameInstallationIcon() {
        let url = URL(fileURLWithPath: "/Applications/Fixture.app")
        let old = ApplicationRecord(url: url, name: "Fixture", bundleID: "org.fixture", version: "1", bytes: 1, iconPNG: Data([1, 2]))
        let metadata = ApplicationRecord(url: url, name: "Fixture", bundleID: "org.fixture", version: "2", bytes: 2)
        #expect(metadata.preservingIcon(from: old).iconPNG == old.iconPNG)
        let replacement = ApplicationRecord(url: url, name: "Replacement", bundleID: "org.other", version: "1", bytes: 3)
        #expect(replacement.preservingIcon(from: old).iconPNG == nil)
    }
}
