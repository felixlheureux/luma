# 048 — Show cleanup-session progress, safe stopping, and batch Undo

Status: Done

Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [047](047-provider-aware-filesystem.md)

## Why

The current app tracks individual Trash records, and Cancel targets the scan task. Users need to know which reviewed operation is running, stop before the next move, and recover one cleanup session without reconstructing it from a long Activity list.

## Scope

- Give each reviewed cleanup a stable session/plan ID, visible scope, counts, logical bytes, and a durable relationship to individual intents/outcomes. Migrate existing history without guessing old batch membership.
- Present validating, moving current item, stopping, completed, partially completed, failed, and recovery-needed states. Report moved items separately from unattempted/blocked items and actual physical space changes.
- Track mutation work separately from scan cancellation. Stop cancels preflight safely or stops before the next item; an in-flight native move finishes and its journal outcome is preserved before the app reports a terminal state.
- Add grouped Activity details and Review undo for a selected completed/partial cleanup session. Reconcile interrupted intents first; Undo never means automatically retrying unknown moves.
- Preview eligible, changed, missing, already restored, and occupied-destination items. Restore only the reviewed eligible records through the normal identity/non-overwrite checks, in a documented deterministic order.
- Persist per-item Undo outcomes and support stopping between restores. Show accurate partial results and Finder handoffs without overwriting conflicts, recreating arbitrary parents, or promising an atomic rollback.

## Acceptance criteria

- [x] Stop during preflight moves nothing; Stop after an earlier move accurately retains completed records and leaves subsequent items unattempted.
- [x] Cancellation cannot skip committing/reconciling the outcome of an in-flight move or label a partial cleanup No changes made.
- [x] Sessions remain correctly grouped after restart, and legacy individual records remain usable without invented grouping.
- [x] Undo targets only the chosen session and reviewed eligible items; changed/occupied/missing targets remain untouched with clear reasons.
- [x] Interrupted or partially failed Undo preserves accurate history and can be reviewed later without automatic retry or duplicate restoration.

## Validation

Use injected move/restore checkpoints for Stop before the first move, during a native operation, between items, after partial success, and across restart. Exercise mixed eligible/blocked Undo, changed Trash contents, occupied parents, provider-state changes, missing metadata, and journal-write failures. Use disposable fixtures only and manually review progress/focus in both appearances.

## Starting points

[AppModel.swift](../Sources/LumaApp/AppModel.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [Models.swift](../Sources/LumaCore/Models.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift), and [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift). Spec: sections 2.2, 76, 80, 90, 94, and 108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare progress, stopping, partial completion, grouped history, and Undo/recovery feedback where observable. Never run reference cleanup against personal files for this comparison. Record all three checkpoints in [reference-checks.md](reference-checks.md).


## Implementation and evidence — 2026-10-17

- `CleanupSession.swift` adds durable reviewed sessions, typed progress, immutable Undo eligibility reviews and per-attempt outcomes. Optional version-1 journal fields preserve legacy individual history without inferring membership.
- The journal holds its existing operation lock for complete cleanup/Undo batches. Stop checks preflight and next-item boundaries. Synchronous post-native verification and commits preserve outcomes despite cancellation; failure retains recoverable intents. Used session/review IDs require a fresh review.
- `CleanupSessionModel` owns mutation lifetime independently of scans/review. The shared progress panel shows validating/current-item/stopping states. Activity groups counts, logical totals, blocked/unattempted paths and Undo attempt details. Review Undo shows eligible/changed/missing/restored/occupied/unavailable items and Finder handoffs. Restore uses descending exact UTF-8 path order and the existing identity, parent and exclusive-rename checks.
- All 143 tests in 13 suites pass. Added fixtures cover preflight Stop, cancellation inside native Trash/Restore, mixed eligibility, selected-session isolation, replay rejection, post-review conflicts/provider changes, replaced parents, stopped Undo across restart, legacy history and completion-write failures recovered without retry.
- Debug build and `Scripts/check-cleanup-sessions.sh` pass in light/dark. The actual native Undo sheet attaches, an injected in-flight fixture move finishes after Stop, the session remains partial, remaining items stay untouched, Undo restores the one eligible record, and monitoring/menu remain live. All source files are generated inside a disposable home; real Trash is never invoked by this native check.
- Own-window captures were inspected in both appearances. The Undo sheet exposes eligibility/consequence text. Fallback view capture omits some layer-backed progress/history/button content, so captures do not establish full visual contrast, complete focus/VoiceOver behavior or external reference interaction. Full accessibility review remains task 007; core outcomes and actual sheet attachment are asserted separately.
- Reference checkpoints are recorded in [reference-checks.md](reference-checks.md). Reference evidence remains static resources, not a verified visual/end-to-end commercial cleanup or Undo workflow.

The existing native scan/window/menu regression also passes in both appearances (6,000-file inventory: 1.137s light/1.033s dark; maximum sampled main-actor delay: 0.073s/0.078s). An earlier dark run timed out after 100 seconds; a rebuilt rerun with retained reports completed successfully. These fixture timings are observations on this machine, not general performance guarantees. Undo summary-write failure also has a regression proving a committed restore cannot be mislabeled failed.
