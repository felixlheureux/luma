import Foundation
import CoreFoundation
import Darwin

public struct HomebrewInventory: Sendable {
    public var formulae: [String] = []
    public var manualPackages: [String] = []
    public var unneededDependencies: [String]? = nil
    public var cleanupSuggestions: [String]? = nil
    public var managedApps: [String: String] = [:]
    public var issues: [String] = []
    public var observedAt = Date()
    public init() {}
    public func cask(for app: URL) -> String? { managedApps[app.resolvingSymlinksInPath().exactStandardizedFileURL.path] }
}

/// Read-only by construction. No operation here accepts arbitrary command arguments.
public struct HomebrewProvider: Sendable {
    public enum Query: Sendable {
        case prefix, inventory, autoremove, cleanup
        var arguments: [String] {
            switch self {
            case .prefix: ["--prefix"]
            case .inventory: ["info", "--json=v2", "--installed"]
            case .autoremove: ["autoremove", "--dry-run"]
            case .cleanup: ["cleanup", "--dry-run"]
            }
        }
    }
    public let executables: [URL]
    public let timeout: TimeInterval
    @TaskLocal public static var fixtureExecutables: [URL]?
    public init(executables: [URL]? = nil, timeout: TimeInterval = 20) {
        self.executables = executables ?? Self.fixtureExecutables ?? Self.candidates
        self.timeout = timeout
    }
    private static var candidates: [URL] {
        var paths = ["/opt/homebrew/bin/brew"]
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] { paths.append(prefix + "/bin/brew") }
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/brew" }
        return Array(Set(paths)).sorted().filter { !$0.hasPrefix("/usr/local/") }.map { URL(fileURLWithPath: $0) }
    }
    static func trusted(_ url: URL, executable: Bool = false) throws {
        let resolved = url.resolvingSymlinksInPath()
        var current = resolved
        while current.path != "/" {
            let attrs = try FileManager.default.attributesOfItem(atPath: current.path)
            guard let owner = attrs[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == getuid() || owner.uint32Value == 0,
                  let mode = attrs[.posixPermissions] as? NSNumber,
                  mode.intValue & 0o002 == 0 || (mode.intValue & 0o1000 != 0 && ["/private/tmp", "/tmp"].contains(current.path)) else {
                throw LumaError.rejected("Homebrew path ownership or permissions cannot be verified: " + current.path)
            }
            current.deleteLastPathComponent()
        }
        if executable && !FileManager.default.isExecutableFile(atPath: resolved.path) {
            throw LumaError.rejected("Homebrew is not executable: " + url.path)
        }
    }
    public func installation() throws -> URL? {
        for executable in executables {
            var value = stat()
            guard lstat(executable.path, &value) == 0 else {
                if errno == ENOENT { continue }
                throw LumaError.rejected("Homebrew executable is unreadable: " + executable.path)
            }
            guard executable.lastPathComponent == "brew", executable.deletingLastPathComponent().lastPathComponent == "bin" else {
                throw LumaError.rejected("Unsupported Homebrew executable location.")
            }
            try Self.trusted(executable, executable: true)
            return executable
        }
        return nil
    }
    public func query(_ query: Query, executable: URL) throws -> String {
        try Task.checkCancellation()
        try Self.trusted(executable, executable: true)
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.arguments = query.arguments
        // Do not inherit Ruby/Bash startup hooks, command overrides or a caller's Brew mutation flags.
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_COLOR": "1", "HOMEBREW_NO_AUTOREMOVE": "1"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = errors
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
        }
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        for handle in handles { _ = fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) }
        var buffers = [Data(), Data()]
        let deadline = Date().addingTimeInterval(timeout)
        func drain() throws {
            for index in handles.indices {
                var bytes = [UInt8](repeating: 0, count: 8192)
                while true {
                    let count = read(handles[index].fileDescriptor, &bytes, bytes.count)
                    if count <= 0 { break }
                    buffers[index].append(contentsOf: bytes.prefix(count))
                    guard buffers[index].count <= 8 * 1024 * 1024 else { throw LumaError.rejected("Homebrew output exceeded the inventory limit.") }
                    try Task.checkCancellation()
                    guard Date() < deadline else { throw LumaError.rejected("Homebrew query timed out.") }
                }
            }
        }
        repeat {
            try Task.checkCancellation(); try drain()
            guard Date() < deadline else { throw LumaError.rejected("Homebrew query timed out.") }
            if process.isRunning { Thread.sleep(forTimeInterval: 0.01) }
        } while process.isRunning
        try drain()
        guard process.terminationStatus == 0 else {
            throw LumaError.rejected("Homebrew \(query.arguments.joined(separator: " ")) failed (exit \(process.terminationStatus)): " + String(decoding: buffers[1].prefix(2000), as: UTF8.self))
        }
        guard buffers[1].isEmpty else {
            throw LumaError.rejected("Homebrew reported incomplete results: " + String(decoding: buffers[1].prefix(2000), as: UTF8.self))
        }
        guard let text = String(data: buffers[0], encoding: .utf8) else { throw LumaError.rejected("Homebrew returned invalid text.") }
        return text
    }
    public func inventory() throws -> HomebrewInventory {
        var result = HomebrewInventory()
        guard let executable = try installation() else { result.issues = ["Homebrew is not installed in a supported current-user location."]; return result }
        let prefix = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard try query(.prefix, executable: executable).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.path else {
            throw LumaError.rejected("Homebrew prefix does not match its verified executable.")
        }
        do { result.managedApps = try Self.managedApps(prefix: prefix) }
        catch is CancellationError { throw CancellationError() }
        catch { result.issues.append(error.localizedDescription) }
        do { result = try Self.decode(query(.inventory, executable: executable), into: result) }
        catch is CancellationError { throw CancellationError() }
        catch { result.issues.append("Package inventory unavailable: " + error.localizedDescription); return result }
        do { result.unneededDependencies = try Self.parseAutoremove(query(.autoremove, executable: executable), formulae: result.formulae, manual: result.manualPackages) }
        catch is CancellationError { throw CancellationError() }
        catch { result.issues.append("Unneeded dependencies unavailable: " + error.localizedDescription) }
        do { result.cleanupSuggestions = try Self.parseCleanup(query(.cleanup, executable: executable)) }
        catch is CancellationError { throw CancellationError() }
        catch { result.issues.append("Cleanup suggestions unavailable: " + error.localizedDescription) }
        return result
    }
    static func decode(_ text: String, into initial: HomebrewInventory = .init()) throws -> HomebrewInventory {
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]], let casks = root["casks"] as? [[String: Any]] else {
            throw LumaError.rejected("Unexpected Homebrew JSON v2 schema.")
        }
        var result = initial
        for formula in formulae {
            guard let name = formula["full_name"] as? String, validName(name),
                  let installed = formula["installed"] as? [[String: Any]], !installed.isEmpty,
                  installed.allSatisfy({ ($0["installed_on_request"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true }) else { throw LumaError.rejected("Incomplete formula installation metadata.") }
            result.formulae.append(name)
            if installed.contains(where: { $0["installed_on_request"] as? Bool == true }) { result.manualPackages.append(name + " (formula)") }
        }
        for cask in casks {
            guard let name = cask["token"] as? String, validName(name), cask["installed"] is String else { throw LumaError.rejected("Incomplete cask installation metadata.") }
            // Cask receipts do not establish usage frequency, even for CLI/font-only casks.
            result.manualPackages.append(name + " (cask; installation intent unknown)")
        }
        guard Set(result.formulae).count == result.formulae.count else { throw LumaError.rejected("Duplicate Homebrew formula records.") }
        result.formulae.sort(); result.manualPackages.sort()
        return result
    }
    static func validName(_ name: String) -> Bool { name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9@+_.-]*(/[a-zA-Z0-9][a-zA-Z0-9@+_.-]*){0,2}$", options: .regularExpression) != nil }
    static func parseAutoremove(_ text: String, formulae: [String], manual: [String]) throws -> [String] {
        let lines = text.split(separator: "\n").map(String.init)
        if lines.isEmpty { return [] }
        guard let header = lines.first, header.range(of: "^(==> )?Would autoremove [0-9]+ unneeded formula(e)?:$", options: .regularExpression) != nil,
              let count = header.split(separator: " ").compactMap({ Int($0) }).first else { throw LumaError.rejected("Unexpected autoremove dry-run output.") }
        let names = Array(lines.dropFirst())
        guard names.count == count, Set(names).count == count,
              names.allSatisfy({ validName($0) && formulae.contains($0) && !manual.contains($0 + " (formula)") }) else { throw LumaError.rejected("Autoremove candidates disagree with installed dependency metadata.") }
        return names.sorted()
    }
    static func parseCleanup(_ text: String) throws -> [String] {
        let lines = text.split(separator: "\n").map(String.init)
        var suggestions: [String] = []
        for line in lines {
            if line.hasPrefix("Would remove: /") || line.hasPrefix("Would remove (broken link): /") || line.hasPrefix("Would remove (empty directory): /") { suggestions.append(line) }
            else if line.range(of: "^(==> )?This operation would free approximately .+\\.$", options: .regularExpression) != nil { continue }
            else { throw LumaError.rejected("Unexpected cleanup dry-run output; suggestions withheld.") }
        }
        return suggestions
    }

    /// Homebrew retains an installed artifact symlink in Caskroom pointing to the
    /// exact deployed app (including renamed/custom-appdir targets). No basename matching.
    public static func managedApps(prefix: URL) throws -> [String: String] {
        let root = prefix.appendingPathComponent("Caskroom")
        var attrs = stat()
        if lstat(root.path, &attrs) != 0 {
            if errno == ENOENT { return [:] }
            throw LumaError.rejected("Homebrew cask provenance is unreadable.")
        }
        try trusted(root)
        var apps: [String: String] = [:], count = 0
        func children(_ directory: URL) throws -> [URL] {
            try Task.checkCancellation()
            let values = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            count += values.count
            guard count <= 30_000 else { throw LumaError.rejected("Homebrew cask provenance exceeds the inspection limit.") }
            return values
        }
        func isDirectory(_ url: URL) throws -> Bool {
            try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory
        }
        // Inspect installed artifact slots only. Never walk the contents of a
        // staged application, SDK, font package or command-line distribution.
        for cask in try children(root) where try isDirectory(cask) {
            try trusted(cask)
            for version in try children(cask) where try isDirectory(version) {
                try trusted(version)
                for url in try children(version) where url.pathExtension == "app" {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
                    let target = url.resolvingSymlinksInPath()
                    if FileManager.default.fileExists(atPath: target.path), (try? Filesystem.applicationIdentifier(at: target)) != nil {
                        apps[target.exactStandardizedFileURL.path] = cask.lastPathComponent
                    }
                }
            }
        }
        return apps
    }
    public static func nativeUninstallBlock(_ appURL: URL) throws -> String? {
        let provider = HomebrewProvider()
        // Inspect all supported installations so another prefix cannot mask a cask.
        for candidate in provider.executables {
            guard let executable = try HomebrewProvider(executables: [candidate]).installation() else { continue }
            let prefix = executable.deletingLastPathComponent().deletingLastPathComponent()
            if let token = try managedApps(prefix: prefix)[appURL.resolvingSymlinksInPath().exactStandardizedFileURL.path] {
                return "Installed with Homebrew (\(token)). Uninstall this cask using Homebrew to update its receipts and artifacts. Luma's Trash-only uninstall is disabled; Homebrew removal has no Luma Undo."
            }
        }
        return nil
    }
}
