import Foundation

public struct ProcessSample: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parentPID: Int32
    public let executable: String
    public let cpu: Double
    public let memory: Int64
    public let usesFootprint: Bool
    public var name: String { URL(fileURLWithPath: executable).lastPathComponent }
    public init(pid: Int32, parentPID: Int32, executable: String, cpu: Double, memory: Int64, usesFootprint: Bool = true) {
        self.pid = pid; self.parentPID = parentPID; self.executable = executable
        self.cpu = cpu; self.memory = memory; self.usesFootprint = usesFootprint
    }
}

public struct ProcessGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleURL: URL?
    public let processes: [ProcessSample]
    public let mainPID: Int32?
    public var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
    public var memory: Int64 { processes.reduce(0) { $0 + $1.memory } }
    public var usesFootprint: Bool { processes.allSatisfy(\.usesFootprint) }
}

public enum ProcessGrouping {
    public static func outerApplication(_ executable: String) -> URL? {
        guard executable.hasPrefix("/") else { return nil }
        let components = URL(fileURLWithPath: executable).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index])))
    }

    public static func group(_ samples: [ProcessSample]) -> [ProcessGroup] {
        let byPID = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func owner(_ sample: ProcessSample) -> URL? {
            if let url = outerApplication(sample.executable) { return url }
            var cursor = sample
            var visited: Set<Int32> = []
            while visited.insert(cursor.pid).inserted, visited.count < 32, let parent = byPID[cursor.parentPID] {
                if let url = outerApplication(parent.executable) { return url }
                cursor = parent
            }
            return nil
        }
        var groups: [String: [ProcessSample]] = [:]
        var bundles: [String: URL] = [:]
        for sample in samples {
            if let url = owner(sample) {
                groups[url.path, default: []].append(sample); bundles[url.path] = url
            } else { groups["process:\(sample.pid)", default: []].append(sample) }
        }
        return groups.map { key, processes in
            let bundle = bundles[key]
            let name = bundle.flatMap { (try? Filesystem.applicationMetadata(at: $0)["CFBundleDisplayName"]) as? String }
                ?? bundle?.deletingPathExtension().lastPathComponent ?? processes[0].name
            // The owning main process has no parent inside this application's group.
            let pids = Set(processes.map(\.pid))
            let mainPID = bundle == nil ? nil : processes.first(where: { !pids.contains($0.parentPID) && outerApplication($0.executable) == bundle })?.pid
            return ProcessGroup(id: key, name: name, bundleURL: bundle, processes: processes.sorted { $0.memory > $1.memory }, mainPID: mainPID)
        }.sorted { $0.memory > $1.memory }
    }
}
