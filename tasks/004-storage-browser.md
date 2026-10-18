# 004 — Build a hierarchical storage browser

Status: Planned  
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

- [ ] A user can drill through at least three folder levels and return with breadcrumbs/back navigation.
- [ ] The list and map refer to the same node and coverage; hidden entries, skipped bytes, hard links, and the remainder have documented accounting.
- [ ] A keyboard and VoiceOver user can obtain the same information and actions without using the map.
- [ ] A partial directory is visibly partial; failed reads are not shown as zero-byte folders.
- [ ] Stale nodes require fresh validation before review/mutation, and protected or unauthorized nodes remain non-removable.
- [ ] Existing large-file, age, and installer filters retain clear semantics at the current directory level.

## Validation

Use a disposable nested tree containing hard links, packages, hidden entries, unreadable folders, cloud metadata test doubles, and changed/deleted nodes. Verify totals and navigation state, then perform a fixture-only Trash/Restore round trip. Capture native light/dark, loading, partial, empty, and selected states; record the capture method's limitations.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift).

Spec: sections 46–51, 88, 90, 98, and 108.5/108.12 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect the reference storage explorer's hierarchy, navigation, map/list connection, and item actions at all three checkpoints. Keep Luma's visual design original. Record comparisons in [reference-checks.md](reference-checks.md).

