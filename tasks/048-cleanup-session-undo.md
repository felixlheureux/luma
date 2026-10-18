# 048 — Show cleanup-session progress, safe stopping, and batch Undo

Status: Ready

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

- [ ] Stop during preflight moves nothing; Stop after an earlier move accurately retains completed records and leaves subsequent items unattempted.
- [ ] Cancellation cannot skip committing/reconciling the outcome of an in-flight move or label a partial cleanup No changes made.
- [ ] Sessions remain correctly grouped after restart, and legacy individual records remain usable without invented grouping.
- [ ] Undo targets only the chosen session and reviewed eligible items; changed/occupied/missing targets remain untouched with clear reasons.
- [ ] Interrupted or partially failed Undo preserves accurate history and can be reviewed later without automatic retry or duplicate restoration.

## Validation

Use injected move/restore checkpoints for Stop before the first move, during a native operation, between items, after partial success, and across restart. Exercise mixed eligible/blocked Undo, changed Trash contents, occupied parents, provider-state changes, missing metadata, and journal-write failures. Use disposable fixtures only and manually review progress/focus in both appearances.

## Starting points

[AppModel.swift](../Sources/LumaApp/AppModel.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [Models.swift](../Sources/LumaCore/Models.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift), and [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift). Spec: sections 2.2, 76, 80, 90, 94, and 108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare progress, stopping, partial completion, grouped history, and Undo/recovery feedback where observable. Never run reference cleanup against personal files for this comparison. Record all three checkpoints in [reference-checks.md](reference-checks.md).

