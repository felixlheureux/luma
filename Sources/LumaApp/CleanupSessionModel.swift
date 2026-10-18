import SwiftUI
import LumaCore

/// Owns mutation lifetime separately from scan/review cancellation.
@MainActor @Observable final class CleanupSessionModel {
    var sessions: [CleanupSession] = []
    var undoAttempts: [UndoAttempt] = []
    var progress: CleanupProgress?
    var stopping = false
    var undoReview: UndoReview?
    @ObservationIgnored private var task: Task<Void, Never>?
    private(set) var isRunning = false

    func run(_ operation: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        progress = nil; stopping = false; isRunning = true
        task = Task {
            await operation()
            task = nil; stopping = false; progress = nil; isRunning = false
        }
    }

    func update(_ progress: CleanupProgress) { self.progress = progress }
    func stop() { stopping = true; task?.cancel() }
}
