# 052 — Add user-started network quality and connection diagnostics

Status: Planned  
Priority: P2  
Depends on: [003](003-scan-sessions.md), [017](017-monitoring-depth.md)

## Why

Live transfer rates answer what the Mac is doing now; they do not measure connection capacity or explain latency under load. Offer an explicit diagnostic alongside passive monitoring.

## Scope

- Add a Network details surface showing active interface, connection type, supported local addresses, connection changes, passive rates/session totals and permission/unavailable states. Keep addresses and network names out of ordinary logs and exported reports by default.
- Evaluate Apple's built-in `networkQuality` as the first fixed command adapter. Confirm supported options and JSON schema on each supported OS, use argument arrays, fixed executable/endpoint policy, normal TLS verification and bounded runtime. No arbitrary shell/config URL runner.
- Start tests only after a deliberate user action that explains Internet traffic, test provider and possible effect on current calls/downloads. No scheduled/background speed tests. Do not silently switch interfaces or send probes to arbitrary LAN hosts.
- Report measured download/upload capacity, idle latency and loaded responsiveness where actually available, with units, interface, time, test provider and scope. Passive bytes/second and active bits/second must not be confused. A fast speed result does not imply good responsiveness or general network health.
- Support running, stopping, partial, completed, offline, constrained/expensive connection, captive-portal-suspected and failed states only when evidence supports them. Connection changes invalidate comparisons; uncertain portal/DNS/VPN causes remain unknown.
- Treat structured error fields and missing/invalid measurements as failures or partial results even when a subprocess exits zero. Bound captured output, reap cancelled processes and preserve valid partial outcomes without inventing a complete score.
- Offer supported System Settings/Wireless Diagnostics handoffs. Task 026 separately assesses DNS flushing; no automatic DNS changes, route resets, VPN disabling, proxy changes or network repair.
- Assess per-app network attribution as a separately gated provider capability. Only display it with a supported, validated process/interface model; no packet capture, privileged agent, fabricated per-app counters or implication that system totals identify an app.

## Acceptance criteria

- [ ] Passive monitoring never initiates active tests, and tests require a deliberate action with clear data-use/provider context.
- [ ] JSON fixtures cover versions, missing fields, error objects, successful exit with invalid results, partial output and malformed values without false success.
- [ ] Interface/VPN changes, cancellation, offline tests and subprocess timeout leave no orphan work or mislabeled comparison.
- [ ] Metrics disclose units, timestamp and scope; unsupported Wi-Fi identity/attribution fields remain unavailable.
- [ ] No diagnostic modifies network settings; native handoffs are clear and private details are redacted from exports.

## Validation

Use injected subprocess/network-state adapters and recorded synthetic schemas; test without making real Internet requests in CI. Run a small deliberate manual test only on an available suitable connection when implementing, record measured traffic and capabilities, and do not claim untested interfaces or captive portals are covered.

## Starting points and evidence

Task 017's counter provider, task 003's lifecycle, task 026's fixed maintenance adapter policy, and spec sections 67, 70, 91–93 and 101.

Primary sources reviewed 2026-10-17: [Apple Network Responsiveness](https://support.apple.com/en-us/101942), [Wireless Diagnostics](https://support.apple.com/en-ie/guide/mac-help/mchlf4de377f/mac), and local Apple `networkQuality(8)` documenting Internet data use, JSON output, interface selection, maximum runtime, throughput, idle latency and RPM. No active test was run during task planning.

Reference checkpoints: compare passive versus active measurements, test initiation, cancellation, metrics and failure messaging. Do not infer per-app attribution from interface totals. Record evidence in [reference-checks.md](reference-checks.md).
