# 006 — Add explicit application reset

Status: Planned  
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

- [ ] Reset leaves the application bundle intact and touches only reviewed, supported targets.
- [ ] Preferences, account/session state, and possible user data are distinguishable before confirmation.
- [ ] Running or unknown ownership/activity states block the affected reset action rather than expanding its scope.
- [ ] Each completed move appears in Activity; a fixture Restore round trip preserves contents and refuses occupied destinations.
- [ ] Cancellation or a rejected preflight changes no files. A later failure stops remaining moves and accurately shows earlier successes.

## Validation

Use a fake app with separate cache, preferences, saved state, and valuable support-data fixtures. Exercise selected subsets, running helpers, recreated paths, partial failure, and recovery after restart. Manually review keyboard navigation and both appearances.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [ResultsView.swift](../Sources/LumaApp/ResultsView.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 005's shared resolver.

Spec: sections 38–42, 76, 80, and 96 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare the reference reset flow, target grouping, running-app handling, confirmation, and completion state. Record unavailable or untestable steps in [reference-checks.md](reference-checks.md); never reset a real personal app for comparison.

