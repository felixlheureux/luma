# 063 — Correct battery reporting on M2

Status: Planned
Priority: P1
Depends on: Existing task [017](017-monitoring-depth.md) monitoring implementation

## Outcome

The Battery view shows useful, verified information on an M2 Mac running macOS 26+, with charge and power state first. Correct task 017's collection and presentation gaps; this is not a monitoring expansion or an Intel compatibility task.

## Scope

- Compare Luma's actual readings with Battery Settings and System Information → Power on the reference M2. Investigate missing condition, cycle count and maximum capacity when macOS reports them. A missing key in the current IOPS/legacy collector does not prove that the hardware cannot supply the value. Do not fix this solely by hiding unavailable cells.
- Keep public IOPowerSources for lightweight charge, source state, charging flags and applicable estimates. Supplement slower details through a documented, bounded read-only source verified on the target: public power-source properties or a fixed Apple `system_profiler` structured Power report. Document the chosen fields, units, provenance and tested OS. Apple's documented `IOPMPowerSource` registry interface includes cycle count; that documentation alone does not guarantee its presence on M2. A tool's structured battery schema also needs actual target evidence; do not guess field names or parse localized display text.
- Collect slower details off-main when opening or explicitly refreshing Battery, cache the result with its observation time, and coalesce requests. Keep slow collection out of the two-second monitoring loop and invalidate details when their battery/source identity changes. A detail failure must preserve current lightweight readings and explain partial coverage. Use a small battery-specific provider, not a general command runner, shell pipeline, privileged helper or private framework/registry fallback.
- Keep current charge separate from maximum battery capacity. Never interpret normalized `CurrentCapacity`/`MaxCapacity` values as health, combine capacities with unverified units, or substitute private raw-capacity guesses. Prefer an explicit system-reported maximum-capacity percentage; label any independently justified estimate accurately. Consolidate reported health/condition into useful wording without inventing a healthy state.
- Preserve estimate states rather than collapsing everything to nil: calculating, applicable estimate, not applicable and missing/failed. Per-source time keys use signed **minutes**; `-1` means calculating. Discharge time requires battery power and explicit `IsCharging == false`; charging time requires `IsCharging == true`. Handle zero and terminal charging states accurately. If using `IOPSGetTimeRemainingEstimate`, its positive result is **seconds** and its unknown/unlimited sentinels are distinct; it is not a charging ETA. Use symbolic constants where provided.
- Read the OS `IsCharged` and `IsFinishingCharge` flags when available instead of deriving fully charged from exactly 100%. Preserve unknown booleans. Distinguish an absent battery from unavailable/partial reporting. The menu must choose its battery/thermal presentation from presence, not whether charge happened to be readable.
- Keep the existing System metric set and layout. Lead Battery with charge and actual power/charging state; show available optional details in a compact area. Replace the fixed grid of unavailable values with one concise partial-data explanation and Battery Settings/System Information access. No new adapter, temperature, discharge-rate, history or diagnostic feature is required.

## Acceptance

- [ ] Actual M2/macOS 26+ comparison records which existing fields macOS exposes and confirms Luma reports supported condition, cycles and maximum capacity through the verified path. Any remaining difference has specific source/output evidence and a visible limitation; fixtures alone cannot close this task.
- [ ] Lightweight charge/power monitoring stays responsive while slow details load, refresh or fail; cached details have an honest observation time and cannot migrate to another battery/source.
- [ ] Charging, discharging, plugged-in/not-charging, charged below 100%, finishing charge, zero, calculating and unknown/unlimited estimate cases have correct units and labels. Missing data never becomes zero, healthy or an invented duration.
- [ ] Charge/power state remains useful with partial details; no wall of unavailable cells or silent Battery-to-Thermals substitution. Light/Dark/System, narrow layouts and menu/main-window readings agree.
- [ ] No Intel work, private API/registry guesses, arbitrary commands, privilege escalation or normalized-charge health calculation is introduced.

## Validation and starting points

Use injected provider/clock/report fixtures for missing, malformed, ambiguous and changed-source data, parser boundaries, request coalescing, failure and estimate states. Run the Swift suite and existing native monitoring checker for the changed behavior. Update its assertions to verify useful partial presentation and record actual M2 field comparison separately from injected successes. Do not publish serial numbers or full private hardware reports. Do not mark the collection gap solved because synthetic health/cycle fixtures render.

Start in `BatteryProvider.swift`, `BatteryDetails.swift`, `MonitoringDetailsView.swift`, `SystemMonitor.swift`, `MenuCompanion.swift`, `BatteryDetailsTests.swift` and `MonitoringDepthCheck.swift`. Keep the correction within these existing boundaries. Follow [README](README.md) for native reference evidence.

## Primary evidence — reviewed 2026-10-19

- Apple documents [battery condition](https://support.apple.com/guide/mac-help/check-the-condition-of-your-computers-battery-mh20865/mac), [Apple Silicon maximum capacity](https://support.apple.com/en-us/102589) and [cycle count in System Information](https://support.apple.com/en-us/102888). System UI availability is not a guarantee that every value is in the current collector.
- [IOPSGetPowerSourceDescription](https://developer.apple.com/documentation/iokit/1523867-iopsgetpowersourcedescription) permits missing keys; [current capacity](https://developer.apple.com/documentation/iokit/kiopscurrentcapacitykey) and [design capacity](https://developer.apple.com/documentation/iokit/kiopsdesigncapacitykey) require correct units. [IOPMPowerSource](https://developer.apple.com/documentation/kernel/iopmpowersource) documents its registry interface, including cycle count.
- [Time to empty](https://developer.apple.com/documentation/iokit/kiopstimetoemptykey), [time to full](https://developer.apple.com/documentation/iokit/kiopstimetofullchargekey), [aggregate time estimate](https://developer.apple.com/documentation/iokit/1523835-iopsgettimeremainingestimate), [charged](https://developer.apple.com/documentation/iokit/kiopsischargedkey) and [finishing charge](https://developer.apple.com/documentation/iokit/kiopsisfinishingchargekey) define the state/unit rules above. The aggregate API's return-value documentation specifies seconds despite its abstract's wording.
