# 026 — Add narrowly scoped troubleshooting tools

Status: Backlog  
Priority: P3  
Phase: E — Audited maintenance  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [008](008-community-rules.md)

## Why

DNS flushing and search reindexing can help specific troubleshooting cases. They need precise purpose and completion states, rather than a generic promise to optimize a healthy Mac.

## Scope

- Evaluate DNS-cache flushing and user-selected Spotlight reindexing first against current documented OS behavior. Evaluate Mail search repair separately; unsupported operations remain unavailable.
- Give each supported operation a fixed implementation, supported OS range, purpose, consequences, permission needs, progress/completion evidence, and cancellation limits.
- Use argument arrays and a fixed executable allowlist where a supported command is necessary. Do not add a generic shell runner, accept arbitrary commands, or silently invoke elevated access.
- Use a native/settings handoff where direct execution cannot be supported safely without a privileged helper. Do not make a root daemon a foundational dependency.
- Record maintenance outcomes separately from Trash moves, including failures and whether work may continue after cancellation. Do not show Restore for operations that cannot be reversed.
- Keep these tools user-invoked and outside automatic cleanup/scheduling. Do not claim routine reindexing or DNS flushing improves general performance.

## Acceptance criteria

- [ ] Every available action has a specific troubleshooting purpose, bounded target, and verified implementation for the tested OS.
- [ ] Unsupported OS/permission states cannot fall back to an unchecked command or broader filesystem scope.
- [ ] Arguments cannot inject shell code or expand a selected target unexpectedly.
- [ ] History, completion, and cancellation labels reflect what actually happened and do not imply an undo capability that does not exist.

## Validation

Use injected process/authorization providers for arguments, exit states, timeout, cancellation, and capability checks. Run supported integration cases only on disposable targets or a suitable test machine, following current primary platform documentation.

## Starting points

[MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), [CleanupActivity.swift](../Sources/LumaCore/CleanupActivity.swift), task 003's operation lifecycle, and task 001's validation patterns. Spec: sections 32–35, 92–94, and 108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare tool descriptions, target selection, authorization handoffs, progress, and outcome states. Do not run reference maintenance against the user's Mac. Record in [reference-checks.md](reference-checks.md).

