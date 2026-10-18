# 018 — Explain sustained resource use and unresponsive apps

Status: Planned  
Priority: P1  
Phase: Near-term parallel optimization track  
Depends on: [003](003-scan-sessions.md)

## Why

A useful Optimizer explains sustained problems and identifies the app involved. Momentary CPU spikes and normal memory caching should not trigger alarming recommendations.

## Scope

This evidence/action foundation can proceed without task 017's network or battery providers. Task 051 builds the guided memory-relief and before/after workflow on it; do not duplicate that UI here.

- Track bounded recent observations for grouped apps and distinguish momentary load from sustained background CPU, pressure/swap trends, and thermal constraints.
- Show the evidence interval and current uncertainty behind a recommendation. High RAM usage alone is not a problem classification.
- Detect unresponsiveness only through supported signals and repeated observations, accounting for sleep/wake and app launch. A busy process is not automatically hung.
- Provide Activate, inspect helpers, and normal Quit actions where appropriate. Any Force Quit action is explicit, applies only to a verified user app, and explains possible unsaved work loss.
- Protect critical processes, handle PID reuse, and clear stale recommendations when the owning app exits or the condition resolves. No automatic termination or RAM purging.

## Acceptance criteria

- [ ] Short spikes, expected foreground work, and normal high memory use do not produce unsupported warnings.
- [ ] Sustained recommendations disclose their measurement interval and disappear when evidence no longer supports them.
- [ ] PID reuse, helper regrouping, and app restart cannot target a different process for an action.
- [ ] System-critical/unknown targets do not receive casual quit or force-quit actions.

## Validation

Use timestamped sample sequences with a controllable clock for load spikes, sustained load, pressure changes, sleep gaps, exits, and identity reuse. Exercise app actions against disposable fixture apps only. Manually inspect explanations and action focus.

## Starting points

[ProcessGrouping.swift](../Sources/LumaCore/ProcessGrouping.swift), [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), and [AppModel.swift](../Sources/LumaApp/AppModel.swift). Spec: sections 22–27 and 71 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare consumer grouping, sustained-load explanations, unresponsive states, and action review. Record observed behavior and limits in [reference-checks.md](reference-checks.md).

