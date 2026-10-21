# 064 — Inspect and select containing folders in Storage

Status: Done

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


## Implementation — 2026-10-21

- Largest files exposes an accessible, keyboard-focusable Inspect containing folder action with a standard folder icon and an explicit hit area. Resolution requires the observed exact filesystem parent and matching device. Explore reveals/highlights the originating file, retains history/selections and temporarily pauses browsing filters for the inspection path without changing their saved values or the global Hidden preference. Resume filters/Largest files restores normal filtering. Breadcrumbs expose observed ancestors and full-path help. The owner-requested Largest files/Explore picker now aligns with the left content edge.
- The current folder shows its exact path, observed unique logical bytes, observed child count and complete/partial coverage. Select this folder uses existing ancestor/descendant selection rules and the fixed Trash footer. Protected parents remain browsable. Saved-only/expired/incomplete directories offer Analyze this folder: an explicit local subtree walk capped at 40,000 entries, the existing 15-second walk budget and 128-level depth bound. Packages, links, aliases, provider paths and volume changes remain excluded.
- Targeted analysis replaces only that subtree, reconciles hard links and preserves unrelated dates, coverage and selections. Completion merges into the latest hierarchy, retaining concurrent unrelated removals/updates; a changed analyzed subtree or scope rejects publication inline rather than reviving removed observations. Per-revision folder eligibility caching also keys home, ignores, known duplicate paths and earliest contained observation expiry, keeping focus/map interactions responsive. Preparation and execution never trust that display cache.
- Shared SafetyEngine policy protects sensitive home credentials, shell/git files and configuration/cache/local roots, including containing ancestors and conservative case variants. Generic package cleanup and custom roots inside packages are rejected. Saved display nodes require fresh verification. Preparation compares observed descendant identity, sizes and actual directory membership before/after capturing a plan; the existing plan/journal still revalidates ignores, duplicate keepers, ownership, providers, volume and full-tree identity before each move. Dedicated application cleanup retains supported internal framework links and journal Undo.

## Validation

- `bash Scripts/test.sh`: **361 tests across 37 suites pass**, with the five existing opt-in native Trash, volume, real-iCloud and benchmark checks skipped. New generated fixtures cover exact parents/protected ancestors, saved-only verification, bounded targeted analysis, hard links, changed/replaced/ignored/unknown/package/link contents, final-mutation additions, credential/configuration paths (16 parameter cases), and merging a completed analysis without reviving removed siblings or overwriting a changed target. The previous generic-app-link fixture now exercises its supported dedicated application rule and still checks Undo and alias rejection.
- Final debug build and `Scripts/check-storage-browser.sh` pass **Light/Dark/System** on **Apple M2, 16 GB, macOS 27.0.1**, with **1,400 generated observations** and a 181-child analyzed folder. Actual Inspect/Analyze/Select controls, hidden-parent focus, filter retention, descendant replacement, blocked Downloads/Documents selection, concurrent unrelated observation removal, folder Trash/Undo, map single/double-click/list reveal, native Search keyboard activation, narrow layouts and continued monitoring pass. Only fixture metadata and an injected mover were used; no personal-folder scan, real Trash or cloud download ran.
- Across appearances: first results **0.517–0.599 s**, warm open **0.154–0.156 s**, requested discovery **4.195–4.261 s**, maximum sampled discovery main-actor interval **0.101–0.112 s**. Parent inspection **0.231–0.281 s**, targeted analysis including concurrent-state merge **0.980–1.031 s**, folder Trash **1.706–1.759 s**, folder Undo/observation update **1.336–1.368 s**. Timings use the generated fixture above, not personal data or exact reclaimed disk measurements.
- Native application footprint/reset and direct uninstall/Undo regression checks pass Light/Dark/System. Cleanup-session Stop/partial-outcome/direct-Undo checks pass Light/Dark. These verify the unchanged shared package policy/journal paths; the final merge follow-up reran the full core suite and native Storage checker.
- Inspected dedicated in-process Light/Dark/System and narrow-window renders, including the requested left alignment. `Scripts/preview.sh` was attempted and still fails its existing missing `Documentation/Screenshots/overview.png` check; it is **not** recorded as passing. Dedicated own-window renders provide the UI evidence. Full VoiceOver/keyboard traversal, composited window appearance, macOS 26 manual integration and the skipped real-provider/native Trash cases remain limits.
- Intermediate failures are excluded: a fixture compared directory URL spelling instead of exact paths; an unsupported SF Symbol produced an empty Inspect hit target; native checks needed an active-window precondition, and repeated uncached folder eligibility work delayed the double-click gesture. The final standard icon/hit area, explicit test activation and correctly invalidated eligibility cache pass without extending timeouts. Reference comparisons and read-only image ejection are recorded in [reference-checks.md](reference-checks.md).

Task 064 is complete. Task 065 is next in the executable queue; no hidden-data residue or Homebrew inventory behavior was added here.

## Owner follow-up for 0.2.4 — 2026-10-21

The owner reported excessive Storage list background height with few results. List surfaces now fit measured content up to the existing 420-point scrolling cap, with exact eager layout for up to 12 results and independent measurements for responsive alternatives. Expanded details contribute to height; empty states retain their readable 220-point content area. Selection, plan and map behavior are unchanged.

Final native Storage checks pass Light/Dark/System on M2/16 GB/macOS 27.0.1 with the generated 1,400-item fixture (bounded observations: 1,300/1,400/1,353). First results take 0.58–0.64 s, warm opening 0.14–0.16 s, maximum main-actor delays 0.13–0.21 s, fixture Trash 0.47–0.49 s and Undo 0.81–1.63 s. Exact parent inspection/analysis, folder Trash/Undo, map/list/selection, keyboard, narrow/empty views and persistence checks pass. Own-process final short-list and long-list renders were inspected.

The checker sends native pointer events directly to its own fixture window, matching its existing keyboard dispatch. Reopening the app bundle could activate another Luma instance; intermediate activation-limited runs are excluded. This does not establish physical desktop pointer/window-manager integration or fully composited appearance. No personal scan, actual Trash or personal-app quit is used.

The standard `Scripts/preview.sh` was also rerun on final source. It repeats the previously recorded missing `overview.png` launch failure; dedicated own-process Storage/Homebrew/Maintenance renders and their native checkers provide the applicable view evidence. This general preview-launcher failure is not counted as a pass.
