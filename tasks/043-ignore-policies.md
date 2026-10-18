# 043 — Extend visible ignore policies across the product

Status: Backlog  
Priority: P2  
Phase: Cross-cutting — Consistent user control  
Depends on: [001](001-cleanup-plans.md), [008](008-community-rules.md), [014](014-incremental-index.md), [015](015-duplicate-review.md), [016](016-volume-analysis.md)

## Why

Path ignores already exist, but the mature product also needs app, rule, volume, duplicate-group, and project exclusions. Every scanner, recommendation, and mutation must respect the same visible policy.

## Scope

- Add a versioned project-owned policy model for exact files/folders, applications, rules, volumes, project roots, and scoped duplicate-group exclusions. Preserve existing path-ignore behavior during migration.
- Define matching and scope clearly: path-component boundaries, descendants, app/rule IDs, verified volume identity, and explicit group semantics. Avoid unrestricted globs or persistent assumptions based only on a reused inode/mount path.
- Provide visible, reversible controls in Settings and relevant review surfaces, with a preview of what an exclusion affects. Removing an ignore does not silently select newly visible items.
- Apply exclusions consistently to scans, cached results, Smart Check, scheduled checks, review totals, and final core validation. Changing policy invalidates affected reviewed plans and cached summaries.
- Preserve user choices across upgrades and localization without using display names as policy identifiers.

## Acceptance criteria

- [ ] Every supported exclusion type has deterministic matching and visible scope, with safe handling of renamed/replaced roots or unavailable volumes.
- [ ] Legacy path ignores migrate without losing exclusions or broadening them unexpectedly.
- [ ] New/replaced scan results and stale cached recommendations cannot bypass a current ignore policy.
- [ ] A direct core mutation request for an ignored target is rejected even if the UI previously allowed it.

## Validation

Use policy fixtures for prefix collisions, descendants, duplicate membership changes, app copies, volume replacement, rule migration, and policy changes after review. Verify persistence and Settings behavior with no real cleanup.

## Starting points

[AppModel.swift](../Sources/LumaApp/AppModel.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift), and task 014's invalidation boundary. Spec: sections 72, 80, 87, and 94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare ignore categories, scope explanations, reversing an exclusion, and how results update. Log the three required checkpoints in [reference-checks.md](reference-checks.md).

