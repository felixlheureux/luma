# 017 — Add network rates and reliable battery details

Status: Done
Priority: P1  
Phase: Near-term parallel monitoring track  
Depends on: [003](003-scan-sessions.md)

## Why

The menu companion should answer more everyday questions than CPU, used RAM, and charge level. Add meaningful network activity and battery details while keeping collection lightweight and honest about unsupported hardware.

## Scope

Deliver passive network rates/interface/session usage first; reliable battery details are a second independently reviewable slice. Both slices must complete before marking this whole task Done. Active network testing was assigned to former task 052, deleted in the core reset.

- Add passive upload/download rates and session totals from supported interface counters, with a clear selected/active interface policy and monotonic sampling.
- Show supported connection type/local address in Network details with explicit privacy and permission states. Do not guess Wi-Fi names, attribute total traffic to apps, or double-count physical and VPN/tunnel counters.
- Handle counter resets, sleep/wake, VPNs, interface changes, and disconnected states without negative rates or double-counted traffic. Do not run active speed tests in the background.
- Show battery condition, maximum capacity/health, cycle count, charging state, and estimates only where a reliable supported source is available. Desktop Macs and unavailable fields have explicit states.
- Expose useful summaries in System and the menu companion, with details in the main app rather than an overloaded popover.
- Keep memory pressure distinct from used memory and preserve grouped resource consumers. Avoid private sensor hacks or invented temperature/health values.

## Acceptance criteria

- [x] Network fixtures produce correct rates and totals across resets, interface transitions, and sleep/wake gaps.
- [x] Unsupported battery fields remain unavailable instead of becoming zero, healthy, or a guessed estimate.
- [x] The menu stays readable in both appearances and does not require the main window to remain visible.
- [x] Collection overhead is measured against the existing monitor and remains bounded when no details view is open.

## Validation

Use injected counter/power providers for deterministic tests and manual checks on available hardware. Record what hardware/OS states were actually tested; do not claim coverage of unavailable devices. Verify current supported platform APIs before implementing providers.

## Starting points

[SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), [MenuCompanion.swift](../Sources/LumaApp/MenuCompanion.swift), and [MemoryAccounting.swift](../Sources/LumaCore/MemoryAccounting.swift). Spec: sections 62–70 and 108.8–108.11 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare metric meaning, menu density, expanded details, and unavailable states throughout implementation. Record in [reference-checks.md](reference-checks.md).


## Implementation and provider contract

`NetworkCounters` bounds and decodes public Darwin NET_RT_IFLIST2/RTM_IFINFO2 64-bit counters. `NetworkProvider` combines these with getifaddrs numeric local addresses and SystemConfiguration's primary interface (IPv4, then IPv6). No DNS lookup, SSID inference, per-app attribution or active traffic is involved. Automatic or explicit selection measures one interface only. ContinuousClock timestamps, administrative generations, wake notifications and missing/reset/gap states prevent invalid intervals from becoming rates. Session totals include only valid measured intervals, omitting transitions and sleep.

`BatteryProvider` uses public IOPowerSources. The supported legacy IOPMCopyBatteryInfo API supplements only cycle count for an unambiguous single battery; unavailable/ambiguous data remains nil. Charge uses current/max values in their source units. Maximum-capacity estimation requires separately reported nominal/design values, never normalized charge's maximum (commonly 100). Condition, health, cycles, power/charging state and estimates are optional and independently validated. Desktop and unavailable power reports have explicit UI states.

Primary contracts were checked against the installed macOS SDK's IOPSKeys.h, IOPMLib.h, IOPM.h, net/if.h, net/if_var.h and net/route.h, alongside [Apple IOPowerSources](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo), [IOPS keys](https://developer.apple.com/documentation/iokit/iopskeys_h) and [getifaddrs](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getifaddrs.3.html). IOPMCopyBatteryInfo is documented as supported but not recommended; IOPowerSources remains primary. No private registry sensor keys or elevated helper are used.

## Validation evidence and limits — 2026-10-18

- All 285 Swift tests in 28 suites pass, including 16 new network counter/accounting and battery fixtures. Cases cover counters above 4 GiB, truncated/invalid/oversized records, resets, interface generations, physical/tunnel non-summing, disconnected/missing sources, backward clocks, sleep gaps, unknown fields, charge versus health and estimate validity.
- Final native monitoring checks pass light/dark injected supported, unavailable and desktop battery states, single-interface rates, System details, compact menu bounds, preserved memory-pressure meaning and continued monitoring after main-window close. Own-window captures were inspected. No mutation, personal-folder scan or active network test is invoked.
- On the available Apple Silicon MacBook Air, macOS 27.0.1 (26A434), actual network counters were available (20 enumerated interfaces). The actual power report exposed charge and an estimate; health, condition, maximum capacity and cycles were unavailable. Fixtures validate their supported presentation, not availability on this hardware. Physical desktop, real VPN transitions and actual sleep/wake were not manually exercised; deterministic fixtures cover their accounting/state boundaries.
- Twenty-sample native core CPU/memory/disk baseline medians were 9.59/9.20 ms in light/dark; extended network/battery collection medians were 15.78/14.79 ms and p95 18.10/15.56 ms. Collection runs off-main every two seconds even without a details view. This compares current core versus extended collection on this machine, not an exact historical release or a universal energy guarantee.
- The optimized app builds successfully and passes strict deep signature verification.
- All 72 native page/layout samples across Light, Dark, System and increased-contrast appearances pass with continued menu monitoring. Full keyboard/VoiceOver traversal remains a manual release gate.

At completion, active quality diagnostics and process insights were still unstarted. Those expansion tasks were deleted in the 2026-10-19 core reset; follow [the current queue](README.md).

- Final native scan-lifecycle regression passes in both appearances from the original app location: 6,000-file inventory 1.701/1.698 s and maximum sampled main-actor delay 0.110/0.089 s, including monitoring after window close. An earlier concurrent-release-build run missed one 2.5-second monitoring assertion; a relocated-bundle retry confirmed monitoring but timed out in the footprint fixture. Neither failed run is counted as passing evidence. The original-location isolated rerun passes all assertions.
