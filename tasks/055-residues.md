# 055 — Show residues automatically and trash them in place

Status: Done
Priority: P0  
Depends on: [054](054-direct-uninstall.md)

## Outcome

Open Residues, see what is available, select items and click Move to Trash in that view. No manual scan prerequisite, second panel or acknowledgement ladder.

## Scope

- Start one bounded ownership/residue refresh automatically on first entry, sharing application inventory with Apps. Persist bounded timestamped display observations so reopening/relaunching shows prior findings immediately while refreshing. The existing Storage/Duplicates hash cache does not supply this behavior.
- Publish completed per-item observations in coalesced batches without waiting for all Library roots. Distinguish loading, empty, refreshing, partial coverage and permission denial. Keep useful previous results visible; no repeated scans when switching tabs and no false clean state while discovery is incomplete.
- Separate read-only saved/partial observations from executable evidence. Selection captures exact items; obtain fresh ownership/identity evidence internally through 054's direct action path. Do not require the user to run Scan again. A reinstalled owner invalidates that item and gives one inline explanation.
- Group residues by the exact full owning bundle identifier, for example `com.vendor.app`, using the existing `LeftoverGroup`/ownership resolver. Show that identifier as the group title, plus item count and unique logical total. Similar identifiers such as `com.vendor.app2` remain separate; a shared `com.vendor` prefix is not ownership evidence. Unresolved owners are explicitly separate and never gain cleanup eligibility from grouping.
- Each group header has an accessible three-state checkbox (none, some, all). Selecting it selects all currently known eligible children of that exact group, including collapsed/offscreen rows; deselecting clears them. Child checkboxes update the group state. Filtering finds groups without silently changing the selected set; the action summary includes selected hidden groups. Refresh arrivals do not inherit an earlier group selection. No automatic initial selection.
- Keep a fixed in-view selection/action footer visible while the residue list scrolls; selecting an early group must not require scrolling past every other group to reach Move to Trash.
- Provide inline paths, ownership explanation and removal consequences. Initial selection is empty. Row/group selection and Move to Trash live together; only the selected items are authorized. No ReviewSheet, extra checkbox or navigation transition follows.
- Preserve filters, scroll, unaffected findings and valid remaining selection after a subset succeeds. Show stable compact pending/outcome feedback, durable partial results and optional Activity/Undo. Failure never broadens selection or silently retries. Background scans and cleanup in unrelated features cannot clear this feature's selections; dirty only affected identifiers/roots after an actual outcome.
- Bound refresh work and invalidation after app install/uninstall, cleanup and restore. Refresh changed supported roots instead of repeating unrelated full application sizing. Do not create a general background daemon or scheduler.

## Acceptance

- [x] First entry automatically discovers residues; later opens and relaunches show saved findings before background work completes.
- [x] Exact bundle-identifier groups have count/size and selectable headers; mixed child selection, collapse, scrolling, filtering and refresh preserve a predictable selected set without prefix-based owner merges.
- [x] Selected local residues or whole groups move to Trash through a fixed visible footer, with one action from the list and no second view, long scroll or confirmation.
- [x] Stale observations, installed/embedded owners, shared/Apple data, links, provider paths and unreadable roots remain correctly protected; incomplete coverage is visible.
- [x] Reopening, refreshing and partial cleanup do not blank, jump or reset the list; display observations never bypass current core checks.

## Validation and starting points

Use synthetic home/app roots, injected ownership observations and a controllable scan clock. Check cold/warm entry, cancellation/replacement, late events, reinstall races, subset failure and relaunch. Cover group select/deselect, mixed state, similar identifier prefixes, collapsed/offscreen children, filtered selected groups, unknown owners and new children arriving after selection. Replace sheet-centric residue QA with direct-flow checks and retain ownership/journal regression tests. Record first-results, warm-open and selection-to-outcome timings with fixture size.

Start in `ApplicationsView.swift` (`LeftoversView`), `ResultsView.swift`, `AppModel.swift`, `LeftoverScanner.swift`, `ApplicationRelationships.swift`, `ScanController` and 054's direct-action state. Follow [README](README.md) for native/reference evidence.


## Implementation — 2026-10-19

- Independent automatic residue discovery uses `ScanController`'s coalescing mailbox. Saved/partial observations stay visible while current ownership refreshes. Metadata-only owner inventory shares pending application rows with Apps without recursive bundle sizing. Known changed owner identifiers use bounded subset refresh; no background scheduler was added.
- A bounded local observation store keeps up to 4,000 timestamped display items and 8 MiB. It is separate from executable snapshots and the Storage/hash cache. Failed/stopped refreshes retain inspected observations with explicit incomplete coverage. A full refresh clears old coverage only after current inspection finishes.
- Exact identifier groups expose native accessible none/some/all checkboxes, collapse, path filtering and unique logical content totals. Selection captures children individually, includes hidden groups, survives navigation/unrelated work and never expands to new arrivals. Changed or disappeared items lose their old selection after refresh. Unresolved owners stay ineligible.
- The fixed footer executes selected-residue Trash directly, with stable progress/outcome, Stop, Activity and Undo. Preparation refreshes captured identity evidence; journal preflight and final checks still enforce current installed/embedded owners, ignore, protected-path, provider and parent-chain policy. Failed preparation refreshes affected observations without retrying a mutation. Confirmed moves remove only affected rows; Undo refreshes restored observations.
- Global search includes known installed applications and opens the filtered app list. The shared primary-route consolidation remains part of the remaining core navigation work; this task exposes Residues in the existing Applications browser.

## Validation

- `bash Scripts/test.sh`: **298 tests in 30 suites passed**. Six new observation fixtures cover saved/relaunch data, corrupt cache handling, fresh selected evidence, changed/ignored/personal paths, exact prefix separation, hard-link totals, owner-scoped refresh and shared pending app metadata. Existing ownership/reinstall/embedded-helper, provider, symlink, protected-path, stale identity and journal partial/Stop/recovery tests remain passing.
- Updated the residue native checker from review-sheet assertions to automatic entry and direct actions. Final Light/Dark/System runs pass cold/warm entry, empty initial selection, group all/mixed/none, unselected new arrivals, navigation, a 760×650 window, live journal detail, retained observations, saved findings during a delayed refresh, second direct action without a scan prerequisite, Undo/rediscovery and continued monitoring. Fixtures contain three initial residue roots under two identifiers, 54 bytes of residue content, and one synthetic installed app/icon. All moves use an injected mover into a disposable fixture Trash; no real Trash or personal-folder scan is invoked.
- Final fixture timings (Light/Dark/System): cold results 0.134/0.135/0.132 s; warm saved-observation reads 0.00347/0.00378/0.00349 s; selection-to-outcome 3.794/3.486/3.442 s. Operation timings include a deliberate move gate, screenshot and 400 ms observation delay; they are not native Trash latency claims. Hardware/OS and remaining native regression results are recorded below.
- Visually inspected Light/Dark residue captures, including the narrow mixed-selection state and fixed footer. Actual pointer interaction with collapsed/offscreen/filtered groups, full manual keyboard/VoiceOver traversal, TCC permission changes, real Trash, and external installation notifications remain unverified. Source/core selection checks cover filtering and exact grouping; synthetic API-driven native checks do not establish those manual interactions.
- The first native Light run found a missing journal detail callback. It was fixed before the accepted three-appearance run; that failed run is not counted as passing evidence.

- Hardware: Apple M2, arm64; macOS 27.0.1 (26A434). The supported deployment minimum remains macOS 26; this run is not validation on every supported OS version.
- Existing native Stop/Undo regressions pass in Light/Dark. Application optional-footprint/reset and direct uninstall/Undo checks pass in Light/Dark/System, including the updated observation-retaining invalidation expectation. Native scan lifecycle checks pass in Light/Dark with 6,000 synthetic files (1.362/1.296 s inventory; maximum sampled main-actor delay 0.390/0.342 s). No repeated whole-app sizing was added to residue refresh.

- `bash Scripts/preview.sh` passes on the final candidate; strict deep debug-bundle signature verification and `git diff --check` pass. Reference before/working/completion comparisons and inspection limits are recorded in [reference-checks.md](reference-checks.md). No version bump, release or packaging changes were made.
