import Foundation
import Darwin

public enum HiddenOwnerState: String, Codable, Sendable {
    case absent = "Verified absent owner · potential leftover"
    case present = "Owner installed or shared · keep"
    case unknown = "Unknown owner · inspect only"
}

/// Display observations are separate from exact-owner executable residue items.
public struct HiddenAppDataObservation: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let owner: String?
    public let state: HiddenOwnerState
    public let bytes: Int64?
    public let detail: String
}

public enum HiddenAppData {
    private static let protected: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".kube", ".git", ".docker", ".azure", ".trash",
        ".config", ".cache", ".local", ".luma", ".codex", ".agents", ".npm", ".yarn", ".pnpm",
        ".gitconfig", ".git-credentials", ".netrc", ".npmrc", ".pypirc",
        ".bashrc", ".bash_profile", ".profile", ".zshrc", ".zshenv", ".zprofile"
    ]
    /// Catalog authors may name a directory or a staged leaf, never a credential
    /// root or an arbitrary descendant. Catalog metadata alone grants no action.
    static func permitsMapping(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first, first.hasPrefix("."), !path.contains(".."),
              !parts.contains(where: { $0.isEmpty || $0.lowercased().contains("credential") || $0.lowercased().contains("keychain") }) else { return false }
        if parts.count == 1 { return !protected.contains(first.lowercased()) && !first.lowercased().hasPrefix(".zsh") && !first.lowercased().hasPrefix(".bash") }
        let staged = (parts.count == 2 && [".config", ".cache"].contains(first))
            || (parts.count == 3 && parts[0] == ".local" && parts[1] == "share")
        let leaf = parts.last?.lowercased() ?? ""
        let hiddenLeaf = leaf.hasPrefix(".") ? leaf : "." + leaf
        return staged && !protected.contains(hiddenLeaf)
            && !hiddenLeaf.hasPrefix(".zsh") && !hiddenLeaf.hasPrefix(".bash")
    }

    public static func affectedOwners(_ owners: Set<String>) -> Set<String> {
        let normalized = Set(owners.map { $0.lowercased() })
        return owners.union(ApplicationRelationships.knownPaths.filter { mapping in
            ([mapping.owner] + mapping.otherOwners).contains { normalized.contains($0.lowercased()) }
        }.map(\.owner))
    }

    static func mapping(for url: URL, home: URL) -> KnownLeftoverPath? {
        ApplicationRelationships.knownPaths.first {
            $0.relativePath.hasPrefix(".") && Filesystem.samePath(home.appendingPathComponent($0.relativePath), url)
        }
    }

    // Tests inject observations without changing production lookup or mutation policy.
    @TaskLocal static var toolPresenceOverride: HiddenOwnerState?

    /// Read metadata only, never execute a discovered CLI or Homebrew binary.
    /// A link (even dangling), inaccessible path, or unreadable process snapshot
    /// cannot establish absence. Brew's full dependency model belongs to task 066.
    public static func toolPresence(_ mapping: KnownLeftoverPath, home: URL) -> HiddenOwnerState {
        if let override = toolPresenceOverride { return override }
        guard !mapping.cliNames.isEmpty, let processes = CleanupActivity.processPaths() else { return .unknown }
        let names = Set(mapping.cliNames.map { $0.lowercased() })
        if processes.contains(where: { path in
            names.contains(URL(fileURLWithPath: path).lastPathComponent.lowercased())
                || (mapping.owner == "com.microsoft.VSCode" && ["/Visual Studio Code.app/", "/Visual Studio Code - Insiders.app/", "/VSCodium.app/", "/Code - OSS.app/"].contains { path.contains($0) })
        }) { return .present }
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.appendingPathComponent(".local/bin").path, home.appendingPathComponent("bin").path]
        directories += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard directories.allSatisfy({ $0.hasPrefix("/") }) else { return .unknown }
        for directory in Set(directories) {
            for name in mapping.cliNames {
                var info = stat()
                if lstat(URL(fileURLWithPath: directory).appendingPathComponent(name).path, &info) == 0 { return .present }
                if errno != ENOENT { return .unknown }
            }
        }
        // Cask installation can outlive its linked .app/CLI. Its presence retains
        // the data; no orphan/unused dependency claim is made here.
        let casks = mapping.owner == "com.microsoft.VSCode" ? ["visual-studio-code", "visual-studio-code@insiders"] : []
        for name in casks {
            var info = stat()
            if lstat("/opt/homebrew/Caskroom/" + name, &info) == 0 { return .present }
            if errno != ENOENT { return .unknown }
        }
        return .absent
    }

    static func discover(home: URL, installed: Set<String>, owners: Set<String>?,
                         lookup: @Sendable (String) -> Bool,
                         toolLookup: @Sendable (KnownLeftoverPath, URL) -> HiddenOwnerState,
                         report: inout ScanReport, emit: ScanEmitter) throws {
        let mappings = ApplicationRelationships.knownPaths.filter { $0.relativePath.hasPrefix(".") && (owners == nil || owners!.contains($0.owner)) }
        var candidates: [String: URL] = [:]
        for mapping in mappings.prefix(128) { candidates[mapping.relativePath] = home.appendingPathComponent(mapping.relativePath) }
        if mappings.count > 128 {
            report.isComplete = false; report.notices.append("Hidden mapping discovery limited to 128 exact paths.")
        }
        // Targeted owner refresh never enumerates home or unrelated staged roots.
        if owners == nil {
            for relative in ["", ".config", ".cache", ".local/share"] {
                let root = relative.isEmpty ? home : home.appendingPathComponent(relative)
                do {
                    let pin = try PinnedPath(root)
                    let names = try PinnedPath.names(in: pin.descriptor, limit: relative.isEmpty ? 4_096 : 1_024)
                    for name in names.sorted() where !relative.isEmpty || name.hasPrefix(".") {
                        try Task.checkCancellation()
                        guard candidates.count < 256 else {
                            report.isComplete = false
                            if !report.notices.contains("Hidden app data display limited to 256 directories.") { report.notices.append("Hidden app data display limited to 256 directories.") }
                            break
                        }
                        let url = root.appendingPathComponent(name)
                        let key = relative.isEmpty ? name : relative + "/" + name
                        var info = stat()
                        guard fstatat(pin.descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                        // Links are visible for inspection, never followed or measured.
                        guard info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFLNK else { continue }
                        candidates[key] = url
                    }
                    try pin.revalidate()
                } catch is CancellationError { throw CancellationError() }
                catch { report.recordFailure(error, at: root, category: .related, rule: "hidden.inventory", emit: emit, missingIsExpected: true) }
            }
        }
        var measurements = 0
        for (relative, url) in candidates.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            emit(.progress(.init("Checking hidden app data", current: relative)))
            let mapping = mappings.first { $0.relativePath == relative }
            var state: HiddenOwnerState = .unknown
            var detail = protected.contains(relative.lowercased())
                ? "Protected credential or shared configuration directory. Inspect only; contents were not read."
                : "No curated exact owner mapping. Size not measured; inspect only."
            var bytes: Int64?
            if let mapping {
                do {
                    _ = try ApplicationRelationships.resolve(url: url, owner: mapping.owner, home: home)
                    let present = ([mapping.owner] + mapping.otherOwners).contains { ApplicationPresence.hasOwner($0, installed: installed, lookup: lookup) }
                    state = present ? .present : toolLookup(mapping, home)
                    detail = (mapping.explanation ?? "Exact catalog ownership mapping.") + " " + state.rawValue + ". " + (mapping.consequence ?? "May contain useful user data.")
                    guard measurements < 8 else { throw LumaError.rejected("Hidden-data measurement budget reached; refresh for coverage.") }
                    measurements += 1
                    let item = try Filesystem.item(url, category: .related, safety: .review, explanation: detail,
                        consequence: mapping.consequence ?? "May remove useful app data.", rule: "application.leftover.exact-identifier",
                        owner: mapping.owner, captureContents: true, limit: 2_000)
                    bytes = item.bytes
                    if state == .absent { report.recordItem(item, emit: emit) }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    if GeneratedDataScanner.failureState(error) == .missing { continue }
                    if state == .absent { state = .unknown }
                    detail = "Inspect only · " + error.localizedDescription
                    report.recordFailure(error, at: url, category: .related, rule: "hidden.measurement", emit: emit)
                }
            }
            let observation = HiddenAppDataObservation(url: url, owner: mapping?.owner, state: state, bytes: bytes, detail: detail)
            report.hiddenAppData.append(observation); emit(.hiddenAppData(observation))
        }
    }
}
