# Luma core task queue

Reset on 2026-10-19 after the owner's review of `78acaf5`. This is the only executable queue. The [product spec](../Documentation/Product-Spec.md) defines the current scope; completed task records describe earlier implementation, not requirements to recreate its screens.

## Platform boundary

Apple Silicon (`arm64`) only on macOS 26+, with M2 as the reference hardware. This applies to every active task, test requirement and release. Intel/x86_64 support, Intel-only maintenance actions, universal builds and Rosetta compatibility are out of scope. Reference-only Intel features below are explicit exclusions, not TODOs or disabled tiles to implement.

## Build the core first

Make the daily actions fast and obvious: uninstall from the app list, select residues and move them to Trash in place, discover large files across the Mac without choosing folders, support iCloud discovery, fix the menu panel, and provide a small Maintenance view. Keep the existing System view and metrics.

| Order | ID | Task | Status | Depends on |
| --- | --- | --- | --- | --- |
| 1 | 054 | [Uninstall directly from the app list](054-direct-uninstall.md) | Ready | Existing cleanup engine |
| 2 | 055 | [Show residues automatically and trash them in place](055-residues.md) | Planned | 054 |
| 3 | 056 | [Make Storage discover large files across the Mac](056-storage-discovery.md) | Planned | 054 (shared action state) |
| 4 | 057 | [Include iCloud files in storage discovery](057-icloud-discovery.md) | Planned | 056 |
| 5 | 058 | [Make the menu panel flat and immediately active](058-menu-panel.md) | Planned | 054 (safe termination) |
| 6 | 059 | [Add simple Maintenance actions](059-maintenance.md) | Planned | 054, 055 |

Follow this order for a serial runner; dependencies permit independent work. Mark a task In progress when work starts. Mark it Done only after its behavior and meaningful validation are recorded. This planning reset implements no app features and does not publish a release.

## Interaction rules

- **Apps:** click Uninstall in the row. No mandatory footprint panel, folder selection, review sheet, or acknowledgement checkbox. Optional details must stay optional.
- **Residues:** open the view, see existing results while it refreshes, select items or an exact bundle-identifier group, click Move to Trash there. No second screen or confirmation ladder.
- **Storage:** open it and see large files and folders across accessible Mac storage. No folder picker or Scan button is required for the default flow. Projects and Downloads become filters/locations in Storage, rather than parallel tools asking the same question.
- **Progress:** reserve a compact status area in the current view. No layout jumps, simulated percentages, validation checklist, or progress restart between internal phases. Keep completed results visible during refresh.
- **Approval:** normal local app/residue Trash actions execute directly. Cache cleanup and permanent Trash emptying each have one clear approval, with consequences visible in the initiating view. OS permission prompts remain OS prompts.
- **Safety:** build plans, refresh evidence and use the existing journal internally. A simpler flow does not grant permission to remove shared, unknown, protected, or cloud-managed content.

## Shared UI acceptance

These apply within 054–059, not as a separate framework or expansion task. Fix selection, scope and duplicate-keeper correctness before visual polish within each task:

- Background discovery must not disable unrelated navigation, selection or core actions until an entire scan finishes. Scope read/operation state to the affected feature and coordinate affected reads internally; serialize mutations through the existing owner.
- Selection belongs to a feature and captured scope. Navigation, filtering, unrelated refreshes and late asynchronous callbacks cannot clear another feature's choices, select new items or reopen a dismissed panel. Mutation actions capture immutable intent immediately. Navigation does not cancel an already authorized mutation; its outcome stays attached to its captured source, and Stop remains explicit.
- Keep successful, partial, stopped, failed and recovery-needed outcomes distinct. Scan invalidation cannot replace an operation outcome with Ready or a generic success message. Refresh only affected observations; restore an app's inventory row after confirmed recovery.
- Use one approved route set across sidebar, command menu, global search, Overview links and menu companion. Primary pages are Storage, Apps, Residues, Maintenance and System; Activity/Settings are secondary. Open the last valid core page, or Storage on first launch. Remove the scan-first Overview and settings-only Privacy wrapper from primary navigation.
- Show action availability and a useful reason at the control. An enabled Restore/Quit/settings action must not silently return; users can always deselect an invalid selection. Keep recovery-only review for genuinely unresolved operations, not ordinary cleanup.
- Support narrow main windows through a collapsible sidebar and responsive content. The existing 1010-point minimum must not prevent narrow-window acceptance. Keep an action footer visible and avoid scrolling the whole browser to details on ordinary item focus; details stay optional and local to the browser.
- Display collecting, unavailable and stale observations honestly, including existing System/menu metrics. Failed reads are not measured zero; metric labels must match the sampled value. Keep the System layout and feature scope.

## Source audit — 44243ef

Code review on 2026-10-19 found these concrete paths. This is source evidence, not native reproduction; macOS focus, scroll and layout still need the relevant task's native checks.

| Finding | Owning task | Source |
| --- | --- | --- |
| Global scan busy/selection clearing blocks unrelated actions; broad mutation invalidation blanks unrelated state | 054, 055, 056 | [AppModel](../Sources/LumaApp/AppModel.swift), [ResultsView](../Sources/LumaApp/ResultsView.swift) |
| Duplicate keeper completion can repopulate another view's selection after navigation | 054, 056 | [DuplicateReviewActions](../Sources/LumaApp/DuplicateReviewActions.swift) |
| Known duplicate members lose keeper evidence when selected through Storage | 056 | [StorageIndex](../Sources/LumaCore/StorageIndex.swift), [reviewStorage](../Sources/LumaApp/AppModel.swift) |
| Retained A results can be labeled as requested scope B; later hard-link paths display/filter as zero bytes | 056 | [AppModel](../Sources/LumaApp/AppModel.swift), [StorageIndex](../Sources/LumaCore/StorageIndex.swift) |
| Restored apps stay absent from Installed; failed/stopped outcomes are overwritten; Restore/Undo eligibility is inconsistent | 054 | [AppModel](../Sources/LumaApp/AppModel.swift), [Activity UI](../Sources/LumaApp/CleanupSessionViews.swift) |
| Residue actions sit after the long list; global Search does not search installed apps; obsolete routes are duplicated | 055, 056, 058 | [ApplicationsView](../Sources/LumaApp/ApplicationsView.swift), [RootView](../Sources/LumaApp/RootView.swift), [LumaApp](../Sources/LumaApp/LumaApp.swift) |
| Quit/last-window close can interrupt a mutation; Navigate commands do not reopen the closed main window | 054, 058 | [LumaApp](../Sources/LumaApp/LumaApp.swift), [MenuCompanion](../Sources/LumaApp/MenuCompanion.swift) |
| Live Quit rows need instance verification/outcomes; ignored cache summaries disagree; missing measurements render numeric zeros | 058, 059 | [MonitorViews](../Sources/LumaApp/MonitorViews.swift), [ScanSummaryView](../Sources/LumaApp/ScanSummaryView.swift), [SystemMonitor](../Sources/LumaApp/SystemMonitor.swift) |

## Deleted work

The unstarted expansion tasks **018–046, 049, and 051–053** and their follow-up queues/coverage inventories have been deleted, not archived. Basic cache cleanup, Trash emptying and measured memory help are included only in 059. There is no parallel monitoring track, formatter/refactor prerequisite, or automatic next expansion queue.

Do not recreate tasks for privacy suites, photos, Mail, app update discovery, diagnostics, startup items, extra ecosystems, scheduling, binary thinning, or similar expansion. New work requires the owner to approve it after the core below is accepted. Fixes necessary to meet a current task belong in that task.

## Core acceptance

Before proposing more features, demonstrate all six completed flows on native Apple Silicon macOS (M2 reference) with synthetic data: direct app uninstall, in-place residue cleanup, automatic cold/warm discovery, iCloud local/online-only/missing-permission states, flat focused menu, and approved maintenance. Check Light/Dark/System appearance, keyboard access, narrow layouts, navigation during work, and continued System monitoring. Record first-results, warm-open and operation timings with fixture size and hardware; do not hide slow work behind a longer timeout or retry loop.

Keep the existing central safety, ownership, identity, provider and recovery regression coverage. Replace obsolete native QA assertions that demand the removed sheets with assertions for the new direct flows. Run checks appropriate to changed behavior once on the final candidate; repeat only after a relevant change or failure. Planning-only edits require link/status/diff checks, not the macOS app suite.

## References and evidence

For implementation, continue the owner's relevant before/during/completion comparisons with reference DMGs in Downloads. Use the reference to simplify an interaction, not to import every commercial feature. Mount read-only, use disposable test data, eject afterward, and state inspection limits in [reference-checks.md](reference-checks.md). An unavailable reference is a reported limit, not evidence of a comparison.

Completed tasks **001–006, 008–017, 047, 048, 050** remain implementation records. **007** remains closed with release checks deferred. Their earlier sheet, manual-scan, and provider-exclusion UX is superseded by 054–059; core execution safeguards remain. No version bump, tag, signed updater or packaging expansion is part of this reset.
