# 004 — Build a hierarchical storage browser

> Core reset, 2026-10-19: 056 replaces the folder-first entry and mandatory storage review UI; core storage safety remains. See [the current queue](README.md). This file retains earlier implementation evidence.

Status: Done

Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [047](047-provider-aware-filesystem.md)

## Why

The current Storage screen sizes immediate children and reveals map items in Finder. A large folder is still a dead end. The next visible feature should let users follow space into that folder and understand its contents.

## Scope

- Add a transient, hierarchical storage model separate from `CleanupItem`. Browsing a node must not automatically make it eligible for removal.
- Provide folder drill-down, breadcrumbs, back navigation, size/name sorting, a hidden-item control, and synchronized list/map selection. Directory activation navigates; Finder reveal remains a separate action.
- Build/cache enough metadata to avoid rescanning the entire root on every navigation. Surface partial sizes, unreadable children, and inspection limits. Measure this approach before introducing a database.
- Represent map coverage honestly. If only the largest items are drawn, show an aggregate remainder and its meaning rather than presenting that subset as the whole folder. Synthetic remainder nodes are not cleanup items.
- Add a details surface with path, type, logical size, dates when available, coverage, Reveal, Copy Path, and Open where appropriate. Keep packages as leaves and avoid downloading cloud placeholders.
- Keep removal inside the current authorized home-folder/volume boundary. Use task 001 plans and task 002 checks for explicit manual selections; protected roots stay protected. Changing the current directory or root clears its selection so hidden selections cannot enter review.

## Acceptance criteria

- [x] A user can drill through at least three folder levels and return with breadcrumbs/back navigation.
- [x] The list and map refer to the same node and coverage; hidden entries, skipped bytes, hard links, and the remainder have documented accounting.
- [x] A keyboard and VoiceOver user can obtain the same information and actions without using the map.
- [x] A partial directory is visibly partial; failed reads are not shown as zero-byte folders.
- [x] Stale nodes require fresh validation before review/mutation, and protected or unauthorized nodes remain non-removable.
- [x] Existing large-file, age, and installer filters retain clear semantics at the current directory level.

## Validation

Use a disposable nested tree containing hard links, packages, hidden entries, unreadable folders, cloud metadata test doubles, and changed/deleted nodes. Verify totals and navigation state, then perform a fixture-only Trash/Restore round trip. Capture native light/dark, loading, partial, empty, and selected states; record the capture method's limitations.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift).

Spec: sections 46–51, 88, 90, 98, and 108.5/108.12 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect the reference storage explorer's hierarchy, navigation, map/list connection, and item actions at all three checkpoints. Keep Luma's visual design original. Record comparisons in [reference-checks.md](reference-checks.md).


## Implementation and evidence — 2026-10-18

- `StorageIndex` performs a transient bounded hierarchy scan through the shared provider policy and no-materialization scope. Normal folders cache children; packages remain leaves. The index limits stored nodes to 100,000 and hierarchy depth to 128; package inspection retains the existing bounded filesystem inspection. Cancelled scans never publish an index. Navigation reads the completed index without filesystem access.
- Native Storage provides directory activation, Back, breadcrumbs, size/name sorting, hidden controls, current-directory filters and pagination. Map/list inspection shares focused node state; details show path, type, logical size, available dates and coverage with Reveal, Copy Path and folder Open. List controls expose the same information/actions without the decorative map. Labels identify row type, size/partial state and action. Full VoiceOver traversal remains part of task 007’s accessibility review; no automated screen-reader session is claimed here.
- Hidden content is indexed and contributes to parent size even when hidden rows are excluded. Every regular inode contributes once at the first path in exact UTF-8 traversal order across the root, including package contents; another hard-link path can therefore show zero contribution. Map weights use precisely the filtered list, with a synthetic aggregate for positive-sized entries beyond the largest twelve. Zero/unknown entries remain in the list. Skipped bytes are unknown, and partial folders show “at least” with the reason rather than claiming empty coverage.
- Directory/root/filter/hidden changes clear removal selection as appropriate. The complete current-directory selection captures fresh object/tree/location evidence off the main actor and enters ordinary core plans. Partial, stale, changed/deleted, ignored, protected and unauthorized selections are rejected or disabled; execution preserves SafetyEngine and journal validation. Any cleanup/Restore outcome invalidates the cached index. A changed descendant is fully reinspected before review, and the review sheet shows the freshly verified size.
- `bash Scripts/test.sh`: 150 tests in 14 suites pass. Seven storage tests cover three-level hierarchy, hidden and package behavior, cross-branch hard links, remainder totals, unknown/provider/unreadable nodes, bounded traversal, links, cancellation, stale/deleted selections, current-directory membership, scope checks, and a generated-fixture journal Trash/Restore round trip preserving adjacent content.
- Debug app builds successfully. `bash Scripts/check-storage-browser.sh` passes in light/dark using 1,030 generated nodes: partial/provider coverage, matching remainder totals, no initial selection, actual review sheet, three-level cached navigation with selection clearing, breadcrumbs/back, complete empty directory, stale review rejection and monitoring. Measured index durations on this machine were about 1.6–1.8 seconds; these are fixture observations, not a universal performance guarantee or a persistent-index benchmark.
- Existing `bash Scripts/check-scan-sessions.sh` passes both appearances, including cancellation, permission retry, provider exclusions, Settings, window close/reopen and menu/monitor continuity. The 6,000-file inventory took 0.994/1.028 seconds with maximum sampled main-actor heartbeat delays of 0.083/0.080 seconds. No personal cleanup was invoked.
- Own-window captures of loading, partial, empty and selected states were inspected. Dark selected captures show the list focus, details and action labels; explicit appearance-aware controls corrected dark label contrast. Scrolling now returns to the top on navigation and brings focused details into view. Fallback capture intermittently omits native/layer-backed content (one light selected capture is blank); images do not establish full keyboard/VoiceOver behavior. Synthetic reports/captures remain temporary and untracked.
- Reference checkpoints and the existing runtime inspection limits are recorded in [reference-checks.md](reference-checks.md). No proprietary assets/code were copied. Persistent indexing, volume expansion and full milestone accessibility review remain tasks 014, 016 and 007.
