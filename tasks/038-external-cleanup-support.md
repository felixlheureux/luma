# 038 — Validate support for external-volume Trash and Restore

Status: Conditional backlog — support decision and fixtures first  
Priority: P3  
Phase: H — Carefully extend mutation boundaries  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [014](014-incremental-index.md), [016](016-volume-analysis.md), [030](030-trash-review.md)

## Why

Read-only external analysis does not establish that Luma can safely move or restore files on that volume. Supporting removal requires volume-bound authorization and recovery rather than relaxing the current home-volume guard.

## Scope

- Evaluate supported filesystem/Trash behavior on disposable external images, including read-only, missing Trash, permission, collision, and disconnect states. Produce an explicit support matrix before enabling a mutation capability.
- Bind authorization, cleanup plans, source/parent identities, and journal intents to a verified volume identity and mount generation, not only a mount path or device number.
- Verify the current user's native Trash destination and same-volume move semantics. Keep other users' Trash, protected roots, and unsupported providers outside the policy.
- Reconcile interrupted moves only when the expected volume is present and identities match. Unplugging, remounting, and path reuse must never redirect recovery to another volume.
- Restore only to a verified original parent without overwrite. Unsupported cases remain read-only; no cross-volume copy/delete fallback, permanent deletion, or invented Restore path.

## Acceptance criteria

- [ ] A documented support/no-go decision exists for each evaluated filesystem/provider and identifies the validation required for any enabled case.
- [ ] Mount-path reuse, changed volume identity, reconnects, and disconnects fail closed for both cleanup and Restore.
- [ ] Supported disposable-image moves retain durable recovery evidence and native Trash collision behavior across restart.
- [ ] Existing protected/home-volume rules remain intact; a no-go result leaves external mutation disabled and analysis available.

## Validation

Use disposable disk images with controlled ownership, filesystems, symlinks, mount swaps, collisions, and interrupted operations. Inject race checkpoints and lost-volume states. Document remaining native pathname-race limits rather than calling descriptor checks an atomic move guarantee.

## Starting points

[CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), task 002's adapter, and task 016's volume identities. Spec: sections 16, 47, 76, 80–83, and 94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare external-volume review, Trash destination/collision feedback, disconnected states, and recovery where observable using disposable media only. Log the checks in [reference-checks.md](reference-checks.md).

