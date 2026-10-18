# 023 — Add scan history, optional schedules, and useful alerts

Status: Backlog  
Priority: P3  
Phase: C follow-up — Monitoring over time  
Depends on: [003](003-scan-sessions.md), [013](013-smart-check.md), [014](014-incremental-index.md), [017](017-monitoring-depth.md)

## Why

Users should be able to understand what changed since a previous scan and choose when Luma checks again, without turning the app into an intrusive background cleaner.

## Scope

- Store local scan summaries with scope, time, coverage, rule version, and comparable totals. Keep this distinct from Activity's actual file-operation journal.
- Show change since a compatible previous analysis and explain when different scope/rules make comparison invalid. Trash moves are not proof of immediately reclaimed disk space.
- Add opt-in scan scheduling while Luma is running, with bounded work, cancellation, quiet periods, and battery/thermal awareness. State clearly what happens when the app is quit; do not silently install a daemon.
- Add user-configurable low-space and sustained-condition notifications, with deduplication, cooldowns, permission handling, and links to relevant review screens.
- Schedules and alerts never select files, perform cleanup, quit apps, or initiate privacy removal automatically.

## Acceptance criteria

- [ ] Scan history distinguishes complete, partial, and cancelled analysis from actual cleanup operations.
- [ ] Comparisons reject incompatible scopes/catalog versions rather than showing misleading savings.
- [ ] Quiet periods, notification denial, sleep/wake, missed schedules, and repeated threshold crossings behave predictably.
- [ ] Background checks remain optional, read-only, and bounded, and explicit Quit stops in-process scheduling.

## Validation

Use a fake clock and injected notification/power/session providers for recurrence, cooldowns, missed runs, and threshold behavior. Test retention/migrations without changing the operation journal. Manually verify menu-only operation and settings clarity.

## Starting points

Task 014's persistence boundary, task 013's checks, [AppModel.swift](../Sources/LumaApp/AppModel.swift), [StatusBarController.swift](../Sources/LumaApp/StatusBarController.swift), and [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift). Spec: sections 66, 71, 75–76, 87, and 89–90 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare history meaning, schedule settings, alert frequency, and menu-only behavior. Record the relevant checks in [reference-checks.md](reference-checks.md).

