# 014 — Make repeated scans faster with a local index

Status: Backlog  
Priority: P2  
Phase: B — Speed and deeper storage analysis  
Depends on: [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [008](008-community-rules.md), [047](047-provider-aware-filesystem.md)

## Why

Once hierarchical scans work, repeated traversal and hashing should not be the normal cost of reopening the same analysis. Introduce persistence only against measured bottlenecks and keep cached data outside the mutation trust boundary.

## Scope

- Measure cold/warm storage scans and duplicate hashing on fixed disposable datasets. Define the useful cache and performance target from that baseline.
- Add a project-owned index interface and use GRDB for SQLite if persistence is justified, following the spec's dependency review. Keep metadata scoped to authorized roots and explicitly chosen scans.
- Store identities, metadata, coverage, rule/catalog version, scan generation, and hash state as needed. Keep schema migrations and a clear way to remove cached local data.
- Use bounded FSEvents invalidation where supported, with a full revalidation fallback for dropped events, journal resets, root replacement, unmounts, or changed rules.
- Never treat a cached record/hash as current authorization for removal. The cleanup executor still performs current identity, ownership, and duplicate-content checks.

## Acceptance criteria

- [ ] Measured repeated scans improve without losing coverage or presenting stale results as current.
- [ ] Missed events, changed roots, metadata changes, and rule-version changes invalidate affected entries safely.
- [ ] Database corruption or a failed migration preserves user files and falls back to a fresh analysis rather than blocking unrelated monitoring.
- [ ] Clearing the analysis cache does not erase Activity history, ignore rules, or user data.

## Validation

Add index migration/invalidation fixtures and compare indexed results with cold-scan results. Include cancellation, hard links, root recreation, denied access, and event loss. Verify current dependency maintenance/license at implementation time and record benchmark conditions.

## Starting points

Task 004's transient tree, task 003's scan sessions, [Filesystem.swift](../Sources/LumaCore/Filesystem.swift), and [Package.swift](../Package.swift). Spec: sections 87–90, 105–106.1, and 108.5/108.7 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare repeat-scan feedback, stale/loading states, and storage-navigation continuity. Do not infer the reference's indexing internals. Log observations in [reference-checks.md](reference-checks.md).

