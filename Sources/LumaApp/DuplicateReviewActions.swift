import SwiftUI
import LumaCore

extension AppModel {
    func duplicateGroup(_ id: String, source: CleanupSource) -> DuplicateGroup? {
        let target: ScanTarget = source == .downloads ? .downloads : .duplicates
        let groups = source == .downloads ? completedSnapshots[target]?.result.downloadsInventory?.duplicates : completedSnapshots[target]?.result.duplicates
        return groups?.first { $0.id == id }
    }

    func clearDuplicateComparison() {
        duplicateComparisonTask?.cancel(); duplicateComparisonTask = nil
        duplicateComparisonGeneration = UUID()
        duplicateComparisonGroup = nil; duplicateComparisons = [:]; duplicateComparisonErrors = [:]
    }

    func compareDuplicateGroup(_ group: DuplicateGroup, source: CleanupSource) {
        clearDuplicateComparison()
        guard let current = duplicateGroup(group.id, source: source), current.items == group.items else { return }
        duplicateComparisonGroup = group.id
        let generation = duplicateComparisonGeneration, exclusions = ignored
        duplicateComparisonTask = Task { @MainActor [weak self] in
            // One bounded worker at a time. Load previews only after an explicit
            // Compare action; rendering never opens paths or delegates to Quick Look.
            for item in DuplicateReview.members(group).prefix(100) {
                do {
                    guard !exclusions.contains(where: { Filesystem.isWithin(item.url, root: URL(fileURLWithPath: $0)) }) else { continue }
                    let result = try await self?.offMain { try DuplicateComparison.read(item) }
                    try Task.checkCancellation()
                    guard self?.duplicateComparisonGeneration == generation, self?.ignored == exclusions else { return }
                    self?.duplicateComparisons[item.id] = result
                } catch is CancellationError { return }
                catch {
                    guard self?.duplicateComparisonGeneration == generation else { return }
                    self?.duplicateComparisonErrors[item.id] = error.localizedDescription
                }
            }
        }
    }

    func prepareDuplicateKeeper(group: DuplicateGroup, keeper: CleanupItem, source: CleanupSource) {
        guard !busy, let current = duplicateGroup(group.id, source: source), current.items == group.items else { return }
        duplicateChoice = nil; duplicateChoiceSource = nil
        let exclusions = ignored
        busy = true; status = "Verifying keeper choice…"
        scanTask = Task {
            do {
                let choice = try await offMain {
                    let choice = try DuplicateKeeperChoice(group: group, keeperID: keeper.id)
                    try choice.validate(ignoredPaths: exclusions)
                    return choice
                }
                try Task.checkCancellation()
                guard ignored == exclusions, duplicateGroup(group.id, source: source)?.items == group.items else {
                    throw LumaError.rejected("The duplicate scan changed. Choose a keeper again.")
                }
                duplicateChoiceSource = source; duplicateChoice = choice
                status = "Preview the keeper and proposed removals"
            } catch is CancellationError { status = "Keeper choice cancelled" }
            catch { selected.subtract(group.items.map(\.id)); self.error = error.localizedDescription }
            finish()
        }
    }

    func applyDuplicateKeeper() {
        guard !busy, let choice = duplicateChoice, let source = duplicateChoiceSource else { return }
        let exclusions = ignored
        busy = true; status = "Rechecking keeper and copies…"
        scanTask = Task {
            do {
                try await offMain { try choice.validate(ignoredPaths: exclusions) }
                try Task.checkCancellation()
                guard ignored == exclusions, duplicateGroup(choice.group.id, source: source)?.items == choice.group.items else {
                    throw LumaError.rejected("The duplicate scan changed. Choose a keeper again.")
                }
                selected.subtract(choice.group.items.map(\.id)); selected.formUnion(choice.removals.map(\.id))
                duplicateChoice = nil; duplicateChoiceSource = nil
                status = "Keeper retained · review selected removals before Trash"
            } catch is CancellationError { status = "Keeper choice cancelled" }
            catch {
                selected.subtract(choice.group.items.map(\.id)); duplicateChoice = nil
                self.error = error.localizedDescription
            }
            finish()
        }
    }
}
