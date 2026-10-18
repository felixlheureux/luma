# 047 — Centralize cloud/provider-aware filesystem policy

Status: Ready  
Priority: P0  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md)

## Why

Cloud exclusions currently appear in individual feature plans. The filesystem and executor need one policy: content availability, provider ownership, and a safe local action are different facts. Even directory traversal can materialize dataless content, so a filename or one cloud flag is not sufficient protection.

## Scope

- Add a project-owned access policy/capability result for verified local, provider-managed, dataless, network-backed, and unknown targets. Evaluate the ancestor chain as well as the leaf, using current supported APIs and documented limits rather than provider-name guesses.
- Apply the policy before recursive inspection, hashing, thumbnail generation, indexing, cleanup validation, and Restore. A completed local download does not make a provider-managed object an ordinary local-only deletion target.
- Make ordinary scans avoid intentional materialization. Where a no-materialization inspection cannot be established, skip the affected scope and explain its coverage rather than probing until the OS fetches content.
- If a documented thread-scoped I/O policy is used, contain it in a controlled synchronous worker and restore it on every exit. Never carry thread-local state across Swift concurrency suspension or assume another worker inherits it.
- Keep provider-managed and unknown mutations unavailable in 0.3.0, with appropriate Finder/provider handoffs. Do not introduce cloud cleaning or a Remove Download implementation through this task.
- Revalidate access/provider state at execution, not only scan time, and distinguish logical remote size from locally inspected/reclaimable bytes. Keep explicit user Open actions separate from background scan access.

## Acceptance criteria

- [ ] All filesystem analysis and mutation entry points consult the same policy; direct core calls cannot bypass it with a rule ID or locally materialized path.
- [ ] Dataless ancestors, provider-backed local files, unknown providers, network paths, and state changes have explicit safe outcomes without ordinary cleanup authority.
- [ ] Tested scan/hash/preview paths do not intentionally download placeholder contents; unsupported guarantees are documented as skipped/unavailable coverage.
- [ ] Cancellation/errors restore any worker I/O policy, and no thread-local setting leaks to unrelated work.
- [ ] Local fixture cleanup and Restore remain usable, while provider-managed/unknown mutations stay disabled for this milestone.

## Validation and references

Use injected capability providers and a guarded filesystem adapter to assert that prohibited reads/moves are never requested. Cover dataless ancestors, changed provider state, unavailable metadata, preview/hash callers, cancellation, and policy restoration. Integration checks use disposable provider data only when a suitable setup exists; otherwise record that limit and retain unsupported states.

Primary references reviewed on 2026-10-17: [Apple TN3150 on dataless access and materialization](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files), [Apple's File Provider synchronization model](https://developer.apple.com/documentation/fileprovider/synchronizing-the-file-provider-extension), and [iCloud Drive local-download versus file-management controls](https://support.apple.com/en-ie/guide/mac-help/mchl1a02d711/27/mac/27). Recheck implementation details against the target SDK and actual provider behavior when implementing.

## Starting points

[Filesystem.swift](../Sources/LumaCore/Filesystem.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 002's descriptor adapter. Spec: sections 2.1, 2.5, 47, 53, 80–83, 90–94, and 104 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare cloud/placeholder labels, skipped coverage, preview behavior, and provider handoffs where observable without changing personal cloud data. Record the before/during/completion comparisons and limits in [reference-checks.md](reference-checks.md).

