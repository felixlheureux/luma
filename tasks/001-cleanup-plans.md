# 001 — Validate complete cleanup plans in the core

Status: Done  
Priority: P0  
Milestone: 0.3.0  
Depends on: None

## Why

In the 0.2.0 baseline, the UI prevented selecting every copy in a duplicate group while `CleanupJournal.trash` accepted individual items. The core needs to enforce the reviewed selection as a whole before storage drill-down and additional app actions create more combinations.

## Scope

- Introduce an immutable, project-owned cleanup plan containing a stable plan/session ID, reviewed items, scan context, authorized roots, and required duplicate-group evidence. Keep the UI responsible for presenting choices, and the core responsible for validating them. Preserve the ID through individual journal outcomes so task 048 can group progress and recovery accurately.
- Give cleanup one execution entry point. Individual journal moves must not provide a route around plan validation.
- Reject repeated paths and overlapping parent/child selections with an explanation. Make review counts and logical-byte totals agree with the executable plan; count hard-linked content consistently and retain the existing physical-savings caveat.
- Move the duplicate keep-one invariant into the core. Before moving a duplicate, verify that an unselected keeper still exists, remains accessible, and has matching full content. A cached group label or a `duplicates.sha256` rule string is insufficient proof.
- Preflight the complete plan before the first move. Revalidate relevant identity, owner, ignore, activity, and keeper assumptions at each mutation boundary. Stop on failure and preserve completed operations in Activity.
- Preserve existing journal recovery, legacy history, and explicit Restore behavior. Never resume an interrupted cleanup automatically.

## Acceptance criteria

- [x] A core caller bypassing SwiftUI cannot execute an all-copies duplicate selection or an overlapping plan.
- [x] A missing, unreadable, or modified keeper invalidates its group, including changes after initial review. Unrelated files remain untouched.
- [x] A plan containing an invalid item fails preflight without moving any item. Later failures stop remaining moves and retain accurate completed history.
- [x] Selection counts and totals in review describe exactly what the executor accepts.
- [x] Existing generated-data, uninstall, leftover, manual-file, and Restore workflows still work through the same boundary.

## Validation

Add disposable fixtures for direct core calls, parent/child overlap, repeated identities, changed keepers, ignored items, stale scans, interruption, and a failure after an earlier success. Inject filesystem/mutation boundaries where needed to make changes deterministic. Run the existing safety, duplicate, and journal suites. Never use personal files for destructive checks.

## Starting points

[AppModel.swift](../Sources/LumaApp/AppModel.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [Models.swift](../Sources/LumaCore/Models.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift).

Spec: sections 53–54, 76, 80, 83, 94, and 108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect selection/review, cancellation, and partial-failure presentation as available in the Downloads reference DMGs. Record observations and inaccessible states in [reference-checks.md](reference-checks.md); do not infer their internal safety guarantees.


## Completion evidence — 2026-10-17

- `CleanupPlan` is immutable and verifies selection identity, overlaps, unique logical totals, and independent duplicate evidence. `CleanupJournal.execute` is the sole public cleanup boundary; private moves retain preflight, live context checks, full duplicate hashes, durable plan IDs and per-item contributions.
- Added 23 plan-boundary fixtures; all 83 tests in seven suites pass. Coverage includes direct core bypasses, changed/missing/unreadable keepers, interleaved operations, ignored/stale candidates, native-move failure/cancellation, replay, legacy decoding, interrupted intent reconciliation, generated data, uninstall, leftovers and Restore.
- Debug native QA passed in light and dark appearances: actual review sheet attached, two selected trees reported 7 unique bytes rather than 14 raw item bytes, missing duplicate evidence was rejected, and fixtures remained unchanged. No cleanup executor was invoked by the native check.
- Debug and release builds verified; current filesystem pathname races and provider-policy work remain explicitly assigned to 002/047. Session progress/Undo UI remains 048.
- Reference static checks and interaction limitations are recorded in [reference-checks.md](reference-checks.md) and the [compiled scope audit](compiled-reference-audit.md). The reference's internal safety and runtime workflow were not verified.
