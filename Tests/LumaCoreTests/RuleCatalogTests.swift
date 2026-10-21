import Foundation
import Testing
@testable import LumaCore

private struct LegacyCatalog: Decodable {
    let generated: [LegacyRule]
    let ownership: [LegacyOwnership]
}
private struct LegacyOwnership: Decodable { let relativePath: String; let owner: String }
private struct LegacyRule: Decodable {
    let id: String
    let relativePath: String
    let category: String
    let explanation: String
    let consequence: String
    let owner: String?
    let name: String
    let profileLeaves: [String]
    let chromiumProfiles: Bool
    let safety: String
    let tools: [CleanupTool]
    let appName: String?
    let requiredApplication: GeneratedOwnerRequirement?
}

@Suite("Validated cleanup catalog") struct RuleCatalogTests {
    private func object() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "RulesBaseline", withExtension: "json"))
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var generated = baseline["generated"] as! [[String: Any]]
        for i in generated.indices {
            generated[i]["regeneration"] = "Rebuilt by the owning app; previous diagnostics require Restore."
            generated[i]["provenance"] = ["Disposable fixture; not production path authority."]
            generated[i]["reviewedOn"] = "2026-10-18"
            let id = generated[i]["id"] as! String
            if ["developer.xcode.derived-data", "developer.swiftpm.cache"].contains(id) { generated[i]["tools"] = ["xcode"] }
            if id == "developer.homebrew.cache" { generated[i]["tools"] = ["packageManager"] }
        }
        var ownership = baseline["ownership"] as! [[String: Any]]
        for i in ownership.indices {
            ownership[i]["classification"] = "review"
            ownership[i]["explanation"] = "Fixture explicit owner"
            ownership[i]["consequence"] = "May contain documents"
            ownership[i]["provenance"] = ["Fixture"]
            ownership[i]["reviewedOn"] = "2026-10-18"
        }
        return ["schemaVersion": 1, "catalogVersion": "fixture.1", "locale": "en", "generated": generated, "ownership": ownership]
    }
    private func load(_ object: [String: Any]) throws -> RuleCatalog {
        // JSON is a YAML subset, exercising the same production parser and validator.
        try RuleLoader.load(data: JSONSerialization.data(withJSONObject: object))
    }

    @Test func migrationPreservesEveryLegacyDecisionFieldAndMapping() throws {
        let url = try #require(Bundle.module.url(forResource: "RulesBaseline", withExtension: "json"))
        let baseline = try JSONDecoder().decode(LegacyCatalog.self, from: Data(contentsOf: url))
        let catalog = try Rules.catalog()
        #expect(catalog.generated.count == 22)
        #expect(catalog.generated.map(\.id) == baseline.generated.map(\.id))
        for (rule, old) in zip(catalog.generated, baseline.generated) {
            #expect(rule.relativePath == old.relativePath)
            #expect(rule.category == ["caches": ItemCategory.caches, "logs": .logs, "developer": .developer][old.category])
            #expect(rule.safety == ["safe": SafetyLevel.safe, "review": .review][old.safety])
            #expect(rule.explanation == old.explanation)
            #expect(rule.consequence == old.consequence)
            #expect(rule.owner == old.owner)
            #expect(rule.title == old.name)
            #expect(rule.profileLeaves == old.profileLeaves)
            #expect(rule.chromiumProfiles == old.chromiumProfiles)
            #expect(rule.appName == old.appName)
            #expect(rule.requiredApplication == old.requiredApplication)
            var effectiveTools = Set(old.tools)
            if old.id == "developer.homebrew.cache" { effectiveTools.insert(.packageManager) }
            if old.id.hasPrefix("developer.xcode.") || old.id == "developer.swiftpm.cache" { effectiveTools.insert(.xcode) }
            #expect(rule.tools == effectiveTools)
            #expect(!rule.provenance.isEmpty && !rule.regeneration.isEmpty)
        }
        #expect(catalog.ownership.prefix(baseline.ownership.count).map(\.relativePath) == baseline.ownership.map(\.relativePath))
        #expect(catalog.ownership.prefix(baseline.ownership.count).map(\.owner) == baseline.ownership.map(\.owner))
    }

    @Test func everyMigratedRuleFindsOnlyItsLegacyUnits() async throws {
        let baselineURL = try #require(Bundle.module.url(forResource: "RulesBaseline", withExtension: "json"))
        let old = try JSONDecoder().decode(LegacyCatalog.self, from: Data(contentsOf: baselineURL))
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/equivalence-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        func write(_ path: String, _ data: Data = Data("fixture".utf8)) throws {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        var expected: Set<String> = []
        for rule in old.generated {
            let units = rule.profileLeaves.isEmpty ? [rule.relativePath] : rule.profileLeaves.map {
                rule.relativePath + "/" + (rule.chromiumProfiles ? "Default" : "abcdefgh.default") + "/" + $0
            }
            for unit in units { try write(unit + "/entry"); expected.insert(unit) }
            if !rule.profileLeaves.isEmpty {
                try write(rule.relativePath + "/" + (rule.chromiumProfiles ? "Default" : "abcdefgh.default") + "/Sessions/important")
            }
        }
        let requirement = try #require(old.generated.last?.requiredApplication)
        let app = "Applications/Visual Studio Code.app/Contents/"
        try write(app + "Info.plist", PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": requirement.bundleID, "CFBundleShortVersionString": requirement.version], format: .xml, options: 0))
        try write(app + "Resources/app/product.json", JSONSerialization.data(withJSONObject: ["darwinBundleIdentifier": requirement.bundleID, "nameShort": requirement.productName, "commit": requirement.commit]))
        try write(app + "Resources/app/package.json", JSONSerialization.data(withJSONObject: ["version": requirement.version]))
        for path in ["Documents/important", "Library/Application Support/Code/User/settings.json", "Library/Application Support/Code/Backups/document", "Library/Developer/CoreSimulator/Devices/device/Documents/personal", "Library/pnpm/store/package", "Projects/test/node_modules/code"] { try write(path) }
        let report = try await VerifiedGeneratedOwner.$applicationRootsOverride.withValue([home.appendingPathComponent("Applications")]) {
            try await GeneratedDataScanner(home: home).scan()
        }
        #expect(report.isComplete)
        #expect(Set(report.items.map { String($0.url.path.dropFirst(home.path.count + 1)) }) == expected)
        #expect(Set(report.items.map(\.ruleID)) == Set(old.generated.map(\.id)))
        #expect(report.items.count == expected.count)
    }

    @Test func schemaNegativeFixturesRejectTheWholeCatalog() throws {
        let base = try object()
        let changes: [(String, Any)] = [("schemaVersion", 99), ("locale", "xx"), ("catalogVersion", ""), ("extra", true), ("generated", [] as [String])]
        for (key, value) in changes {
            var fixture = base; fixture[key] = value
            #expect(throws: RuleCatalogError.self) { try load(fixture) }
        }
        let invalidFields: [(String, Any)] = [
            ("id", "manual.folder-review"), ("relativePath", "/System/Library"), ("relativePath", "Library/Caches/../Documents"),
            ("relativePath", "Library/Caches//cache"), ("relativePath", "Library/Caches/*"), ("relativePath", "~/Library/Caches/cache"),
            ("relativePath", "Library/Caches/${HOME}"), ("relativePath", "Documents/project"), ("relativePath", "Library/Containers/com.example.app"),
            ("relativePath", "Library/Caches/Google"), ("relativePath", "Library/CloudStorage/provider"),
            ("category", "related"), ("safety", "userData"), ("explanation", "  "), ("consequence", ""), ("name", ""),
            ("regeneration", ""), ("provenance", [] as [String]), ("reviewedOn", "yesterday"),
            ("tools", [] as [String]), ("owner", "group.shared"), ("unknownField", true),
            ("profileLeaves", ["Sessions"]), ("tools", ["forceTerminate"])
        ]
        for (key, value) in invalidFields {
            for index in [6, 7, 8, 9] {
            var fixture = base; var rules = fixture["generated"] as! [[String: Any]]
            rules[index]["profileLeaves"] = [] as [String]; rules[index]["chromiumProfiles"] = false
            fixture["generated"] = rules
            #expect(throws: RuleCatalogError.self) { try load(fixture) }
        }
        for path in ["Library/Caches/Homebrew/part", "Library/Caches/org.swift.swiftpm/part", "Library/Caches/Firefox/Profiles/abcdefgh.default/Sessions"] {
            var fixture = base; var onlyRule = (fixture["generated"] as! [[String: Any]])[0]
            onlyRule["relativePath"] = path; onlyRule["tools"] = [] as [String]
            fixture["generated"] = [onlyRule]; fixture["ownership"] = [] as [String]
            #expect(throws: RuleCatalogError.self) { try load(fixture) }
        }
        var fixture = base; var rules = fixture["generated"] as! [[String: Any]]
            rules[0][key] = value; fixture["generated"] = rules
            #expect(throws: RuleCatalogError.self) { try load(fixture) }
        }
        var fixture = base; var rules = fixture["generated"] as! [[String: Any]]
        rules.append(rules[0]); fixture["generated"] = rules
        #expect(throws: RuleCatalogError.self) { try load(fixture) }
        rules[rules.count - 1]["id"] = "fixture.duplicate-path"; fixture["generated"] = rules
        #expect(throws: RuleCatalogError.self) { try load(fixture) }
        rules.removeLast(); rules[1]["relativePath"] = "Library/Developer/Xcode/DerivedData/child"; fixture["generated"] = rules
        #expect(throws: RuleCatalogError.self) { try load(fixture) }
    }

    @Test func ambiguousAndProtectedOwnershipCannotActivate() throws {
        for (path, owner, classification) in [
            ("Library/Application Support/Code/Cache", "com.example.other", "review"),
            ("Library/Application Support/Code", "com.example.other", "review"),
            ("Library/Application Support/Spotify", "com.spotify.client", "review"),
            ("Library/Application Support/Other", "com.apple.finder", "review"),
            ("Library/Application Support/Other", "com.example.other", "safe"),
            ("Documents/Other", "com.example.other", "review")
        ] {
            var fixture = try object(); var mappings = fixture["ownership"] as! [[String: Any]]
            var added = mappings[0]; added["relativePath"] = path; added["owner"] = owner; added["classification"] = classification
            mappings.append(added); fixture["ownership"] = mappings
            #expect(throws: RuleCatalogError.self) { try load(fixture) }
        }
    }

    @Test func ownershipReviewUsesCatalogTextAndRetainsUserDataCategory() throws {
        let catalog = try load(object())
        try Rules.$catalogOverride.withValue(.success(catalog)) {
            let home = URL(fileURLWithPath: "/Users/fixture")
            let relationship = try #require(ApplicationRelationships.candidates(owner: "com.spotify.client", home: home).first {
                $0.url.path == home.appendingPathComponent("Library/Application Support/Spotify").path
            })
            #expect(relationship.category == .userData)
            #expect(relationship.evidence == "Fixture explicit owner")
            #expect(relationship.consequence == "May contain documents")
        }
        for mapping in try Rules.catalog().ownership.filter({ !$0.relativePath.hasPrefix(".") }) {
            #expect(mapping.explanation == "Explicit ownership mapping: \(mapping.relativePath) → \(mapping.owner).")
            #expect(mapping.consequence == "May contain documents, offline content, extensions or sessions. Ownership does not make this data disposable.")
        }
    }

    @Test func unsupportedYAMLFeaturesHaveActionableFailures() throws {
        for yaml in ["hello", "true", "null", "[]", "schemaVersion: 1\nschemaVersion: 2", "schemaVersion: 1\n---\nschemaVersion: 1", "schemaVersion: &version 1", "schemaVersion: *missing", "schemaVersion: !custom 1", "[", "", "schemaVersion: 1\ngenerated: !!binary abcd"] {
            do {
                _ = try RuleLoader.load(data: Data(yaml.utf8))
                Issue.record("Accepted invalid YAML fixture")
            } catch let error as RuleCatalogError { #expect(error.localizedDescription.hasPrefix("Cleanup catalog:")); #expect(error.localizedDescription.count < 1_024) }
        }
        let valid = try JSONSerialization.data(withJSONObject: object())
        let trailing = valid + Data("\n---\n[".utf8)
        #expect(throws: RuleCatalogError.self) { try RuleLoader.load(data: trailing) }
        #expect(throws: RuleCatalogError.self) { try RuleLoader.load(data: Data(repeating: 32, count: 1_048_577)) }
        #expect(throws: RuleCatalogError.self) { try RuleLoader.load(data: Data([0xff])) }
    }

    @Test func contributorRuleUsesUnchangedScannerAndRuntimeSafety() async throws {
        var fixture = try object()
        var rules = fixture["generated"] as! [[String: Any]]
        var addition = rules[2]
        addition["id"] = "app.fixture.cache"; addition["relativePath"] = "Library/Caches/com.example.fixture"
        addition["owner"] = "com.example.fixture"; addition["name"] = "Fixture cache"
        rules.append(addition); fixture["generated"] = rules
        let catalog = try load(fixture)
        let home = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Fixtures/catalog-\(UUID())")
        let cache = home.appendingPathComponent("Library/Caches/com.example.fixture")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("data")
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: home) }
        try await Rules.$catalogOverride.withValue(.success(catalog)) {
            let report = try await GeneratedDataScanner(home: home).scan()
            let item = try #require(report.items.first { $0.ruleID == "app.fixture.cache" })
            try SafetyEngine(home: home).validate(item)
            #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(item, runningBundleIDs: ["com.example.fixture.helper"]) }
            #expect(throws: (any Error).self) { try SafetyEngine(home: home, ignoredPaths: [cache.path]).validate(item) }
            let spoofed = try Filesystem.item(cache, category: .caches, safety: .safe, explanation: "forged", consequence: "forged", rule: item.ruleID, owner: "com.example.other")
            #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(spoofed) }
            let personal = home.appendingPathComponent("Documents/personal")
            try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
            let forged = try Filesystem.item(personal, category: .caches, safety: .safe, explanation: "forged", consequence: "forged", rule: item.ruleID, owner: item.ownerBundleID)
            #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(forged) }
            let plan = try CleanupPlan(items: [item])
            try Data("changed".utf8).write(to: file)
            #expect(throws: (any Error).self) { try SafetyEngine(home: home).validate(item) }
            try await Rules.$catalogOverride.withValue(.failure(RuleCatalogError("fixture invalid catalog"))) {
                await #expect(throws: RuleCatalogError.self) { try await GeneratedDataScanner(home: home).scan() }
                #expect(ApplicationRelationships.candidates(owner: "com.example.fixture", home: home).isEmpty)
                #expect(throws: RuleCatalogError.self) { try SafetyEngine(home: home).validate(item) }
                #expect(throws: RuleCatalogError.self) { try plan.preflight(home: home, context: .init()) }
            }
        }
    }
}
