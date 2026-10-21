import Foundation
internal import Yams

public struct RuleCatalogError: Error, LocalizedError, Sendable {
    public let detail: String
    public var errorDescription: String? { "Cleanup catalog: " + detail }
    init(_ detail: String) { self.detail = detail }
}

/// Only the loader can construct a catalog. Parsing never publishes a partial set.
public struct RuleCatalog: Sendable {
    public let version: String
    public let locale: String
    public let generated: [CleanupRule]
    public let ownership: [KnownLeftoverPath]
    fileprivate init(version: String, locale: String, generated: [CleanupRule], ownership: [KnownLeftoverPath]) {
        self.version = version; self.locale = locale; self.generated = generated; self.ownership = ownership
    }
}

/// Local, reviewable YAML only. No includes, remote sources, aliases or path expansion.
/// Yams values stay in this file; consumers receive project-owned immutable values.
public enum RuleLoader {
    public static func load(from url: URL) throws -> RuleCatalog {
        do { return try load(data: Filesystem.readMetadata(url, limit: 1_048_576)) }
        catch let error as RuleCatalogError { throw error }
        catch { throw RuleCatalogError("Cannot read \(url.lastPathComponent): \(error.localizedDescription)") }
    }

    public static func bundled() throws -> RuleCatalog {
        // Resolve the same package bundle locations as SwiftPM, but report a missing
        // resource instead of trapping in its generated Bundle.module accessor.
        let codeBundle = Bundle(for: CatalogBundleMarker.self)
        let roots: [URL?]
        if Bundle.main.bundleURL.pathExtension == "app" {
            // A distributed app must use its own signed resource directory.
            roots = [Bundle.main.resourceURL]
        } else {
            // SwiftPM/XCTest can place resources beside the test bundle rather
            // than inside its Contents/Resources directory on older toolchains.
            roots = [Bundle.main.resourceURL, codeBundle.resourceURL, Bundle.main.bundleURL,
                     codeBundle.bundleURL.deletingLastPathComponent()]
        }
        guard let bundle = roots.compactMap({ $0?.appendingPathComponent("Luma_LumaCore.bundle") }).compactMap({ Bundle(url: $0) }).first,
              let url = bundle.url(forResource: "CleanupRules", withExtension: "yaml") else {
            throw RuleCatalogError("Bundled CleanupRules.yaml is missing. Rebuild or reinstall Luma.")
        }
        return try load(from: url)
    }

    public static func load(data: Data) throws -> RuleCatalog {
        guard data.count <= 1_048_576, let yaml = String(data: data, encoding: .utf8) else {
            throw RuleCatalogError("Expected UTF-8 YAML of at most 1 MiB.")
        }
        do {
            guard let documentNode = try compose(yaml: yaml, .default, .default, .utf8),
                  case .mapping = documentNode else { throw RuleCatalogError("Expected exactly one YAML mapping document.") }
            let object = try plainValue(documentNode, path: [], depth: 0)
            let document = try JSONDecoder().decode(Document.self, from: JSONSerialization.data(withJSONObject: object))
            return try validate(document)
        } catch let error as RuleCatalogError { throw error }
        catch let error as YamlError { throw RuleCatalogError(yamlDiagnostic(error)) }
        catch { throw RuleCatalogError("Invalid schema: \(error)") }
    }

    private static func yamlDiagnostic(_ error: YamlError) -> String {
        switch error {
        case .scanner(_, let problem, let mark, _), .parser(_, let problem, let mark, _), .composer(_, let problem, let mark, _):
            return "YAML line \(mark.line), column \(mark.column): \(problem.prefix(200))"
        case .duplicatedKeysInMapping(let duplicates, let context):
            return "Duplicate YAML keys near line \(context.mark.line): \(duplicates.prefix(5).map { String($0.prefix(80)) }.joined(separator: ", "))"
        case .reader(let problem, _, _, _): return "YAML encoding: " + problem.prefix(200)
        default: return "Invalid or unsupported YAML. Check syntax, tags and document structure."
        }
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let catalogVersion: String
        let locale: String
        let generated: [RuleRecord]
        let ownership: [OwnershipRecord]
    }
    private struct RuleRecord: Decodable {
        let id: String
        let relativePath: String
        let category: String
        let safety: String
        let name: String
        let explanation: String
        let consequence: String
        let owner: String?
        let profileLeaves: [String]
        let chromiumProfiles: Bool
        let tools: [CleanupTool]
        let appName: String?
        let requiredApplication: GeneratedOwnerRequirement?
        let regeneration: String
        let provenance: [String]
        let reviewedOn: String
    }
    private struct OwnershipRecord: Decodable {
        let cliNames: [String]?
        let otherOwners: [String]?
        let relativePath: String
        let owner: String
        let classification: String
        let explanation: String
        let consequence: String
        let provenance: [String]
        let reviewedOn: String
    }

    private static let rootKeys: Set<String> = ["schemaVersion", "catalogVersion", "locale", "generated", "ownership"]
    private static let ruleKeys: Set<String> = ["id", "relativePath", "category", "safety", "name", "explanation", "consequence", "owner", "profileLeaves", "chromiumProfiles", "tools", "appName", "requiredApplication", "regeneration", "provenance", "reviewedOn"]
    private static let ownershipKeys: Set<String> = ["cliNames", "otherOwners", "relativePath", "owner", "classification", "explanation", "consequence", "provenance", "reviewedOn"]
    private static let applicationKeys: Set<String> = ["bundleName", "bundleID", "productName", "version", "commit"]

    /// Validate duplicate/unknown keys and YAML features before constructing Swift values.
    /// Limits apply before any alias expansion (aliases/anchors are always rejected).
    private static func plainValue(_ node: Node, path: [String], depth: Int) throws -> Any {
        guard depth < 12, node.anchor == nil else { throw RuleCatalogError("\(path.joined(separator: ".")): nesting/anchors are unsupported.") }
        switch node {
        case .mapping(let mapping):
            guard node.tag == Tag(.map) else { throw RuleCatalogError("Custom YAML mapping tags are unsupported.") }
            let allowed: Set<String>
            if path.isEmpty { allowed = rootKeys }
            else if path.count == 2 && path[0] == "generated" { allowed = ruleKeys }
            else if path.count == 2 && path[0] == "ownership" { allowed = ownershipKeys }
            else if path.count == 3 && path.last == "requiredApplication" { allowed = applicationKeys }
            else { throw RuleCatalogError("Unexpected mapping at \(path.joined(separator: ".")).") }
            var result: [String: Any] = [:]
            for (key, value) in mapping {
                guard case .scalar = key, key.anchor == nil, key.tag == Tag(.str), let name = key.string, allowed.contains(name) else {
                    throw RuleCatalogError("\(path.joined(separator: ".")): unsupported field '\(key.string ?? "non-string key")'.")
                }
                guard result[name] == nil else { throw RuleCatalogError("\((path + [name]).joined(separator: ".")): duplicate field.") }
                result[name] = try plainValue(value, path: path + [name], depth: depth + 1)
            }
            return result
        case .sequence(let sequence):
            guard node.tag == Tag(.seq), sequence.count <= 1_000 else { throw RuleCatalogError("Sequence is too large or has an unsupported tag.") }
            return try sequence.enumerated().map { try plainValue($0.element, path: path + [String($0.offset)], depth: depth + 1) }
        case .scalar:
            if node.tag == Tag(.str), let value = node.string { return value }
            if node.tag == Tag(.null) { return NSNull() }
            if node.tag == Tag(.bool), let value = node.bool { return value }
            if node.tag == Tag(.int), let value = node.int { return value }
            throw RuleCatalogError("\(path.joined(separator: ".")): unsupported scalar/tag; quote dates and version strings.")
        case .alias: throw RuleCatalogError("YAML aliases are unsupported.")
        }
    }

    private static func validate(_ document: Document) throws -> RuleCatalog {
        guard document.schemaVersion == 1 else { throw RuleCatalogError("Unsupported schemaVersion \(document.schemaVersion); expected 1.") }
        guard document.locale == "en" else { throw RuleCatalogError("Schema 1 supports explicit English display text (locale: en).") }
        try text(document.catalogVersion, field: "catalogVersion")
        guard !document.generated.isEmpty, document.generated.count <= 500, document.ownership.count <= 500 else {
            throw RuleCatalogError("Expected 1–500 generated rules and at most 500 ownership mappings.")
        }
        var ids: Set<String> = []
        var paths: Set<String> = []
        var rules: [CleanupRule] = []
        for record in document.generated {
            let context = record.id
            guard record.id.range(of: "^[a-z][a-z0-9-]*(\\.[a-z0-9-]+)+$", options: .regularExpression) != nil,
                  !record.id.hasPrefix("application."), !record.id.hasPrefix("manual."), !record.id.hasPrefix("duplicates."),
                  ids.insert(record.id).inserted else { throw RuleCatalogError("\(context): invalid, reserved or duplicate id.") }
            try path(record.relativePath, field: context)
            guard paths.insert(record.relativePath.lowercased()).inserted else { throw RuleCatalogError("\(context): duplicate generated path.") }
            let categories: [String: ItemCategory] = ["caches": .caches, "logs": .logs, "developer": .developer]
            guard let category = categories[record.category], let safety = ["safe": SafetyLevel.safe, "review": .review][record.safety] else {
                throw RuleCatalogError("\(context): unsupported generated category/safety.")
            }
            for (field, value) in [("name", record.name), ("explanation", record.explanation), ("consequence", record.consequence), ("regeneration", record.regeneration)] {
                try text(value, field: "\(context).\(field)")
            }
            try evidence(record.provenance, reviewedOn: record.reviewedOn, field: context)
            if let owner = record.owner { try identifier(owner, field: context, allowApple: true) }
            if let appName = record.appName { try text(appName, field: context + ".appName") }
            guard Set(record.tools).count == record.tools.count else { throw RuleCatalogError("\(context): duplicate tool guard.") }
            try generatedBoundary(record)
            rules.append(CleanupRule(id: record.id, relativePath: record.relativePath, category: category,
                explanation: record.explanation, consequence: record.consequence, owner: record.owner, name: record.name,
                profileLeaves: record.profileLeaves, chromiumProfiles: record.chromiumProfiles, safety: safety,
                tools: Set(record.tools), appName: record.appName, requiredApplication: record.requiredApplication,
                regeneration: record.regeneration, provenance: record.provenance, reviewedOn: record.reviewedOn))
        }
        var ownership: [KnownLeftoverPath] = []
        for record in document.ownership {
            try path(record.relativePath, field: "ownership")
            try identifier(record.owner, field: record.relativePath, allowApple: false)
            guard record.classification == "review", (["Library/Application Support/", "Library/Caches/", "Library/Logs/", "Library/Preferences/", "Library/Saved Application State/"].contains(where: { record.relativePath.hasPrefix($0) }) || HiddenAppData.permitsMapping(record.relativePath)) else {
                throw RuleCatalogError("\(record.relativePath): ownership requires a bounded app-data path classified review.")
            }
            if record.relativePath.hasPrefix(".") && (record.cliNames?.isEmpty != false) {
                throw RuleCatalogError("Hidden ownership requires explicit CLI guards.")
            }
            for name in record.cliNames ?? [] {
                guard name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$", options: .regularExpression) != nil else { throw RuleCatalogError("Invalid CLI guard.") }
            }
            for owner in record.otherOwners ?? [] { try identifier(owner, field: record.relativePath, allowApple: false) }
            try text(record.explanation, field: record.relativePath + ".explanation")
            try text(record.consequence, field: record.relativePath + ".consequence")
            try evidence(record.provenance, reviewedOn: record.reviewedOn, field: record.relativePath)
            guard !ownership.contains(where: { $0.relativePath.lowercased() == record.relativePath.lowercased() }) else {
                throw RuleCatalogError("Duplicate ownership path: \(record.relativePath).")
            }
            ownership.append(.init(relativePath: record.relativePath, owner: record.owner, explanation: record.explanation, consequence: record.consequence, cliNames: record.cliNames ?? [], otherOwners: record.otherOwners ?? []))
        }
        let derived = rules.compactMap { rule -> KnownLeftoverPath? in
            guard let owner = rule.owner else { return nil }
            return .init(relativePath: rule.relativePath, owner: owner)
        }
        let allMappings = ownership + derived
        for mapping in allMappings {
            guard !allMappings.contains(where: { other in
                other.owner.lowercased() != mapping.owner.lowercased() && overlaps(mapping.relativePath, other.relativePath)
            }) else { throw RuleCatalogError("Conflicting or overlapping ownership at \(mapping.relativePath).") }
        }
        for (index, rule) in rules.enumerated() {
            guard !rules.dropFirst(index + 1).contains(where: { overlaps(rule.relativePath, $0.relativePath) }) else {
                throw RuleCatalogError("Overlapping generated roots at \(rule.relativePath).")
            }
        }
        return RuleCatalog(version: document.catalogVersion, locale: document.locale, generated: rules, ownership: ownership)
    }

    private static func generatedBoundary(_ rule: RuleRecord) throws {
        let p = rule.relativePath
        let ordinary = p.hasPrefix("Library/Caches/") || p.hasPrefix("Library/Logs/")
        let developer = ["Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator/Caches", ".npm/_cacache", ".npm/_npx", ".npm/_logs"].contains(p)
        let vscode = p.hasPrefix("Library/Application Support/Code/")
        guard ordinary || developer || vscode else { throw RuleCatalogError("\(rule.id): path is outside supported generated-data scopes.") }
        let sharedRoots = ["Library/Caches/Google", "Library/Caches/BraveSoftware", "Library/Caches/Firefox", "Library/Caches/zen", "Library/Caches/Yarn", "Library/Caches/pnpm", "Library/Logs/DiagnosticReports"]
        guard !sharedRoots.contains(p) else { throw RuleCatalogError("\(rule.id): shared or diagnostic root is protected.") }
        if rule.category == "caches", rule.owner == nil { throw RuleCatalogError("\(rule.id): app caches require an exact owner.") }
        let profileScopes = ["Library/Caches/Firefox/Profiles": false, "Library/Caches/zen/Profiles": false,
                             "Library/Caches/BraveSoftware/Brave-Browser": true, "Library/Caches/Microsoft Edge": true]
        for (root, chromium) in profileScopes {
            if p == root {
                guard rule.chromiumProfiles == chromium, !rule.profileLeaves.isEmpty else {
                    throw RuleCatalogError("\(rule.id): a supported browser profile root requires its audited cache leaves.")
                }
            } else if p.hasPrefix(root + "/") {
                throw RuleCatalogError("\(rule.id): use the audited profile cache-leaf rule rather than a direct profile target.")
            }
        }
        if rule.chromiumProfiles || !rule.profileLeaves.isEmpty {
            let leaves = rule.chromiumProfiles ? ["Cache", "Code Cache", "GPUCache"] : ["cache2", "startupCache"]
            guard p.hasPrefix("Library/Caches/"), Set(rule.profileLeaves) == Set(leaves), rule.profileLeaves.count == leaves.count, rule.owner != nil else {
                throw RuleCatalogError("\(rule.id): unsupported profile cache leaves or owner.")
            }
        }
        let minimum: Set<CleanupTool>
        if p.hasPrefix(".npm/") || p.hasPrefix("Library/Caches/Yarn/") || p.hasPrefix("Library/Caches/pnpm/") || (p == "Library/Caches/Homebrew" || p.hasPrefix("Library/Caches/Homebrew/")) { minimum = [.packageManager] }
        else if p.contains("CoreSimulator") { minimum = [.simulator, .xcode] }
        else if p == "Library/Developer/Xcode/DerivedData" || (p == "Library/Caches/org.swift.swiftpm" || p.hasPrefix("Library/Caches/org.swift.swiftpm/")) { minimum = [.xcode] }
        else if vscode { minimum = [.visualStudioCode] }
        else { minimum = [] }
        guard Set(rule.tools).isSuperset(of: minimum) else { throw RuleCatalogError("\(rule.id): missing required tool guards \(minimum.map(\.rawValue).sorted()).") }
        if p == "Library/Developer/CoreSimulator/Caches", rule.safety != "review" { throw RuleCatalogError("Simulator caches must remain review first.") }
        if vscode {
            guard let app = rule.requiredApplication, app.bundleName == "Visual Studio Code.app", app.bundleID == "com.microsoft.VSCode", rule.owner == app.bundleID,
                  app.productName == "Code", ["Cache", "GPUCache", "CachedData", "logs"].contains(String(p.dropFirst("Library/Application Support/Code/".count))),
                  app.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
                  app.commit.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
                  (!p.hasSuffix("/logs") || rule.safety == "review") else { throw RuleCatalogError("\(rule.id): unsupported verified-product layout or classification.") }
        } else if rule.requiredApplication != nil { throw RuleCatalogError("\(rule.id): unsupported product verifier.") }
    }

    private static func path(_ value: String, field: String) throws {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard value.utf8.count <= 1_024, (parts.count >= 2 || (field == "ownership" && HiddenAppData.permitsMapping(value))), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !value.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true || "~$%\\*?[]{}<>:".contains($0) }) else {
            throw RuleCatalogError("\(field): expected an exact home-relative path, without traversal, tokens or globs.")
        }
    }
    private static func identifier(_ value: String, field: String, allowApple: Bool) throws {
        let lower = value.lowercased()
        guard value.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$", options: .regularExpression) != nil,
              !lower.hasPrefix("group."), lower != "app.luma.mac", !lower.hasPrefix("app.luma.mac."),
              allowApple || !lower.hasPrefix("com.apple.") else { throw RuleCatalogError("\(field): unsupported or protected owner identifier.") }
    }
    private static func text(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 8_192, !value.contains("\0") else { throw RuleCatalogError("\(field): missing or oversized text.") }
    }
    private static func evidence(_ sources: [String], reviewedOn: String, field: String) throws {
        guard !sources.isEmpty, sources.count <= 20, reviewedOn.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            throw RuleCatalogError("\(field): provenance and YYYY-MM-DD reviewedOn are required.")
        }
        for source in sources { try text(source, field: field + ".provenance") }
    }
    private static func overlaps(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
}

private final class CatalogBundleMarker {}
