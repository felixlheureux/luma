# 064 — Inspect and select containing folders in Storage

Status: Not started  
Priority: P0  
Depends on: Completed 056/062

## Outcome

From a large file, users can inspect its **actual filesystem parent** or a chosen safe ancestor, see that folder's contents, and select the **folder** rather than the individual file when appropriate. No guessed project root, no hidden recursive delete action.

## Existing code

- `Sources/LumaCore/StorageIndex.swift`: `StorageNode.parentID`, `StorageIndex.breadcrumbs`, completeness and final preparation.
- `Sources/LumaCore/StorageDiscovery.swift`: multi-root hierarchy, bounded index and persistence.
- `Sources/LumaCore/StorageListing.swift`: Largest files rows come from an existing hierarchy.
- `Sources/LumaApp/StorageView.swift`: row, details, Explore and breadcrumbs.
- `Sources/LumaApp/StorageActions.swift`: `navigateStorage`, `selectStorage`, `storageEligible`, `trashStorage`.
- `Sources/LumaCore/SafetyEngine.swift`, `CleanupPlan.swift`: final policy, ancestor/descendant selection prohibition and duplicate proofs.

## Scope

1. In **Largest files**, offer **Inspect containing folder** on each local file (row context menu or compact action). Resolve via the observed `parentID`/standardized exact URL, not filename patterns or a heuristic. Switch to Explore, open that parent and focus/highlight the originating file. Preserve history, existing selections, search/filter state and ongoing unrelated work. Reveal hidden parents without silently changing the global Hidden preference.
2. Show the filesystem **ancestor breadcrumb** with clear path and actual containment. Allow the user to choose a different ancestor; never automatically guess that a `Projects` or `Downloads` folder is disposable. The containing folder should be browsable even when ineligible for cleanup.
3. Offer **Select this folder** only for a complete, supported current-user local directory. Replace selected descendants with the single parent target using existing selection rules; never authorize both ancestor and descendant. Show its precise path, observed logical size, child count and partial/inaccessible coverage before action. The existing fixed footer still performs **Move to Trash**; do not create another delete modal.
4. When the broad discovery marked a folder incomplete, offer **Analyze this folder** (explicit targeted, bounded rescan) instead of enabling removal or restarting the whole Mac scan. Reuse StorageIndex/StorageScope and merge refreshed evidence into the current hierarchy without losing unrelated results. If still incomplete, keep folder selection disabled. Do not pretend a limited display subset is complete.
5. Reuse CleanupPlan, SafetyEngine and CleanupJournal for folder moves and native Undo. Never infer deletion rights from merely discovering/visiting a parent. Revalidate identity, descendants, ignored paths, known duplicate keepers, volume and exclusions before executing. If evidence changed, abort with one useful inline explanation.

## Safety invariants

- Keep home root and protected top-level home dirs (`Downloads`, `Documents`, `Desktop`, `Library`, etc.) nonselectable; `~/Library` descendants remain outside *generic* Storage deletion.
- **Close the existing generic Storage-selection gap before enabling new parent-folder actions:** in `SafetyEngine`, protect credential/configuration locations such as `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, shell/git credential files, and the `~/.config`, `~/.cache`, and `~/.local` roots from generic deletion, including attempted selection of a containing ancestor. Enforce policy at UI eligibility, plan preparation, and final mutation; approved exact-owner leaf cleanup belongs to task 065 instead. Add regression fixtures.
- Do not follow symlinks/aliases, cross volumes, descend into package internals, or grant direct deletion for cloud/online-only files, protected subtrees or an unobserved ancestor.
- Reconcile hard-linked logical totals without promising exact disk savings (APFS clones/snapshots may also affect reclaimable space).
- A folder with ignored, protected, unknown or changed descendants remains non-actionable even if one large contained file is valid.

## Acceptance fixtures

- A large file in `~/Downloads/Project/cache/archive.bin` opens `cache`, retains selected file focus, and permits selection of `cache` after complete analysis; `Downloads` itself cannot be selected.
- A file inside `~/Documents` can inspect that parent without being allowed to delete `Documents`.
- Parent selection removes existing descendant selections; choosing a child under an already selected parent does not silently add both.
- Partial/bounded folder and saved-only observations remain read-only until targeted verification. File addition/replacement between analysis and Trash blocks cleanup.
- Ignored nested target, symlink out of home, different volume, app package, known duplicate keeper and iCloud-only target cannot be bulk-trashed.
- Explore/Largest-files, hidden filtering, selected filter, map/list focus, scroll, Undo and native narrow-window keyboard behavior remain correct.

## Validation

Add focused Swift Testing cases to `Tests/LumaCoreTests/StorageDiscoveryTests.swift` and storage safety tests; extend `Sources/LumaApp/StorageBrowserCheck.swift` / `Scripts/check-storage-browser.sh` native fixture to cover inspect-folder and bounded reanalysis. Do not run on actual personal folders during tests.