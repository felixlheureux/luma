# 031 — Expand cache coverage and let users inspect smaller selections

Status: Backlog  
Priority: P2  
Phase: F — Finish everyday cleanup coverage  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [008](008-community-rules.md), [050](050-expanded-cache-discovery.md)

## Why

The first bounded coverage batch now ships earlier in task 050. This task owns deeper child selection and subsequent catalog-based expansion; it must not duplicate or delay that batch.

Whole cache roots are useful starting points, but users need to inspect what is large and choose a smaller supported unit. Broader logs, temporary data, and browser-version coverage also need explicit rules rather than a blanket Library scan.

## Scope

- Add rule-declared child-selection boundaries for supported generated-data roots, with full-root and supported child review. A descendant is not removable merely because it lies inside a matched root.
- Expand bounded user-cache, application-log, temporary-data, and browser-profile rules using current primary documentation and disposable fixtures for each supported layout/version.
- Evaluate exact sandbox-container cache leaves, Electron cache families, application/diagnostic logs, and additional Xcode module/documentation/device-log caches as separate supported batches. Assess system/Darwin/App Store cache permissions and API feasibility without assuming privileged cleanup is available. These categories have compiled reference evidence; individual paths and regeneration still need independent validation.
- Keep rule classification, owner, active-tool guards, ignore policy, and regeneration consequences attached to every child candidate. Unknown data and privacy state stay excluded.
- Make category, parent, and selected-child totals consistent. Reject overlapping operations in the core and revalidate the reviewed tree before mutation.
- Add lazy details/progress without building an unbounded list of every cache file on the main thread.

## Acceptance criteria

- [ ] A user can inspect a supported cache and review a bounded subset without implicitly selecting its parent or siblings.
- [ ] Forged descendants, profile escapes, links, stale children, and classification overrides fail core validation.
- [ ] Each new supported rule has documented provenance, consequences, and positive/negative fixtures; unsupported versions remain visible as unsupported.
- [ ] Temporary-file age alone never permits deleting an unknown or actively used path.

## Validation

Exercise parent/child overlap, hard links, shared owners, privacy leaves, denied reads, active writers, and large trees. Compare selected totals with the accepted core plan and run existing generated-data, ownership, and journal checks.

## Starting points

Task 008's catalog, task 004's hierarchy, [Rules.swift](../Sources/LumaCore/Rules.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), and [ResultsView.swift](../Sources/LumaApp/ResultsView.swift). Spec: sections 10–13, 79–85, and 96–97 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect category depth, granular selection, totals, and explanations before implementation, during the working flow, and at completion. Record evidence in [reference-checks.md](reference-checks.md).

