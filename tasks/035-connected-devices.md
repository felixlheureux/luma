# 035 — Show supported connected devices and accessory alerts

Status: Backlog  
Priority: P3  
Phase: G — Hardware context in the monitor  
Depends on: [016](016-volume-analysis.md), [017](017-monitoring-depth.md), [023](023-history-scheduling-alerts.md)

## Why

The menu companion can help with low accessory battery and external-drive capacity, provided the device information is actually available and does not require intrusive background discovery.

## Scope

- Inventory supported connected accessories, storage, and device connections using verified platform capabilities. Show names/types, connection state, and battery/capacity only when exposed reliably.
- Use stable scoped identities and handle duplicate names, reconnects, stale samples, multiple batteries, and permission restrictions.
- Add opt-in low-battery/external-space alerts through the existing notification policy, with cooldowns and direct links to the relevant detail.
- Keep discovery lightweight and read-only. Do not pair devices, scan continuously without need, request unrelated permissions, or expose serial numbers in ordinary UI/logs.
- Reuse volume analysis for drives instead of maintaining a conflicting capacity model.

## Acceptance criteria

- [ ] Unsupported or stale accessory battery values remain unavailable rather than zero or guessed percentages.
- [ ] Reconnected/replaced devices cannot inherit stale readings or another device's alert state.
- [ ] Alerts respect user preferences, permission denial, quiet periods, and cooldowns.
- [ ] The menu remains usable with no devices and with many devices, in both appearances and via VoiceOver.

## Validation

Use capability/device fixtures for reconnects, identical names, multiple battery components, missing permission, and removed drives. Check actual available hardware without claiming untested model coverage, and measure discovery overhead.

## Starting points

[MenuCompanion.swift](../Sources/LumaApp/MenuCompanion.swift), [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), task 016's volumes, and task 023's alert policy. Spec: sections 69–71 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare device grouping, battery/capacity states, detail density, and alert navigation at the required checkpoints. Record in [reference-checks.md](reference-checks.md).

