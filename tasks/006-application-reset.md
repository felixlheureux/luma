# 006 — Add explicit application reset

Status: Done
Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [005](005-application-footprints.md)

## Why

Users should be able to review an app's state for troubleshooting without uninstalling its bundle. Reset needs a clear boundary between generated caches, preferences, account state, and data worth keeping.

## Scope

- Add a Review reset action in application details, backed by the shared relationship resolver and normal cleanup-plan executor.
- Group supported exact targets as caches, preferences/settings, saved state, and other app data. Show concrete consequences, including lost settings or sign-in state where established by a rule.
- Start with no selected targets. Keep the application bundle outside a reset plan. Application Support is a separate review category with explicit user selection, never an implied part of a reset preset.
- Require the app and known owning helpers to be stopped. Offer a normal quit request when appropriate and recheck before mutation; do not force-quit automatically.
- Use the existing review sheet, journal, Activity, and identity-verified Restore. Explain that active apps may recreate paths and prevent a non-overwriting Restore.
- Invalidate affected footprint/leftover results after completion or partial failure and offer a rescan.

## Acceptance criteria

- [x] Reset leaves the application bundle intact and touches only reviewed, supported targets.
- [x] Preferences, account/session state, and possible user data are distinguishable before confirmation.
- [x] Running or unknown ownership/activity states block the affected reset action rather than expanding its scope.
- [x] Each completed move appears in Activity; a fixture Restore round trip preserves contents and refuses occupied destinations.
- [x] Cancellation or a rejected preflight changes no files. A later failure stops remaining moves and accurately shows earlier successes.

## Validation

Use a fake app with separate cache, preferences, saved state, and valuable support-data fixtures. Exercise selected subsets, running helpers, recreated paths, partial failure, and recovery after restart. Manually review keyboard navigation and both appearances.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 005's shared resolver.

Spec: sections 38–42, 76, 80, and 96 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare the reference reset flow, target grouping, running-app handling, confirmation, and completion state. Record unavailable or untestable steps in [reference-checks.md](reference-checks.md); never reset a real personal app for comparison.


## Implementation evidence — 2026-10-18

- `ApplicationReset` defines four consequence groups and validates a single supported owner; `CleanupPlan` captures the distinct reset source/app and rejects bundles, mixed owners and unsupported targets. No targets or support-data presets are selected automatically.
- The footprint sheet offers Review reset, separate support/container-data review, user-started normal quit, explicit activity recheck and the existing final confirmation. Unknown activity or installed ownership blocks reset. Preflight and every move recheck owner/helper identifiers and executable paths inside the app bundle.
- The existing journal records per-item reset outcomes, safe Stop, partial failure, restart and non-overwriting Restore/Undo. Footprints and leftovers invalidate after mutation outcomes and Restore; Inspect again requests fresh evidence.
- `bash Scripts/test.sh`: 168 tests in 16 suites pass. Reset fixtures cover all four groups, selected subsets, bundle/missing-app/unknown-process/helper rejection, provider/ignore/symlink boundaries, cancellation, stale preflight, native-mover failure/reconciliation, a helper starting between moves, restart and occupied Restore destinations. Valuable unselected support documents and the app bundle remain intact. All fixture moves use an injected mover and generated home.
- Debug app build and native light/dark footprint/reset checks pass: attached review sheets, no initial selection, four reset groups, keyboard focus, data-only reset confirmation and footprint/leftover invalidation. Cleanup-session and scan/window/menu light/dark regressions pass. Native checks never execute cleanup against personal data.
- Own reset and final-confirmation captures were inspected in both appearances. Lower groups require scrolling, and fallback captures can omit native/layer-backed controls. Keyboard focus is checked, but a complete keyboard/VoiceOver audit and real-app quit/save-prompt interactions remain in task 007. Fixture-only QA intentionally shows unknown ownership for its app outside the actual home; idle/running transitions are covered by core fixtures.
- Reference checkpoints and limits are recorded in [reference-checks.md](reference-checks.md). Activity checks do not lock other processes or establish ownership for unrelated external daemons; the supported detection envelope is documented in Safety.md.
