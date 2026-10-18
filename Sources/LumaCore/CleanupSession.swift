import Foundation

public enum CleanupPhase: String, Codable, Sendable {
    case validating, moving, stopping, completed, stopped, partial, failed, recoveryNeeded
    public var isTerminal: Bool { ![.validating, .moving, .stopping].contains(self) }
}

public struct CleanupSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let source: CleanupSource
    public let date: Date
    public let paths: [URL]
    public let logicalBytes: Int64
    public var phase: CleanupPhase
    public var detail: String?
    public var blockedPath: URL? = nil
}

public struct CleanupProgress: Sendable {
    public let sessionID: UUID
    public let phase: CleanupPhase
    public let current: URL?
    public let completed: Int
    public let total: Int
}

public enum UndoEligibility: String, Sendable {
    case eligible, changed, missing, restored, occupied, unavailable
}

public struct UndoReviewItem: Identifiable, Sendable {
    public var id: UUID { record.id }
    public let record: CleanupRecord
    public let eligibility: UndoEligibility
    public let detail: String
}

/// The exact eligible record IDs reviewed by the user; execution checks again.
public struct UndoReview: Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let items: [UndoReviewItem]
    public var eligibleIDs: [UUID] { items.filter { $0.eligibility == .eligible }.map(\.id) }
}

public struct UndoOutcome: Codable, Sendable {
    public let recordID: UUID
    public let restored: Bool
    public let detail: String
}

public struct UndoAttempt: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let date: Date
    public let recordIDs: [UUID]
    public var outcomes: [UndoOutcome]
    public var phase: CleanupPhase
}

/// Only the verification/commit after a started native mutation ignores Stop.
/// Preflight and every next-item boundary remain cancellable.
enum MutationOutcome {
    @TaskLocal static var preserving = false
    static func checkCancellation() throws {
        if !preserving { try Task.checkCancellation() }
    }
}
