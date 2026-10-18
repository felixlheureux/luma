import Foundation
import CryptoKit
import Darwin

/// Versioned, deliberately narrow project rules. Custom output paths and shared
/// stores are never discovered from environment variables or executed manifests.
public enum ProjectRule: String, Codable, Sendable, CaseIterable {
    case node = "project.v1.node.dependencies"
    case rust = "project.v1.rust.build"
    case swift = "project.v1.swift.build"
    public var title: String {
        switch self { case .node: "Node dependencies"; case .rust: "Rust build output"; case .swift: "Swift build output" }
    }
    var manifest: String {
        switch self { case .node: "package.json"; case .rust: "Cargo.toml"; case .swift: "Package.swift" }
    }
    public var consequence: String {
        switch self {
        case .node: "Reinstall with your project's package manager (for example npm install). Network access and install scripts may be required. Local dependency edits and unavailable packages may not be recoverable by reinstalling. Restore from Activity before reinstalling if needed."
        case .rust: "A subsequent cargo build recompiles this project. Downloads may require network access. Custom files in target are not guaranteed to be reproducible; inspect them first."
        case .swift: "A subsequent swift build recompiles these products. Resolving dependencies may require network access. Checkouts and repositories are kept; custom build files may not be reproducible."
        }
    }
    func matches(_ url: URL, project: URL) -> Bool {
        switch self {
        case .node: Filesystem.samePath(url, project.exactAppendingPathComponent("node_modules"))
        case .rust: Filesystem.samePath(url, project.exactAppendingPathComponent("target"))
        case .swift:
            Filesystem.samePath(url.exactDeletingLastPathComponent(), project.exactAppendingPathComponent(".build"))
                && url.lastPathComponent.range(of: "^(arm64|x86_64)-apple-macosx$", options: .regularExpression) != nil
        }
    }
}

public struct ProjectEvidence: Codable, Sendable, Equatable {
    public let project: URL
    public let location: FileLocation
    public let manifestIdentity: FileIdentity
    public let manifestDigest: String
}

public enum ProjectDataKind: String, Sendable {
    case source = "Source", configuration = "Manifests & configuration"
    case build = "Build output", dependencies = "Dependencies", unknown = "Other data", excluded = "Excluded"
}

public struct ProjectEntry: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let kind: ProjectDataKind
    public let bytes: Int64?
    public let item: CleanupItem?
    public let detail: String
}

public struct DeveloperProject: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let ecosystems: [ProjectRule]
    public let entries: [ProjectEntry]
    public var items: [CleanupItem] { entries.compactMap(\.item) }
}

public struct ProjectInventory: Sendable {
    public var projects: [DeveloperProject] = []
    public var report = ScanReport()
    public init() {}
}

public enum DeveloperProjects {
    private static let discoveryExclusions: Set<String> = ["node_modules", "target", ".build", ".git", "vendor", "Vendor", "Pods", "Carthage", ".swiftpm", ".cargo", ".npm", ".pnpm-store", ".yarn", ".venv", "venv", "Library", ".Trash"]
    private static let sourceNames: Set<String> = ["src", "Sources", "Tests", "tests", "test", "include"]
    private static let sensitiveNames: Set<String> = [".git", "vendor", "Vendor", ".env", ".ssh", ".aws", ".pnpm", ".pnpm-store", ".yarn", "credentials", "secrets", ".npmrc", ".netrc", ".git-credentials", "id_rsa", "id_ed25519", ".kube", ".azure"]
    private static let sensitiveExtensions: Set<String> = ["db", "db-wal", "db-shm", "realm", "mdb", "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm", "pem", "key", "p12", "pfx", "keychain", "keychain-db", "qcow2", "utm", "sparseimage", "sparsebundle", "vhd", "vhdx", "ova", "ovf", "vmdk", "vdi", "vmwarevm", "pvm"]

    private static func ignored(_ url: URL, paths: Set<String>) -> Bool {
        paths.contains { Filesystem.isWithin(url, root: URL(fileURLWithPath: $0)) }
    }

    /// Reads at most 1 MiB; never evaluates Package.swift, Cargo config or scripts.
    private static func manifest(_ rule: ProjectRule, project: URL) throws -> (FileIdentity, String) {
        let url = project.exactAppendingPathComponent(rule.manifest)
        return try NonMaterializingIO.perform {
            let pinned = try PinnedPath(url)
            guard pinned.value.st_mode & S_IFMT == S_IFREG, pinned.value.st_uid == getuid(),
                  pinned.value.st_size <= 1_048_576 else { throw LumaError.rejected("Unsupported project manifest.") }
            let before = try Filesystem.inspect(url).1
            let handle = FileHandle(fileDescriptor: try pinned.openReadableRegularFile(), closeOnDealloc: true)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 1_048_577) ?? Data()
            guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else { throw LumaError.rejected("Unsupported project manifest encoding or size.") }
            let valid: Bool
            switch rule {
            case .node:
                let object = try JSONSerialization.jsonObject(with: data)
                valid = object is [String: Any]
            case .rust:
                // Recognize only literal package/workspace table headers. Full
                // TOML interpretation, inherited/custom targets are out of scope.
                valid = !text.contains("\"\"\"") && !text.contains("'''") && text.split(separator: "\n").contains {
                    let line = $0.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
                    return line == "[package]" || line == "[workspace]"
                }
            case .swift:
                valid = text.hasPrefix("// swift-tools-version:") && text.contains("import PackageDescription") && text.range(of: "\\bPackage\\s*\\(", options: .regularExpression) != nil
            }
            try pinned.revalidate(expected: before.location)
            guard valid, try Filesystem.inspect(url).1 == before else { throw LumaError.rejected("Project manifest is unsupported or changed during inspection.") }
            return (before, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
    }

    /// Reject linked/shared content and recognizable sensitive data anywhere in
    /// a candidate, including otherwise internal links. No partial tree moves.
    private static func inspectCandidate(_ url: URL, rule: ProjectRule, ignoredPaths: Set<String>) throws -> (Int64, FileIdentity) {
        var remaining = 100_000
        func check(_ path: URL, depth: Int) throws {
            try Task.checkCancellation()
            remaining -= 1
            guard remaining >= 0, depth < 128, !ignored(path, paths: ignoredPaths) else { throw LumaError.rejected("Ignored data or the project inspection limit prevents reviewing this entire folder.") }
            let pinned = try PinnedPath(path)
            let name = path.lastPathComponent
            guard pinned.value.st_uid == getuid(), !sensitiveNames.contains(name), !name.hasPrefix(".env."),
                  !sensitiveExtensions.contains(path.pathExtension.lowercased()),
                  pinned.value.st_mode & S_IFMT != S_IFREG || pinned.value.st_nlink == 1 else {
                throw LumaError.rejected("Sensitive, vendored or shared data is kept. Review this location in Finder.")
            }
            if rule != .node {
                guard !sourceNames.contains(name), !["Cargo.toml", "Package.swift", "package.json", "Cargo.lock", "Package.resolved", "package-lock.json", "pnpm-lock.yaml", "yarn.lock"].contains(name),
                      !["rs", "swift", "c", "h", "cpp", "hpp", "js", "ts", "jsx", "tsx"].contains(path.pathExtension.lowercased()) else {
                    throw LumaError.rejected("Source or project configuration inside build output is kept. Inspect it in Finder.")
                }
            }
            if pinned.value.st_mode & S_IFMT == S_IFDIR {
                for child in try PinnedPath.names(in: pinned.descriptor, limit: max(0, remaining)) { try check(path.exactAppendingPathComponent(child), depth: depth + 1) }
            }
            try pinned.revalidate()
        }
        try check(url, depth: 0)
        return try Filesystem.inspect(url, limit: 100_000)
    }

    public static func validate(_ item: CleanupItem, authorizedRoots: [URL], ignoredPaths: Set<String>, home: URL, activity: CleanupActivity?) throws {
        guard let rule = ProjectRule(rawValue: item.ruleID), let proof = item.projectEvidence,
              item.safety == .review, item.category == .developer, item.ownerBundleID == nil,
              rule.matches(item.url, project: proof.project),
              SafetyEngine(home: home, ignoredPaths: ignoredPaths).permitsManualSelection(at: item.url, authorizedRoots: authorizedRoots),
              authorizedRoots.contains(where: { Filesystem.isWithin(proof.project, root: $0) }),
              !ignored(proof.project, paths: ignoredPaths) else { throw LumaError.rejected("Choose and scan this project again before reviewing its generated data.") }
        let relativeComponents = proof.project.pathComponents.dropFirst(home.pathComponents.count)
        guard relativeComponents.allSatisfy({ !discoveryExclusions.contains($0) }) else {
            throw LumaError.rejected("Projects inside generated, vendored or shared stores are protected.")
        }
        let project = try PinnedPath(proof.project)
        try project.revalidate(expected: proof.location)
        let current = try manifest(rule, project: proof.project)
        guard current.0 == proof.manifestIdentity, current.0.location == proof.manifestIdentity.location,
              current.1 == proof.manifestDigest else { throw LumaError.rejected("The project manifest changed. Scan again.") }
        let tools = (activity ?? CleanupActivity.collect()).tools
        guard let tools, tools.isDisjoint(with: [.packageManager, .xcode, .projectBuild]) else {
            throw LumaError.rejected("Stop active builds, runtimes and package managers before cleaning project data. Tool activity must be available.")
        }
        _ = try inspectCandidate(item.url, rule: rule, ignoredPaths: ignoredPaths)
    }

    public static func scan(root: URL, ignoredPaths: Set<String> = [], emit: @escaping ScanEmitter = { _ in }) throws -> ProjectInventory {
        let start = Date()
        let pinned = try PinnedPath(root)
        guard !discoveryExclusions.contains(root.lastPathComponent) else { throw LumaError.rejected("Choose a project or workspace rather than an output, vendored or shared-store folder.") }
        guard pinned.value.st_mode & S_IFMT == S_IFDIR, pinned.value.st_uid == getuid() else { throw LumaError.rejected("Choose a project folder owned by your user.") }
        var result = ProjectInventory()
        var visited = 0
        var examined = 0
        func notice(_ url: URL, _ detail: String) {
            let message = "\(url.path): \(detail)"
            result.report.notices.append(message); result.report.isComplete = false; emit(.notice(message))
        }
        func walk(_ folder: URL, depth: Int) throws {
            try Task.checkCancellation()
            guard !ignored(folder, paths: ignoredPaths) else { notice(folder, "Ignored project or folder."); return }
            visited += 1
            guard visited <= 10_000 else { throw LumaError.rejected("Project discovery limit reached. Choose a narrower folder.") }
            let directory = try PinnedPath(folder)
            guard directory.value.st_mode & S_IFMT == S_IFDIR, directory.value.st_uid == getuid(), directory.value.st_dev == pinned.value.st_dev else { throw LumaError.rejected("Project discovery stays in owned folders on one volume.") }
            let names = try PinnedPath.names(in: directory.descriptor, limit: 10_000)
            guard names.count <= 10_000 else { throw LumaError.rejected("Too many project entries. Choose a narrower folder.") }
            examined += names.count
            guard examined <= 20_000 else { notice(folder, "Discovery entry limit reached. Choose a narrower folder."); return }
            var evidence: [ProjectRule: ProjectEvidence] = [:]
            for rule in ProjectRule.allCases where names.contains(rule.manifest) {
                do {
                    let value = try manifest(rule, project: folder)
                    evidence[rule] = ProjectEvidence(project: folder, location: directory.location, manifestIdentity: value.0, manifestDigest: value.1)
                } catch is CancellationError { throw CancellationError() }
                catch { notice(folder.exactAppendingPathComponent(rule.manifest), error.localizedDescription) }
            }
            var entries: [ProjectEntry] = []
            func entry(_ url: URL, rule: ProjectRule?) throws {
                let name = url.lastPathComponent
                let kind: ProjectDataKind = rule.map { $0 == .node ? .dependencies : .build }
                    ?? (sourceNames.contains(name) || ["swift", "rs", "js", "ts", "tsx", "jsx", "c", "h"].contains(url.pathExtension) ? .source
                        : (["package.json", "Cargo.toml", "Package.swift", "Cargo.lock", "Package.resolved", "package-lock.json", "yarn.lock", "pnpm-lock.yaml"].contains(name) ? .configuration : .unknown))
                if ignored(url, paths: ignoredPaths) || ignoredPaths.contains(where: { Filesystem.isWithin(URL(fileURLWithPath: $0), root: url) }) { entries.append(.init(url: url, kind: .excluded, bytes: nil, item: nil, detail: "Ignored; no cleanup available.")); return }
                do {
                    let inspected: (Int64, FileIdentity)
                    if let rule { inspected = try inspectCandidate(url, rule: rule, ignoredPaths: ignoredPaths) }
                    else { inspected = try Filesystem.inspect(url, limit: 20_000) }
                    var item: CleanupItem?
                    if let rule, let proof = evidence[rule], inspected.0 > 0 {
                        let path = try PinnedPath(url)
                        guard path.value.st_mode & S_IFMT == S_IFDIR else { throw LumaError.rejected("Expected a local directory.") }
                        let candidate = CleanupItem(url: url, bytes: inspected.0, category: .developer, safety: .review,
                            explanation: "\(rule.title) in \(folder.lastPathComponent). Location and manifest indicate a conventional project folder; they do not prove every file can be recreated. Inspect local changes before selecting.",
                            consequence: rule.consequence, ruleID: rule.rawValue, ownerBundleID: nil, identity: inspected.1, scannedAt: Date(), projectEvidence: proof)
                        item = candidate; result.report.items.append(candidate); emit(.item(candidate))
                    }
                    entries.append(.init(url: url, kind: kind, bytes: inspected.0, item: item, detail: rule?.consequence ?? "Kept. No project cleanup rule applies to this data."))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    entries.append(.init(url: url, kind: .excluded, bytes: nil, item: nil, detail: error.localizedDescription))
                    notice(url, error.localizedDescription)
                }
            }
            if !evidence.isEmpty {
                for name in names.sorted() {
                    let url = folder.exactAppendingPathComponent(name)
                    if name == ".build", evidence[.swift] != nil {
                        if ignored(url, paths: ignoredPaths) {
                            entries.append(.init(url: url, kind: .excluded, bytes: nil, item: nil, detail: "Ignored; no inspection or cleanup.")); continue
                        }
                        do {
                            let build = try PinnedPath(url)
                            for child in try PinnedPath.names(in: build.descriptor).sorted() {
                                let childURL = url.exactAppendingPathComponent(child)
                                if ["checkouts", "repositories", "artifacts"].contains(child) {
                                    entries.append(.init(url: childURL, kind: .excluded, bytes: nil, item: nil, detail: "Kept: dependency source or downloaded artifacts.")); continue
                                }
                                try entry(childURL, rule: ProjectRule.swift.matches(childURL, project: folder) ? .swift : nil)
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch { notice(url, error.localizedDescription) }
                    } else {
                        let rule = ProjectRule.allCases.first { evidence[$0] != nil && $0.matches(url, project: folder) }
                        // Retain excluded metadata/stores without inspecting their contents.
                        if discoveryExclusions.contains(name), rule == nil {
                            entries.append(.init(url: url, kind: .excluded, bytes: nil, item: nil, detail: "Kept: version control, vendored data or an unsupported store."))
                        } else { try entry(url, rule: rule) }
                    }
                }
                result.projects.append(.init(url: folder, ecosystems: ProjectRule.allCases.filter { evidence[$0] != nil }, entries: entries))
            }
            emit(.progress(.init("Inspecting chosen projects", current: folder.path, entries: visited, bytes: result.report.items.reduce(0) { $0 + $1.bytes })))
            for name in names.sorted() where !name.hasPrefix(".") && !discoveryExclusions.contains(name) {
                if examined >= 20_000 || visited >= 10_000 { break }
                let child = folder.exactAppendingPathComponent(name)
                do {
                    let node = try PinnedPath(child)
                    guard node.value.st_mode & S_IFMT == S_IFDIR, child.pathExtension.isEmpty else { continue }
                    if depth < 6 { try walk(child, depth: depth + 1) }
                    else { notice(child, "Discovery stops after six levels. Choose this folder directly to inspect deeper projects.") }
                } catch is CancellationError { throw CancellationError() }
                catch { notice(child, error.localizedDescription) }
            }
            try directory.revalidate()
        }
        try walk(root, depth: 0)
        try pinned.revalidate()
        result.report.visited = visited; result.report.duration = Date().timeIntervalSince(start)
        result.projects.sort { $0.url.path < $1.url.path }
        return result
    }
}
