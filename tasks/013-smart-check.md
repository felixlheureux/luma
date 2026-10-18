# 013 — Turn Overview into a useful progressive Smart Check

Status: Backlog  
Priority: P2  
Phase: A — More useful space recovery  
Depends on: [003](003-scan-sessions.md), [005](005-application-footprints.md), [008](008-community-rules.md), [010](010-developer-projects.md), [011](011-downloads-review.md)

## Why

Overview currently starts generated-data scanning and inventories applications. A Smart Check should bring together the useful implemented findings and take users directly to an explainable review.

## Scope

- Compose existing scanners and live measurements through scan sessions, with cheap checks first and optional deep checks scoped to folders the user has authorized.
- Report generated-data opportunities, potential leftovers, project output, Downloads review, storage pressure, and meaningful memory/thermal status only when their underlying checks actually ran.
- Give each result a timestamp, scope, evidence, coverage state, and destination. Show unknown, skipped, stale, and cancelled checks distinctly from a good result.
- Deduplicate overlapping findings and distinguish user-data review from generated-data cleanup. Avoid one grand savings number that adds the same bytes twice.
- Make recommendations navigational and explainable. Keep normal review/selection before any mutation; do not create a health score, automatic cleanup, or a recommendation to purge RAM.

## Acceptance criteria

- [ ] Useful results appear progressively without waiting for the deepest selected check.
- [ ] A user can open the exact relevant results from each recommendation, with scope and time intact.
- [ ] An unsupported, unrun, or permission-blocked category cannot appear as checked/healthy.
- [ ] Overlapping caches, app footprints, project results, and Downloads findings do not inflate totals or duplicate operations.
- [ ] Cancellation and replacement retain the session guarantees established by task 003.

## Validation

Use fake scanner streams and measurement providers to cover mixed completion, overlap, denied access, stale results, cancellation, and unavailable metrics. Manually check the scan-to-review path in both appearances and with keyboard navigation.

## Starting points

[OverviewView.swift](../Sources/LumaApp/OverviewView.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ScanSummaryView.swift](../Sources/LumaApp/ScanSummaryView.swift), and task 003's coordinator. Spec: sections 6–7, 71, and 89–90 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare overview progression, recommendations, navigation into findings, and partial results before implementation, at the first working flow, and at completion. Record in [reference-checks.md](reference-checks.md).

