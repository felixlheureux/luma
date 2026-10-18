import Foundation

/// Runs only in a controller-owned worker. Traversal scopes remain the existing
/// bounded scanners. All filesystem access uses the shared provider policy.
public enum ScanEngine {
    public static func run(_ request: ScanRequest, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           applicationRoots: [URL]? = nil, emit: @escaping ScanEmitter = { _ in }) async throws -> ScanResult {
        try Task.checkCancellation()
        switch request.target {
        case .generatedData, .overview:
            let generated = try await GeneratedDataScanner(home: home, progress: { update in
                emit(.progress(.init("Checking generated data", current: update.current, completed: update.completedRules,
                                     total: update.totalRules, entries: update.entries, bytes: update.bytes)))
            }, emit: emit).scan()
            if request.target == .generatedData { return ScanResult(report: generated) }
            try Task.checkCancellation()
            let inventory = try ApplicationScanner.inventory(home: home, roots: applicationRoots, emit: emit)
            var combined = generated
            combined.notices += inventory.report.notices
            combined.coverage += inventory.report.coverage
            combined.isComplete = generated.isComplete && inventory.report.isComplete
            combined.duration += inventory.report.duration
            return ScanResult(report: combined, applications: inventory.applications)
        case .applications:
            return try ApplicationScanner.inventory(home: home, roots: applicationRoots, emit: emit)
        case .leftovers:
            return ScanResult(report: try await LeftoverScanner(home: home, applicationRoots: applicationRoots, emit: emit).scan())
        case .footprint:
            guard let app = request.application else { throw LumaError.rejected("Choose an application to inspect.") }
            return ScanResult(report: try ApplicationScanner.footprintReport(app, home: home, emit: emit))
        case .storage:
            guard let root = request.root else { throw LumaError.rejected("Choose a folder to analyze.") }
            return ScanResult(report: try await FolderScanner(root: root, emit: emit).scan())
        case .duplicates:
            guard let root = request.root else { throw LumaError.rejected("Choose a folder to compare.") }
            return try DuplicateScanner(root: root, emit: emit).scanResult()
        }
    }
}
