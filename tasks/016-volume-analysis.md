# 016 — Add volume selection and read-only external analysis

Status: Backlog  
Priority: P2  
Phase: B — Speed and deeper storage analysis  
Depends on: [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [014](014-incremental-index.md)

## Why

Storage should explain selected internal and external volumes, while broader browsing must remain separate from permission to remove data there.

## Scope

- Add a volume/target picker with filesystem, mount point, capacity, available-space meaning, read/write capability, and accessible coverage.
- Allow explicitly requested read-only analysis of supported external volumes and broader internal targets. Respect package, cloud, ignore, permission, and traversal boundaries.
- Bind scan/index state to a volume identity and root generation. Handle removal, remounting, read-only media, and changed mount points without reusing an old path as authority.
- Present protected system locations and external-volume results as inspection-only. This task does not generalize the existing home-volume cleanup journal or enable external removal.
- Provide list-based navigation and honest partial totals when the full target cannot be read.

## Acceptance criteria

- [ ] The correct volume and scope remain visible throughout analysis and drill-down.
- [ ] Unmounting or replacing a volume invalidates its live results and cached assumptions cleanly.
- [ ] No external or protected node becomes executable cleanup merely because it can be browsed.
- [ ] Available, free, purgeable, and logical scanned bytes are labeled without claiming guaranteed physical recovery.

## Validation

Use disposable disk images or injected volume providers for read-only media, identity replacement, unmounts, permission failures, and mount-point collisions. Verify that cleanup rejection tests still pass unchanged for external/protected paths.

## Starting points

Task 004's browser, task 014's index, [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), and [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift). Spec: sections 47–49, 66, 81, and 88 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare volume selection, capacity labels, navigation, and disconnected-volume behavior where observable. Record in [reference-checks.md](reference-checks.md).

