# 013 — Turn Overview into a useful progressive Smart Check

Status: Done
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

- [x] Useful results appear progressively without waiting for the deepest selected check.
- [x] A user can open the exact relevant results from each recommendation, with scope and time intact.
- [x] An unsupported, unrun, or permission-blocked category cannot appear as checked/healthy.
- [x] Overlapping caches, app footprints, project results, and Downloads findings do not inflate totals or duplicate operations.
- [x] Cancellation and replacement retain the session guarantees established by task 003.

## Validation

Use fake scanner streams and measurement providers to cover mixed completion, overlap, denied access, stale results, cancellation, and unavailable metrics. Manually check the scan-to-review path in both appearances and with keyboard navigation.

## Starting points

[OverviewView.swift](../Sources/LumaApp/OverviewView.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ScanSummaryView.swift](../Sources/LumaApp/ScanSummaryView.swift), and task 003's coordinator. Spec: sections 6–7, 71, and 89–90 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare overview progression, recommendations, navigation into findings, and partial results before implementation, at the first working flow, and at completion. Record in [reference-checks.md](reference-checks.md).


## Implementation evidence — 2026-10-18

- `SmartCheck` composes existing generated-data, application inventory and leftover scanners sequentially through one ScanController worker. Optional projects/Downloads use explicitly selected roots captured with the request and retained on retry. Storage capacity, memory pressure and thermals use the timestamped monitoring sample; unavailable readings remain explicit. Application footprints, backup integrity, security, updates and similar photos are not silently counted as checked.
- A bounded completed-subcheck event publishes immutable feature snapshots progressively; partial previews still have no review authority. A failed subcheck records failure and later categories continue. Cancellation/replacement keep already committed results, reject late events and hold the worker slot until exit. A completion callback can cancel without reviving the worker.
- Overview shows per-category scope, completion time, evidence, coverage/failure/skipped/stale state and a native button to the exact feature snapshot. Invalidated/replaced snapshots cannot be opened from an old recommendation. Ordinary explicit selection and confirmation remain required. The summary has no aggregate candidates or savings total; overlapping categories cannot create combined duplicate operations, and ordinary mutation invalidation drops affected feature snapshots.
- Nine new core fixtures cover mixed completion, denied access, stale/unrun results, optional authorization/ignore capture, overlap, cancellation, replacement, callback cancellation and rejection of unauthorized subcheck scopes. All 229 Swift tests in 21 suites pass.
- `Scripts/check-smart-check.sh` exercises actual progressive publication, failed-category isolation, scope/time-preserving navigation, no initial selection, the normal confirmation sheet, invalidation, unavailable measurements and monitoring in light/dark with disposable fixtures. It never invokes cleanup or scans personal folders. Own captures are temporary. A basic Tab-event/first-responder check is automated; full keyboard traversal, VoiceOver and the system folder chooser remain manual accessibility limitations rather than claimed validation.
- Reference comparison and its resource-only limits are recorded in `reference-checks.md`. No reference runtime workflow or undocumented safety behavior is inferred.
