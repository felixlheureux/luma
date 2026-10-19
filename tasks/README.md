# Luma core task queue

Reset on 2026-10-19 after the owner's review of `78acaf5`, then reviewed again at `c03e185`. This is the only executable queue. The [product spec](../Documentation/Product-Spec.md) defines the current scope; completed task records describe earlier implementation, not requirements to recreate its screens. The owner-approved follow-up restores Overview and corrects the core; it does not restart the deleted expansion backlog.

## Platform boundary

Apple Silicon (`arm64`) only on macOS 26+, with M2 as the reference hardware. This applies to every active task, test requirement and release. Intel/x86_64 support, Intel-only maintenance actions, universal builds and Rosetta compatibility are out of scope. Reference-only Intel features below are explicit exclusions, not TODOs or disabled tiles to implement.

## Build the core first

Make the daily actions fast and obvious: uninstall from the app list, select residues and move them to Trash in place, discover large files across the Mac without requiring a folder chooser, support iCloud discovery, fix the menu panel, and provide a small Maintenance view. Restore a concise Overview as the first page. Keep the existing System view and metric set; fix incomplete M2 battery reporting.

| Order | ID | Task | Status | Depends on |
| --- | --- | --- | --- | --- |
| 1 | 054 | [Uninstall directly from the app list](054-direct-uninstall.md) | Done | Existing cleanup engine |
| 2 | 055 | [Show residues automatically and trash them in place](055-residues.md) | Done | 054 |
| 3 | 056 | [Make Storage discover large files across the Mac](056-storage-discovery.md) | Done | 054 (shared action state) |
| 4 | 057 | [Include iCloud files in storage discovery](057-icloud-discovery.md) | Done | 056 |
| 5 | 058 | [Make the menu panel flat and immediately active](058-menu-panel.md) | In progress | 054 (safe termination) |
| 6 | 060 | [Correct app inventory, icons and uninstall eligibility](060-app-inventory-and-uninstall-corrections.md) | Planned | 054, 055 |
| 7 | 061 | [Restore Overview and refine layout and input focus](061-overview-layout-and-input-focus.md) | Planned | 054–057; coordinate routes with 058 |
| 8 | 062 | [Correct Storage selection, map and continuation](062-storage-selection-map-and-continuation.md) | Planned | 056, 057 |
| 9 | 063 | [Correct M2 battery reporting](063-m2-battery-reporting.md) | Planned | Existing monitoring; coordinate menu with 058 |
| 10 | 059 | [Add simple Maintenance actions](059-maintenance.md) | Planned | 054, 055; core corrections first |

Follow this order for a serial runner; dependencies permit independent work. Complete the current menu work and core corrections before adding Maintenance. Mark a task In progress when work starts. Mark it Done only after its behavior and meaningful validation are recorded. Preserve 054–057's implementation evidence; the follow-up defects are tracked in 060–063. This review changes tasks and guidance, not runtime code or a release.

## Interaction rules

- **Apps:** click Uninstall in the row. No mandatory footprint panel, folder selection, review sheet, or acknowledgement checkbox. Optional details must stay optional.
- **Overview:** first primary page and default on a new launch, with concise summaries and links into current core views. No Smart Check or automatic whole-machine scan gate.
- **Residues:** open the view, see existing results while it refreshes, select items or an exact bundle-identifier group, click Move to Trash there. No second screen or confirmation ladder.
- **Storage:** open it without starting a scan. Show saved observations when available; Scan accessible Mac starts broad discovery explicitly. Keep the existing optional folder picker under Locations. Projects and Downloads become filters/locations in Storage, rather than parallel tools asking the same question.
- **Progress:** reserve a compact status area in the current view. No layout jumps, simulated percentages, validation checklist, or progress restart between internal phases. Keep completed results visible during refresh.
- **Approval:** normal local app/residue Trash actions execute directly. Cache cleanup and permanent Trash emptying each have one clear approval, with consequences visible in the initiating view. OS permission prompts remain OS prompts.
- **Safety:** build plans, refresh evidence and use the existing journal internally. A simpler flow does not grant permission to remove shared, unknown, protected, or cloud-managed content.

## Shared UI acceptance

These apply within 054–063, not as a separate framework or expansion task. Fix selection, scope and duplicate-keeper correctness before visual polish within each task:

- Background discovery must not disable unrelated navigation, selection or core actions until an entire scan finishes. Scope read/operation state to the affected feature and coordinate affected reads internally; serialize mutations through the existing owner.
- Selection belongs to a feature and captured scope. Navigation, filtering, unrelated refreshes and late asynchronous callbacks cannot clear another feature's choices, select new items or reopen a dismissed panel. Mutation actions capture immutable intent immediately. Navigation does not cancel an already authorized mutation; its outcome stays attached to its captured source, and Stop remains explicit.
- Keep successful, partial, stopped, failed and recovery-needed outcomes distinct. Scan invalidation cannot replace an operation outcome with Ready or a generic success message. Refresh only affected observations; restore an app's inventory row after confirmed recovery.
- Use one approved route set across sidebar, command menu, global search and Overview links. Primary pages are Overview, Storage, Apps, Residues, Maintenance and System; Activity/Settings are secondary. Start new launches at Overview; reopening the running main window may retain its page. Restore Overview's real route, without its obsolete scan-first workflow. The companion has only Open Luma and Maintenance as primary footer actions, independent of route count. Keep the settings-only Privacy wrapper out of primary navigation.
- Show action availability and a useful reason at the control. An enabled Restore/Quit/settings action must not silently return; users can always deselect an invalid selection. Keep recovery-only review for genuinely unresolved operations, not ordinary cleanup.
- Support narrow main windows through a collapsible sidebar and responsive content. The existing 1010-point minimum must not prevent narrow-window acceptance. Keep an action footer visible and avoid scrolling the whole browser to details on ordinary item focus; details stay optional and local to the browser.
- Display collecting, unavailable and stale observations honestly, including existing System/menu metrics. Failed reads are not measured zero; metric labels must match the sampled value. Keep the System layout and feature scope.
- Indent residue children and align their explanations with the path label, with a clear top gap. Avoid duplicate page headings and repeating common cleanup instructions beneath every row. Keep the Storage footer to its action row and conditional useful status; empty reserved rows must not consume browser space.
- Clicking outside a text input ends editing while preserving its value and delivering the first click to the intended control. Keep native keyboard focus, Tab, Escape and Command-K behavior.

## Follow-up review — c03e185

The owner reported eight issues after 054–057 landed. All are assigned below. These are source-backed findings; actual focus, appearance, layout and M2 measurements still require the owning task's native checks. The owner's later Storage decision (idle opening, explicit Scan, optional folder picker) and 057's owner-reported iCloud acceptance remain authoritative.

| Finding / requested correction | Task | Evidence |
| --- | --- | --- |
| Too many menu footer buttons; retain two clear actions | 058 | [MenuCompanion](../Sources/LumaApp/MenuCompanion.swift) iterates all core destinations |
| Some valid apps cannot uninstall: related-data ID rules gate the bundle; denied optional data or unrelated helpers can abort the action | 060 | [ApplicationActions](../Sources/LumaApp/ApplicationActions.swift), [ApplicationUninstall](../Sources/LumaCore/ApplicationUninstall.swift), [LeftoverScanner](../Sources/LumaCore/LeftoverScanner.swift) |
| Missing logos, changing app membership and vendor companion uninstallers in the ordinary list | 060 | [Scanners](../Sources/LumaCore/Scanners.swift), [ApplicationIcon](../Sources/LumaCore/ApplicationIcon.swift), [AppModel](../Sources/LumaApp/AppModel.swift) |
| Overview removed from routes/startup; residue children unindented and explanations crowded; repeated copy | 061 | [AppModel](../Sources/LumaApp/AppModel.swift), [StorageActions](../Sources/LumaApp/StorageActions.swift), [OverviewView](../Sources/LumaApp/OverviewView.swift), [ApplicationsView](../Sources/LumaApp/ApplicationsView.swift) |
| Click-away text focus has no dismissal policy; Storage footer reserves multiple rows even when idle | 061 | [RootView](../Sources/LumaApp/RootView.swift), [ApplicationsView](../Sources/LumaApp/ApplicationsView.swift), [StorageView](../Sources/LumaApp/StorageView.swift) |
| Selected can hide targets still queued for Trash; map/list Other items differs under sorting; Continue can repeat the same bounded prefix | 062 | [StorageListing](../Sources/LumaCore/StorageListing.swift), [StorageIndex](../Sources/LumaCore/StorageIndex.swift), [StorageView](../Sources/LumaApp/StorageView.swift) |
| Battery grid mostly Unavailable; collector omits available-source investigation and loses power/estimate state distinctions | 063 | [BatteryProvider](../Sources/LumaApp/BatteryProvider.swift), [BatteryDetails](../Sources/LumaCore/BatteryDetails.swift), [MonitoringDetailsView](../Sources/LumaApp/MonitoringDetailsView.swift) |

## Source audit — 44243ef and b67c0b0

Code review on 2026-10-19 found these concrete paths before 054–057 implementation. This is historical source evidence, not native reproduction or a new queue. Later owner decisions and completion evidence in 056–057 supersede earlier automatic-start assumptions: Storage opens idle and scans explicitly. macOS focus, scroll and layout still need the relevant task's native checks.

| Finding | Owning task | Source |
| --- | --- | --- |
| Global scan busy/selection clearing blocks unrelated actions; broad mutation invalidation blanks unrelated state | 054, 055, 056 | [AppModel](../Sources/LumaApp/AppModel.swift), [ResultsView](../Sources/LumaApp/ResultsView.swift) |
| Duplicate keeper completion can repopulate another view's selection after navigation | 054, 056 | [DuplicateReviewActions](../Sources/LumaApp/DuplicateReviewActions.swift) |
| Known duplicate members lose keeper evidence when selected through Storage | 056 | [StorageIndex](../Sources/LumaCore/StorageIndex.swift), [reviewStorage](../Sources/LumaApp/AppModel.swift) |
| Retained A results can be labeled as requested scope B; later hard-link paths display/filter as zero bytes | 056 | [AppModel](../Sources/LumaApp/AppModel.swift), [StorageIndex](../Sources/LumaCore/StorageIndex.swift) |
| Restored apps stay absent from Installed; failed/stopped outcomes are overwritten; Restore/Undo eligibility is inconsistent | 054 | [AppModel](../Sources/LumaApp/AppModel.swift), [Activity UI](../Sources/LumaApp/CleanupSessionViews.swift) |
| Residue actions sit after the long list; global Search does not search installed apps; obsolete routes are duplicated | 055, 056, 058 | [ApplicationsView](../Sources/LumaApp/ApplicationsView.swift), [RootView](../Sources/LumaApp/RootView.swift), [LumaApp](../Sources/LumaApp/LumaApp.swift) |
| Quit/last-window close can interrupt a mutation; Navigate commands do not reopen the closed main window | 054, 058 | [LumaApp](../Sources/LumaApp/LumaApp.swift), [MenuCompanion](../Sources/LumaApp/MenuCompanion.swift) |
| Ignored descendants can enter Trash through a selected parent; same-ID app copies do not establish exclusive related-data ownership | 054, 056 | [SafetyEngine](../Sources/LumaCore/SafetyEngine.swift), [ApplicationRelationships](../Sources/LumaCore/ApplicationRelationships.swift) |
| Automatic whole-Mac discovery must replace picker-only local action authority and avoid index-write refresh loops; old-volume events must not cancel a new scope | 056 | [StorageScope](../Sources/LumaCore/StorageVolumes.swift), [AppModel](../Sources/LumaApp/AppModel.swift), [AnalysisEvents](../Sources/LumaCore/AnalysisEvents.swift) |
| Live Quit rows need instance verification/outcomes; ignored cache summaries disagree; missing measurements render numeric zeros | 058, 059 | [MonitorViews](../Sources/LumaApp/MonitorViews.swift), [ScanSummaryView](../Sources/LumaApp/ScanSummaryView.swift), [SystemMonitor](../Sources/LumaApp/SystemMonitor.swift) |

## Deleted work

The unstarted expansion tasks **018–046, 049, and 051–053** and their follow-up queues/coverage inventories have been deleted, not archived. Basic cache cleanup, Trash emptying and measured memory help are included only in 059. There is no parallel monitoring track, formatter/refactor prerequisite, or automatic next expansion queue.

Do not recreate tasks for privacy suites, photos, Mail, app update discovery, diagnostics, startup items, extra ecosystems, scheduling, binary thinning, or similar expansion. New features require the owner to approve them after the core below is accepted. Fixes to unfinished work belong in that task; 060–063 are the owner's requested corrections to completed core work, not a second feature backlog.

## Core acceptance

Before proposing more features, demonstrate the core flows and corrections on native Apple Silicon macOS (M2 reference) with synthetic data: direct app uninstall, in-place residue cleanup, idle cold/warm Storage opening and requested discovery, iCloud local/online-only/missing-permission states, flat focused two-action menu, concise Overview and approved maintenance. Verify stable app inventory/icons, visible selected Storage targets, map/list agreement, compact layouts and click-away focus. Compare battery readings on the actual M2 with Battery Settings/System Information; fixture success alone cannot establish hardware support. Check Light/Dark/System appearance, keyboard access, narrow layouts, navigation during work, and continued System monitoring. Record first-results, warm-open and operation timings with fixture size and hardware; do not hide slow work behind a longer timeout or retry loop.

Keep the existing central safety, ownership, identity, provider and recovery regression coverage. Replace obsolete native QA assertions that demand the removed sheets with assertions for the new direct flows. Run checks appropriate to changed behavior once on the final candidate; repeat only after a relevant change or failure. Planning-only edits require link/status/diff checks, not the macOS app suite.

## References and evidence

For implementation, continue the owner's relevant before/during/completion comparisons with reference DMGs in Downloads. Use the reference to simplify an interaction, not to import every commercial feature. Mount read-only, use disposable test data, eject afterward, and state inspection limits in [reference-checks.md](reference-checks.md). An unavailable reference is a reported limit, not evidence of a comparison.

Completed tasks **001–006, 008–017, 047, 048, 050** remain implementation records. **007** remains closed with release checks deferred. Their earlier sheet, manual-scan, and provider-exclusion UX is superseded by 054–063; core execution safeguards remain. No version bump, tag, signed updater or packaging expansion is part of this reset.
