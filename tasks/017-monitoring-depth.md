# 017 — Add network rates and reliable battery details

Status: Planned  
Priority: P1  
Phase: Near-term parallel monitoring track  
Depends on: [003](003-scan-sessions.md)

## Why

The menu companion should answer more everyday questions than CPU, used RAM, and charge level. Add meaningful network activity and battery details while keeping collection lightweight and honest about unsupported hardware.

## Scope

Deliver passive network rates/interface/session usage first; reliable battery details are a second independently reviewable slice. Both slices must complete before marking this whole task Done. Task 052 owns active network testing.

- Add passive upload/download rates and session totals from supported interface counters, with a clear selected/active interface policy and monotonic sampling.
- Show supported connection type/local address in Network details with explicit privacy and permission states. Do not guess Wi-Fi names, attribute total traffic to apps, or double-count physical and VPN/tunnel counters.
- Handle counter resets, sleep/wake, VPNs, interface changes, and disconnected states without negative rates or double-counted traffic. Do not run active speed tests in the background.
- Show battery condition, maximum capacity/health, cycle count, charging state, and estimates only where a reliable supported source is available. Desktop Macs and unavailable fields have explicit states.
- Expose useful summaries in System and the menu companion, with details in the main app rather than an overloaded popover.
- Keep memory pressure distinct from used memory and preserve grouped resource consumers. Avoid private sensor hacks or invented temperature/health values.

## Acceptance criteria

- [ ] Network fixtures produce correct rates and totals across resets, interface transitions, and sleep/wake gaps.
- [ ] Unsupported battery fields remain unavailable instead of becoming zero, healthy, or a guessed estimate.
- [ ] The menu stays readable in both appearances and does not require the main window to remain visible.
- [ ] Collection overhead is measured against the existing monitor and remains bounded when no details view is open.

## Validation

Use injected counter/power providers for deterministic tests and manual checks on available hardware. Record what hardware/OS states were actually tested; do not claim coverage of unavailable devices. Verify current supported platform APIs before implementing providers.

## Starting points

[SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), [MenuCompanion.swift](../Sources/LumaApp/MenuCompanion.swift), and [MemoryAccounting.swift](../Sources/LumaCore/MemoryAccounting.swift). Spec: sections 62–70 and 108.8–108.11 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare metric meaning, menu density, expanded details, and unavailable states throughout implementation. Record in [reference-checks.md](reference-checks.md).

