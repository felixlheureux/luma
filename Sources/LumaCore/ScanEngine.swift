import Foundation

/// Runs only in a controller-owned worker. Traversal scopes remain the existing
/// bounded scanners. All filesystem access uses the shared provider policy.
public enum ScanEngine {
    public static func run(_ request: ScanRequest, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           applicationRoots: [URL]? = nil, analysisIndex: AnalysisIndex? = nil, emit: @escaping ScanEmitter = { _ in }) async throws -> ScanResult {
        try Task.checkCancellation()
        switch request.target {
        case .overview:
            return try await SmartCheck.run(request, emit: emit) { child, output in
                try await run(child, home: home, applicationRoots: applicationRoots, analysisIndex: analysisIndex, emit: output)
            }
        case .generatedData:
            let generated = try await GeneratedDataScanner(home: home, progress: { update in
                emit(.progress(.init("Checking generated data", current: update.current, completed: update.completedRules,
                                     total: update.totalRules, entries: update.entries, bytes: update.bytes)))
            }, emit: emit).scan()
            return ScanResult(report: generated)
        case .applications:
            return try ApplicationScanner.inventory(home: home, roots: applicationRoots, emit: emit)
        case .leftovers:
            return ScanResult(report: try await LeftoverScanner(home: home, applicationRoots: applicationRoots, emit: emit, owners: request.residueOwners).scan())
        case .footprint:
            guard let app = request.application else { throw LumaError.rejected("Choose an application to inspect.") }
            return try ApplicationFootprintScanner.inspect(app, home: home, emit: emit)
        case .storage:
            guard let root = request.root else {
                let index = try StorageDiscovery.scan(home: home, ignoredPaths: request.ignoredPaths, emit: emit)
                var report = ScanReport()
                report.visited = index.nodes.count; report.duration = index.duration
                report.isComplete = false
                report.notices = [index.nodes[index.rootID]?.issue ?? "Accessible local storage only"]
                return ScanResult(report: report, storageIndex: index)
            }
            let (cache, cacheNote) = analysisSession(root: root, index: analysisIndex)
            let index = try StorageIndex.scan(root: root, ignoredPaths: request.ignoredPaths, home: home, expectedVolume: request.storageVolumeIdentity, cache: cache, emit: emit)
            var report = ScanReport()
            for node in index.nodes.values where !node.isComplete {
                var coverage = ScanCoverage(ruleID: "storage.index", title: node.url.lastPathComponent,
                    path: node.url.path, category: .storage, state: node.coverageState ?? .skipped,
                    bytes: node.bytes, detail: node.issue ?? "Incomplete inspection")
                coverage.accessCapability = node.accessCapability
                report.coverage.append(coverage); emit(.coverage(coverage))
                report.isComplete = false
            }
            report.visited = index.nodes.count
            report.duration = index.duration
            var result = ScanResult(report: report, storageIndex: index)
            result.analysisCache = try finishAnalysis(cache, note: cacheNote)
            if result.analysisCache?.state == .changed {
                result.report.isComplete = false
                result.report.notices.append("The folder changed during analysis. Scan again for current results.")
            }
            return result
        case .developerProjects:
            guard let root = request.root else { throw LumaError.rejected("Choose a project folder to inspect.") }
            let inventory = try DeveloperProjects.scan(root: root, ignoredPaths: request.ignoredPaths, emit: emit)
            var result = ScanResult(report: inventory.report)
            result.projectInventory = inventory
            return result
        case .deviceBackups:
            let inventory = try DeviceBackups.scan(home: home, ignoredPaths: request.ignoredPaths, emit: emit)
            var result = ScanResult(report: inventory.report)
            result.deviceBackups = inventory
            return result
        case .downloads:
            guard let root = request.root else { throw LumaError.rejected("Choose a Downloads folder to review.") }
            let inventory = try DownloadsScanner.scan(root: root, ignoredPaths: request.ignoredPaths, emit: emit)
            var result = ScanResult(report: inventory.report, duplicates: inventory.duplicates)
            result.downloadsInventory = inventory
            return result
        case .duplicates:
            guard let root = request.root else { throw LumaError.rejected("Choose a folder to compare.") }
            let (cache, cacheNote) = analysisSession(root: root, index: analysisIndex)
            var result = try DuplicateScanner(root: root, emit: emit).scanResult(cache: cache)
            result.analysisCache = try finishAnalysis(cache, note: cacheNote)
            if result.analysisCache?.state == .changed {
                result.report.isComplete = false
                result.report.notices.append("The folder changed during analysis. Scan again for current results.")
            }
            return result
        }
    }
    private static func analysisSession(root: URL, index: AnalysisIndex?) -> (AnalysisIndexSession?, AnalysisCacheSummary?) {
        guard let index else { return (nil, nil) }
        do { return (try index.begin(root: root, version: "analysis-policy-1/" + Rules.catalog().version), nil) }
        catch { return (nil, AnalysisCacheSummary(state: .unavailable)) }
    }

    private static func finishAnalysis(_ cache: AnalysisIndexSession?, note: AnalysisCacheSummary?) throws -> AnalysisCacheSummary? {
        try Task.checkCancellation()
        guard let cache else { return note }
        do {
            let saved = try cache.finish()
            return AnalysisCacheSummary(state: saved ? .updated : .changed,
                reusedMetadata: cache.reusedMetadata, reusedHashes: cache.reusedHashes)
        } catch is CancellationError { throw CancellationError() }
        catch { return AnalysisCacheSummary(state: .notSaved) }
    }
}
