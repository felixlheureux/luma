# 053 — Explain live disk activity and sustained I/O

Status: Planned  
Priority: P2  
Depends on: [003](003-scan-sessions.md)

## Why

CPU and memory do not explain every slowdown. Add observed disk reads/writes and supported app attribution so users can distinguish ongoing file work from storage capacity or hardware-health issues.

## Scope

- Assess current public system/process counter APIs and document supported OS/hardware scope before choosing providers. Sample cumulative read/write counters into rates using a monotonic clock, with bounded history and lightweight collection.
- Show system read/write activity, measurement scope, interval, source and unavailable states. Logical filesystem I/O, physical-device traffic, operation counts and bytes have different meanings; do not label one as another or double-count APFS/container devices.
- Add app/helper grouping only where supported process counters and stable process identities establish attribution. Explain coverage limits; app totals need not equal physical disk totals. Unknown attribution remains unknown without packet-style tracing, elevated helpers or private APIs.
- Handle sleep/wake, counter resets/overflow, process exit/PID reuse, volume changes and stale samples without negative rates or false zero activity.
- Reuse task 018's sustained observation policy for any recommendations. Disk activity alone does not prove a bottleneck, failing drive, excessive swap, or an app that should be stopped. Correlate supported evidence without claiming causation.
- Keep SMART/disk health and thermal capability work in 034, capacity/snapshot accounting in 033, and network counters in 017. Offer app inspection/Activity Monitor handoffs; no automatic service restart, disk benchmark, repair or process termination.

## Acceptance criteria

- [ ] Fixtures produce correct units/rates across normal samples, resets, sleep and missing telemetry.
- [ ] Logical/process versus physical-device counters are labeled correctly, with documented aggregation and coverage.
- [ ] Unsupported attribution remains unavailable and reused process/volume identities cannot inherit stale history.
- [ ] System/menu integration stays readable and measured sampling overhead remains bounded.
- [ ] No hardware-health or performance diagnosis is inferred solely from activity volume.

## Validation

Use injected clocks/counters and disposable reader/writer fixture apps for any manual attribution checks. No disk stress benchmark or personal file access is needed. Verify providers against current SDK documentation, compare against Activity Monitor's metric definitions, and record scope differences rather than demanding unlike counters agree.

## Starting points

[SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [ProcessGrouping.swift](../Sources/LumaCore/ProcessGrouping.swift), tasks 017/018/034 and [Apple Activity Monitor](https://support.apple.com/guide/activity-monitor/view-disk-activity-actmntr1005/mac). This is a small product extension supporting the spec's evidence-based resource troubleshooting; it is not currently implemented or proven by the compiled reference.

Reference checkpoints: compare disk-activity meaning, scope, rates and unavailable states where present. Absence of a matching reference symbol is not proof the capability is absent. Log before/during/completion evidence in [reference-checks.md](reference-checks.md).
