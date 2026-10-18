# 051 — Add a measured memory-relief workflow

Status: Planned  
Priority: P1  
Release: Next feature expansion; independent of disk traversal  
Depends on: [003](003-scan-sessions.md), [018](018-process-insights.md)

## Why

The specification includes memory optimization, but a consumer list alone does not provide an actionable relief workflow. Help users relieve actual sustained pressure and understand the result, including when no action is needed.

## Scope

- Provide a Review memory action in Optimizer and a compact entry point in the menu. Show pressure, used/cached/compressed/wired memory, swap occupancy and supported swap-activity trends with timestamps and sampling limits.
- Reuse task 018's bounded sustained-load evidence, grouped app ownership and verified process identities. Size alone does not label an app inactive, leaking, or safe to quit; unavailable signals remain unknown.
- Let the user explicitly choose apps to quit normally, with app names, current measured footprint, relevant activity and unsaved-work consequences. Initial selection is empty. Do not automatically quit, force-quit, relaunch, terminate helpers separately or target system/unknown processes.
- Show a quitting/waiting state and verify whether each app actually exited. Handle save prompts, refusal, timeout, PID reuse, relaunch and cancellation without claiming success prematurely. Force Quit remains a separately reviewed task 018 action.
- Resample after the selected action with a documented settling interval and comparable observation window. Show observed before/after pressure and memory values, changes in other running apps, and sampling uncertainty. Do not sum app footprints into guaranteed recoverable RAM, attribute every system change to Luma, or treat an unchanged swap file as failure.
- Evaluate any proposed explicit reclaim API separately against current public documentation, permissions, ownership and reproducible workload measurements. If no supported beneficial system-wide action is established, ship app review/quit and a no-action-needed state. Releasing Luma's own caches can only be described as Luma's own memory.
- Do not run `purge`, allocate memory to force eviction, delete swap, restart system services, install a root helper or advertise a fixed amount of RAM recovered. Cached memory is useful system-managed memory, not automatic waste.
- Keep bounded local action outcomes separate from Trash history; no file Restore is offered for app termination. Do not retain private process arguments or documents.

## Acceptance criteria

- [ ] Low pressure with high used/cached memory yields an accurate no-action-needed state; sustained pressure can open evidence-backed consumer review.
- [ ] Every quit targets the reviewed current owning app and reports actual exit, refusal, timeout or cancellation without automatic escalation.
- [ ] Before/after results are actual comparable samples with timing/coverage; overlapping app footprints are not presented as exact recoverable bytes.
- [ ] Missing telemetry, sleep/wake, unrelated workload changes and app relaunch produce honest partial/unavailable outcomes.
- [ ] The reclaim assessment records public evidence, measurements and a support/no-go decision; no unsupported purge/pressure-inducing path exists.

## Validation

Use injected sample clocks/providers and disposable fixture apps with cooperative exit, refusal, delayed exit and relaunch. Verify pressure trends, shared-memory accounting, PID reuse, cancellation and post-action sampling. Any performance experiment uses a fixed disposable workload; do not quit personal apps to validate behavior.

## Starting points and evidence

[MemoryAccounting.swift](../Sources/LumaCore/MemoryAccounting.swift), [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), [ProcessGrouping.swift](../Sources/LumaCore/ProcessGrouping.swift), tasks 018/023 and spec sections 2.4, 22–27, 63 and 70–71.

Primary sources reviewed 2026-10-17: [Apple memory accounting](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac); local Apple `purge(8)` describes cold disk-cache performance analysis and explicitly excludes anonymous app allocations. This task adds no claim that a supported general RAM-reclaim API has been found.

Reference checkpoints: compare memory action meaning, review, progress, no-action-needed state and reported outcomes. Do not infer real performance benefit from a displayed freed-memory counter. Record before/during/completion evidence in [reference-checks.md](reference-checks.md).
