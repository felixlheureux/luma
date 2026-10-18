# 040 — Evaluate supported Photos-library discovery and review

Status: Conditional backlog — public capability and recovery assessment first  
Priority: P3  
Phase: H — Carefully extend provider boundaries  
Depends on: [001](001-cleanup-plans.md), [003](003-scan-sessions.md), [014](014-incremental-index.md), [022](022-similar-photos.md)

## Why

Folder-based image analysis does not cover a user's managed photo library. Any library integration must use supported provider capabilities and preserve its own permission, asset, and recovery semantics.

## Scope

- Evaluate current public Photos/PhotoKit capabilities, authorization scope, asset identifiers, thumbnails, metadata, and change notifications before choosing a supported first slice.
- Start with explicit library/album review and local analysis. Respect limited/denied access, cancellation, cloud availability, and the user's choice about any original download.
- Treat an asset as a provider-managed object, not an exposed path inside a library package. Never edit library databases, move package internals, or infer originals from private layouts.
- Reuse comparison/grouping where appropriate while preserving asset versions, edits, paired components, and provider identity. Unknown equivalence remains unknown.
- Assess any future removal separately with supported provider operations, explicit review, typed operation receipts, and accurate recovery limits. Do not represent provider deletion as a normal Trash/Restore operation.

## Acceptance criteria

- [ ] The capability assessment defines a supported read-only first slice or an explicit no-go with reasons.
- [ ] Limited/changed authorization, asset replacement, edits, unavailable originals, and cloud-only state cannot silently expand access or trigger downloads.
- [ ] The library's private files/databases remain untouched, and analysis results retain correct provider asset identity.
- [ ] Any removal capability requires separately verified provider/recovery semantics; absent that evidence, the feature remains inspection-only.

## Validation

Use an injected provider plus a disposable library if available. Cover permission transitions, paired assets, edits, change notifications, cache invalidation, cloud placeholders, and cancellation. Verify current primary documentation and record which integration cases were actually tested.

## Starting points

Task 022's image analysis, task 014's cache boundary, task 003's sessions, and task 001's typed operation policy. Spec: sections 56, 91, 93, and 108.13 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare library permission, album selection, original availability, comparison, and recovery states where accessible. Do not alter the user's library through either app; log checks in [reference-checks.md](reference-checks.md).

