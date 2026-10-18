# 044 — Validate performance and resilience across the expanded app

Status: Backlog  
Priority: P2  
Phase: I — Product-wide engineering validation  
Depends on: [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [007](007-native-ux-and-release.md), [014](014-incremental-index.md), [023](023-history-scheduling-alerts.md)

## Why

Per-feature tests do not establish how indexing, monitoring, cancellation, history, and large results behave together over time. Measure the expanded app under realistic interruption and scale before claiming broad reliability.

## Scope

- Build reproducible disposable datasets for many small files, deep/wide trees, large duplicate sets, many app records, and changing files. Record hardware, OS, build configuration, fixture size, and cold/warm conditions.
- Measure UI responsiveness, memory growth, descriptor/task counts, disk I/O, scan throughput, and idle/menu-only overhead. Establish budgets from measured baselines rather than invented universal timings.
- Exercise repeated cancellation/replacement, sleep/wake, app restarts, denied reads, low-disk journal writes, index corruption, and volume disconnects.
- Reuse task 002's filesystem-edge corpus and task 047's provider-access fixtures across indexed/cold scans, review, mutation, and recovery. Preserve path distinctions and supported file metadata under scale and interruption.
- Verify recovery never auto-retries mutations, cancellation never publishes executable partial plans, and background work respects lifecycle/power limits.
- Fix measured bottlenecks and leaks with before/after evidence. Keep expensive soak/scaling runs separate from the fast required CI suite where appropriate.

## Acceptance criteria

- [ ] Benchmarks and interruption scenarios are reproducible from documented fixtures and report their conditions.
- [ ] Repeated scans/navigation/cancellation do not accumulate unbounded tasks, descriptors, memory, or permanent stale busy states.
- [ ] Fault injection preserves user-data boundaries, journal evidence, and usable monitoring/recovery states.
- [ ] Product-wide performance limits and unresolved supported-scope concerns are documented with evidence before release inclusion.

## Validation

Use deterministic injected failures plus bounded integration/soak runs on disposable datasets. Keep real system power/hardware observations distinct from fake providers. Run relevant existing safety, ownership, journal, index, session, and lifecycle checks after fixes.

## Starting points

[Scripts](../Scripts), [Tests](../Tests), task 014's index, task 023's scheduler, and [AppModel.swift](../Sources/LumaApp/AppModel.swift). Spec: sections 83, 89–90, 93–94, and 108.1–108.9 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare observable responsiveness, cancellation, repeat scans, and menu-only behavior under comparable non-destructive conditions. Do not infer implementation internals or make unsupported benchmark comparisons; record in [reference-checks.md](reference-checks.md).

