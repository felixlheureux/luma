import Foundation

public enum CleanupTool: String, Sendable, Codable {
    case packageManager, simulator, xcode
}

public struct CleanupActivity: Sendable {
    public let tools: Set<CleanupTool>?
    public let simulatorsBooted: Bool?
    public init(tools: Set<CleanupTool>?, simulatorsBooted: Bool? = nil) {
        self.tools = tools; self.simulatorsBooted = simulatorsBooted
    }

    public static func classify(_ lines: String) -> Set<CleanupTool> {
        var result: Set<CleanupTool> = []
        for line in lines.split(separator: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            let names = tokens.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
            if names.contains(where: { ["npm", "npx", "pnpm", "yarn", "corepack", "brew", "brew.rb", "npm-cli.js", "npx-cli.js", "pnpm.cjs", "pnpm.mjs", "yarn.js", "yarn.cjs"].contains($0) || $0.range(of: "^yarn-[0-9.]+\\.c?js$", options: .regularExpression) != nil }) { result.insert(.packageManager) }
            if names.contains(where: { ["xcode", "xcodebuild", "swift-build", "swift-package", "swift-test"].contains($0) }) { result.insert(.xcode) }
            if names.contains(where: { ["simulator", "simctl"].contains($0) }) { result.insert(.simulator) }
        }
        return result
    }

    public static func collect(checkSimulators: Bool = false) -> CleanupActivity {
        let tools = output("/bin/ps", ["-axo", "comm=,args="]).map(classify)
        var booted: Bool?
        if checkSimulators, let data = output("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "--json"])?.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let devices = json["devices"] as? [String: [[String: Any]]] {
            booted = devices.values.flatMap { $0 }.contains { $0["state"] as? String == "Booted" }
        }
        return CleanupActivity(tools: tools, simulatorsBooted: booted)
    }

    private static func output(_ path: String, _ arguments: [String]) -> String? {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: deadline)
        defer { deadline.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
