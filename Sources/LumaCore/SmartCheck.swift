import Foundation

/// Sequential composition keeps the controller's single-worker, cancellation and
/// replacement guarantees. Each subcheck completes independently; no aggregate
/// candidate list or cross-category savings total is created.
public enum SmartCheck {
    public static let targets: [ScanTarget] = [.generatedData, .applications, .leftovers, .developerProjects, .downloads]
    public typealias Runner = @Sendable (ScanRequest, @escaping ScanEmitter) async throws -> ScanResult

    public static func requests(for request: ScanRequest) -> [ScanRequest] {
        targets.compactMap { target in
            if [.developerProjects, .downloads].contains(target), request.smartScopes[target] == nil { return nil }
            return ScanRequest(target, root: request.smartScopes[target], ignoredPaths: request.ignoredPaths)
        }
    }

    public static func run(_ request: ScanRequest, emit: @escaping ScanEmitter, runner: Runner) async throws -> ScanResult {
        var summary = ScanReport()
        for child in requests(for: request) {
            try Task.checkCancellation()
            emit(.progress(.init("Checking \(child.target.title)", current: child.scope)))
            let result: ScanResult
            do { result = try await runner(child, emit) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                var failed = ScanResult()
                failed.smartCheckFailure = error.localizedDescription
                failed.report.isComplete = false
                failed.report.notices = [error.localizedDescription]
                result = failed
            }
            try Task.checkCancellation()
            summary.isComplete = summary.isComplete && result.report.isComplete
            summary.notices += result.report.notices
            emit(.checkCompleted(ScanSnapshot(sessionID: UUID(), request: child, finishedAt: Date(), result: result)))
        }
        return ScanResult(report: summary)
    }

    public static func status(snapshot: ScanSnapshot?, startedAt: Date?, phase: ScanPhase?, now: Date = Date()) -> String {
        if let snapshot, snapshot.finishedAt >= (startedAt ?? .distantPast) {
            if snapshot.result.smartCheckFailure != nil { return "Could not check" }
            if now.timeIntervalSince(snapshot.finishedAt) > 900 { return "Stale · check again" }
            return snapshot.result.report.isComplete && snapshot.result.report.notices.isEmpty ? "Completed" : "Limited coverage"
        }
        switch phase {
        case .running, .stopping: return "Waiting for completion"
        case .cancelled: return "Cancelled · not checked"
        case .replaced: return "Replaced · not checked"
        case .timedOut: return "Timed out · not checked"
        case .failed: return "Could not check"
        default: return "Not checked"
        }
    }
}
