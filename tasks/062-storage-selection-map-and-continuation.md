# 062 — Keep Storage selections visible and browsing consistent

Status: Done
Priority: P1
Depends on: Completed [056](056-storage-discovery.md) and [057](057-icloud-discovery.md); existing direct-action safety from [054](054-direct-uninstall.md)

## Outcome

Storage's Selected view exposes the actual removal targets, Explore's map agrees with its list, and bounded-discovery controls describe the work they can perform. Correct these existing flows without adding another scanner, cleanup review screen or navigation destination.

## Findings

Source review of `c03e185`; these are code findings, not a new native validation result:

- `StorageListing.swift:24,33–34` takes the selected set as its source but still applies the current search and location. Select a file in Downloads, switch to Documents or enter a nonmatching search, then choose Selected: the list can be empty while the footer still authorizes that selected file.
- `StorageView.swift:152–155` divides the list at its first 12 rows after the chosen sort. `StorageIndex.swift:270–278` independently chooses the map's 12 largest items. With Name/Modified sorting, a bubble can represent a collapsed row, and its synthetic remainder can describe a different set from Other items in the list.
- `StorageView.swift:85` labels a new scan Continue bounded discovery. It increases only the entry budget and calls `ensureStorage`; `StorageActions.swift:106–108` starts a fresh traversal, while `StorageIndex.swift:105` resets the same time bound. A time-limited branch can repeatedly produce the same prefix without continuing beyond it.

## Scope

- Make Selected a reliable view of every selected target across folders and modes. Bypass incompatible search, location and hidden-item filters in this view, or explicitly reset them when entering it; do not silently present an empty or incomplete selection. Keep its effective filters and selected count understandable. Changed, ignored, unavailable or otherwise ineligible targets must be reconciled or shown with a reason, rather than remaining invisible actionable IDs. Selection visibility never relaxes current plan, ownership, ignore, provider, identity or duplicate-keeper checks.
- Derive Explore's primary items and remainder from one shared membership decision. The map and list must agree under Size, Name and Modified sorting, including search/filters, equal sizes and zero/unknown sizes. Bubble area still represents the declared size metric; omitted/unknown items remain accessible in the list. A synthetic remainder is never a filesystem target. Focusing or activating a map item reveals its actual row when it would otherwise be collapsed or beyond the display limit; the remainder opens the corresponding list items. Keep keyboard focus, folder navigation and removal selection distinct, with no rescan or whole-page jump to details.
- Make the bounded-discovery action honest. If a small change to the existing scanner can retain a bounded cursor/progress set and visit previously unvisited work, implement and prove that continuation. Otherwise rename it as a fresh scan with a larger entry limit, state that it restarts, and disable or omit a repeat when the relevant bound cannot increase. A time-limit-only result must not offer a misleading entry-limit increase as continuation. Preserve reached useful observations and explicit unknown coverage; do not hide this problem by lengthening timeouts, unbounded traversal or retry loops. No new discovery framework or persistent worker is required.
- Preserve the owner's current startup choice: Storage opens idle, loads only saved observations, and scans only after an explicit action. Keep Scan accessible Mac and the optional custom-folder picker. Do not restore automatic scanning or filesystem watchers. Preserve 057's accepted read-only iCloud metadata behavior, no-download boundary and Finder management handoff.
- Compact footer presentation and outside-click text-field focus belong to task 061. This task changes target visibility and browser/discovery correctness, not that presentation work. Overview restoration is owned separately.

## Acceptance

- [x] Selected shows all selected targets despite prior location/search/hidden filters; its count agrees with the action's captured target set. No invisible selection can authorize an unexpected Trash operation.
- [x] Explore's map, primary rows and Other items describe the same membership under every supported sort/filter. Map focus/remainder activation reveals the matching list content without changing removal selection or restarting discovery.
- [x] The discovery action either demonstrates bounded forward progress into previously unvisited work, or accurately describes a larger fresh scan and becomes unavailable when it cannot increase the relevant bound. Time-limited results cannot trigger a useless continuation loop.
- [x] Cold/warm opening remains idle, requested scans and optional folder selection still work, and cloud observations remain read-only without content materialization.

## Validation and starting points

Add focused generated-data fixtures to the existing Storage listing/discovery tests. Cover selections outside the current location and search, hidden selected paths, mixed folders/files and a selected item becoming ineligible; assert the exact visible and captured target sets. Use more than 12 mixed-size entries with differing names/dates, ties, zeros and unknown sizes; verify primary/remainder membership and that the remainder has no cleanup authority. Use the existing deterministic discovery clock for entry-limited and time-limited branches; measure newly visited paths for genuine continuation, or assert the truthful larger-scan/disabled state. Cancellation must retain useful observations and coverage.

Extend only the affected assertions in `Scripts/check-storage-browser.sh`: Selected with incompatible filters, map-to-collapsed-row focus, Other items under Name/Modified sorting, and the chosen bounded-discovery behavior. Verify the changed controls in Light/Dark/System at ordinary and narrow widths, including keyboard use and continued System monitoring. Use disposable fixtures and the existing injected mover if direct target capture is exercised; never scan personal data or invoke real Trash for QA. Run the meaningful changed checks on the final implementation and record actual outcomes and limits. This task file itself claims no test or native pass.

Start in `StorageListing.swift`, `StorageView.swift`, `StorageActions.swift`, `StorageDiscovery.swift`, `StorageIndex.swift` and the existing Storage discovery/browser tests. Follow [README](README.md) for current queue and reference evidence; earlier automatic-start requirements in 056 are superseded by its owner correction.

## Implementation

- Selected uses the selection as its source and pauses search, location and hidden filters in both browse modes. Controls explain the paused filters. Ineligible retained targets show an inline reason, remain deselectable and block removal; fresh plan/journal checks remain unchanged.
- The worker-prepared `StorageExploreListing` partitions the sorted/filtered rows for both the list and map. Positive primary observations retain their per-path logical area; zero/unknown observations stay accessible in the list. The remainder represents exactly the list's Other items and cannot enter a cleanup plan. Pointer/keyboard map focus expands and reveals corresponding content inside the browser's own scroll area, leaving selection and whole-page position alone.
- Discovery stores optional entry/time/depth bound evidence, requested budget and root count. Only entry-only results with an effective larger per-root budget offer **Rescan with larger entry limit**, with explicit restart wording. Time/depth bounds, capped/complete scans and old saved observations with unknown budgets offer no misleading continuation. Existing 15-second/fair-branch bounds stay unchanged; no cursor, watcher or retry loop is added.
- The Storage header stacks its existing scan/location actions at narrow widths. The detail viewport is explicitly constrained so an ineligible-selection explanation cannot push the action footer beyond the window. Idle opening, optional folder picking, retained observations, central mutation checks and read-only cloud metadata remain intact.

## Validation

Generated-data regressions cover exact visible/captured selection sets across incompatible filters, hidden paths and mixed folders/files; ignored/changed rejection; shared membership for Size/Name/Modified, ties/zeros/unknowns and filters; synthetic remainder rejection; reveal beyond the display bound; deterministic time-bound suppression; effective per-root entry increases, caps, saved metadata and useful observations. Existing cancellation/session, identity/provider/ignore and duplicate-keeper regressions remain in the suite.

Final acceptance on Apple M2/16 GB/macOS 27.0.1: the full Swift suite passes 330 reported tests across 33 suites (five opt-in skips). Native Storage passes Light/Dark/System with 1,217 generated observations: first results 0.528–0.546 s, warm opening 0.093–0.121 s, requested discovery 2.144–2.803 s, maximum sampled main-actor interval 0.060–0.076 s, injected Trash 0.306–0.348 s and Undo 0.313–0.372 s. Exact Selected target capture, incompatible filters/hidden paths, blocked-but-deselectable targets, visible footer geometry, all-sort map membership, actual first-remainder-row visibility, effective larger fresh scans/time-bound suppression, idle cold/warm opening, scope retention, Search keyboard activation, narrow layouts and continued monitoring pass. Only generated data and an injected mover were used; no personal-folder scan, cloud download or real Trash was invoked. Light/Dark/System own-process renders were inspected.

Shared native regressions pass: 60 Overview/input assertions on each fresh/legacy saved-page launch, menu interaction/appearance checks in Light/Dark/System, and close/monitor/reopen/Quit lifecycle. Strict deep debug-bundle signature verification, shell syntax, whitespace and local documentation links pass. Full manual keyboard/VoiceOver, composited glass/chrome, accessibility preference toggles, macOS 26-specific integration and real-home performance remain unverified; fixture timings do not establish real-home scan coverage.

The required standalone `preview.sh` attempt still fails its existing missing `Documentation/Screenshots/overview.png` check; it is not accepted as passing. Dedicated dimension-checked native Storage/Overview renders provide the inspected Light/Dark/System and narrow-window evidence. Task 062 is complete with this existing preview-launcher limit; 063 battery reporting is next.
