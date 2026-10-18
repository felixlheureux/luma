# 002 — Strengthen filesystem identity checks

Status: Done  
Priority: P0  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md)

## Why

Current path-component checks reduce stale-scan mistakes, but a parent or target can change before the final pathname-based Trash call. Strengthen the boundary before adding more manual file actions, and describe exactly what the native API still leaves unresolved.

## Scope

- Add a small project-owned filesystem adapter for descriptor-relative inspection using Darwin APIs. Pin relevant directories and compare descriptor identities with the scanned device/inode and expected parent chain; reject links without following their targets.
- Use the adapter during cleanup-plan validation and immediately around Trash and Restore operations. Verify owners, volume boundaries, and expected file types, including replaced parents and mount points.
- Preserve the bounded exception for internal framework links in valid app bundles; never traverse an external target.
- Keep native Trash collision handling and non-overwriting Restore. Do not introduce permanent deletion or a custom Trash implementation to hide a failing check.
- Identify which final calls still resolve a pathname. Record the remaining race window and its implications in the safety documentation; descriptor inspection alone does not make `FileManager.trashItem` atomic with validation.
- Preserve journal schema compatibility. Add low-level dependencies only if they materially improve the adapter and satisfy the spec's dependency policy.
- Encode identity/tree records unambiguously, including filenames containing delimiters, newlines, and Unicode variants. Preserve filesystem path distinctions rather than merging objects by case folding or display-name normalization.
- Define supported ordinary file types and reject unsupported special objects without opening them. Extend the bounded application-link exception without allowing aliases or external targets to escape review.

## Acceptance criteria

- [x] Deterministic parent replacement, target replacement, link substitution, and volume-boundary fixtures fail closed before the guarded move.
- [x] Verified identity tokens cannot be reused for a different path, parent, or filesystem object.
- [x] Internal application links remain supported, while external links and aliases remain excluded.
- [x] Restore preserves an occupied destination and detects a changed original parent.
- [x] Documentation distinguishes the checks now enforced from the residual native pathname race. Unsupported operations remain unavailable rather than silently weakening validation.
- [x] Case-sensitive names, Unicode variants, delimiter/newline filenames, aliases, and special-file fixtures cannot collide in fingerprints or bypass the supported-type policy.

## Validation

Use injected synchronization points for race fixtures; do not depend on a probabilistic stress loop as proof. Include valid moves, app-bundle framework links, ancestor swaps, mount/device mismatches, and journal recovery after a rejected or interrupted operation. Run safety, leftover, generated-data, and journal suites.

Add a reusable filesystem-edge corpus covering supported case-sensitive/insensitive layouts, Unicode/long/delimiter-containing names, sparse files, hard links, aliases, special objects, extended attributes, Finder tags, permissions, and ACLs. Check contents and supported metadata through native fixture Trash/Restore round trips. Document unsupported preservation/inspection cases rather than silently claiming equivalence.

## Starting points

[Filesystem.swift](../Sources/LumaCore/Filesystem.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [Safety.md](../Documentation/Safety.md).

Spec: sections 80–83, 93–94, 106.9, and 108.1–108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare blocked-action explanations and recovery paths in the reference app where observable. Internal race resistance cannot be established from UI or resources. Record that limit in [reference-checks.md](reference-checks.md).


## Completion evidence — 2026-10-17

- Added the project-owned `PinnedPath` Darwin adapter. All components are opened relative to pinned directories with no link following; device/inode/owner/type chains and exact path bytes bind location evidence. Search-only parents preserve recovery of known Trash children without requiring directory listing. Event-only metadata handles avoid opening special-object data streams.
- New scans retain optional, Codable location evidence alongside a location-independent object fingerprint. Plans and rules use byte-exact path keys, explicit path equality and length-prefixed tree records; canonical Unicode spelling, case, delimiters and newlines do not collapse distinct input records. Dot-component, remote and NUL paths are unavailable. Ordinary types are limited to regular files/directories; aliases and special objects fail closed. Bounded valid application metadata and internal framework-link moves/Restore remain covered.
- Cleanup holds the descriptor chain through native Trash and verifies the returned object when readable. Restore verifies the historical parent chain and uses descriptor-relative `renameatx_np(RENAME_EXCL)` with post-move verification. Pre-move rejections leave no false completed history; uncertain mutation outcomes retain their durable intent. No custom Trash, permanent deletion or copying fallback was introduced.
- Version-1 history and interrupted-operation reconciliation remain compatible, including the old fingerprint encoding. Records without historical parent evidence remain readable but require Finder Restore; accepting such an entry would weaken the new parent guarantee. New cleanup requires a fresh scan.
- All 96 tests in nine suites passed with the opt-in native journal corpus and real case-sensitive APFS volume enabled. Fixtures cover same-inode ancestor swaps, target/link replacement, token reuse, changed Restore sources/parents, occupied destinations, real mount/device boundaries, aliases, FIFOs/devices, case/Unicode/delimiter names, framework-link recovery and legacy reconciliation. Existing safety, duplicate, generated-data, leftover and journal suites pass.
- The native corpus preserves file contents, logical sizes, synchronized allocation counts, hard links, POSIX permissions, ACLs, extended attributes and stored Finder-tag data through real Trash/Restore. Sparse allocation and filesystem-native Unicode equivalence follow the host filesystem; no cross-volume/provider/unsupported-metadata guarantee is claimed. Both mounted images were ejected.
- Debug/native and release validation are recorded with the safety boundary in [Safety.md](../Documentation/Safety.md). Relevant reference checks and the remaining visual/runtime comparison gap are recorded in [reference-checks.md](reference-checks.md). Native Trash still resolves a pathname; descriptor-relative Restore still resolves a source basename. The final identity-check/move window is explicitly not claimed atomic.

- Final verification: debug and optimized release suites both pass (96 tests in nine suites); native journal Trash/Restore passes in both configurations. The nested-volume corpus passed with the disposable image mounted during debug validation and was then ejected; the later release run intentionally skipped that opt-in volume test. `git diff --check` passes.
