# 034 — Add supported disk-health and thermal diagnostics

Status: Backlog — capability assessment first  
Priority: P3  
Phase: G — Explain system-managed storage and hardware  
Depends on: [016](016-volume-analysis.md), [017](017-monitoring-depth.md)

## Why

Disk condition and thermal context can be useful, but support varies by hardware and connection. A missing SMART result or sensor value must not be presented as a healthy device or a measured temperature.

## Scope

- Define capability-based providers for supported disk status and thermal information, with primary-source/API verification and hardware/OS scope documented before implementation.
- Separate storage capacity from hardware health. Show an actual status/source when available and explicit unsupported, unavailable, or restricted states otherwise.
- Prefer supported thermal-state information. Add temperatures/fan fields only where a reliable supported source exists; do not depend on fragile sensor-name guesses or private control interfaces.
- Bind observations to the correct physical/logical device and invalidate them on replacement or disconnect. Avoid aggressive polling and any disk stress/repair operation in this feature.
- Put details in System and concise relevant context in the menu, with no arbitrary combined health score.

## Acceptance criteria

- [ ] Provider fixtures distinguish measured status from unsupported/unknown across internal, USB, and simulated hardware cases.
- [ ] Device replacement and stale samples cannot display another device's health or temperature.
- [ ] No unknown result is labeled Healthy, and no unavailable sensor becomes a fabricated value.
- [ ] Collection remains read-only and its measured overhead is bounded; no privileged daemon is introduced.

## Validation

Use injected capability/device providers, counter resets, stale samples, denied access, and disconnects. Record actual hardware tested separately from simulated coverage, and keep unsupported devices explicitly unsupported.

## Starting points

[SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), task 016's device identity, and task 017's metric providers. Spec: sections 65, 68, 90, and 108.11 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare diagnostic labels, source detail, supported-device behavior, and unavailable states. Reference resource presence does not establish hardware accuracy; record limits in [reference-checks.md](reference-checks.md).

