# 016 — Add volume selection and read-only external analysis

> Core reset, 2026-10-19: 056 replaces default manual volume/folder selection with automatic discovery; inspection does not broaden cleanup authority. See [the current queue](README.md). This file retains earlier implementation evidence.

Status: Done
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

- [x] The correct volume and scope remain visible throughout analysis and drill-down.
- [x] Unmounting or replacing a volume invalidates its live results and cached assumptions cleanly.
- [x] No external or protected node becomes executable cleanup merely because it can be browsed.
- [x] Available, free, purgeable, and logical scanned bytes are labeled without claiming guaranteed physical recovery.

## Validation

Use disposable disk images or injected volume providers for read-only media, identity replacement, unmounts, permission failures, and mount-point collisions. Verify that cleanup rejection tests still pass unchanged for external/protected paths.

## Starting points

Task 004's browser, task 014's index, [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), and [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift). Spec: sections 47–49, 66, 81, and 88 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare volume selection, capacity labels, navigation, and disconnected-volume behavior where observable. Record in [reference-checks.md](reference-checks.md).


## Implementation

Storage now captures volume UUID, device, filesystem ID, mount point and the descriptor-pinned root location. A completed hierarchy retains the selected scope and scan-time volume capacity/free/system-available observations independently of logical file totals. Outside-home, other-device and read-only targets have a core inspection-only gate; browsing never authorizes removal. Existing SafetyEngine/journal restrictions remain unchanged.

A native volume menu lists supported local volumes and retains the ordinary explicit folder chooser. Drill-down uses the existing list/map and breadcrumbs. The app checks root/volume availability every two seconds without traversing content and listens for native unmount events, so a rapid remount does not silently revive old results. Loss/replacement clears live storage snapshots/selections and cancels a storage refresh. Cached analysis retains its existing UUID/root/metadata/event checks before reuse.

Storage scans now carry captured ignore rules. Ignored subtrees are not traversed; an opaque package containing an ignored descendant has an unknown/partial size rather than being read for a total. Provider, permission and limit exclusions retain partial coverage.

Ten new core fixtures cover volume/root identity, replaced or missing roots, stale picker media, read-only broader-scope review rejection, ignored subtrees/package descendants, provider/permission failures, links/cancellation and the explicit inspection-root versus default mutation-root boundary. All 269 Swift tests in 25 suites pass, preserving external/protected cleanup rejection.

Native light/dark checks use an independently generated read-only APFS image. They verify volume/scope/readonly metadata, nested list navigation, no initial selection, both app/core review rejection and actual unmount invalidation of both snapshot owners, with monitoring continuing and no mutation. Own full-size analysis and unavailable-state captures were inspected in both appearances. An initial bare directory launch argument suppressed the main scene; the final harness passes the fixture root through its debug-only environment, explicitly opens the main window and validates capture dimensions. Earlier tiny status-window captures are not UI evidence. HFS+ feasibility attempts and initial launcher failures are not passing support evidence.

Existing native storage and cache regressions pass in both appearances. Storage records 1,030 nodes in 2.775s/2.784s on this machine/run; this is fixture evidence, not a general performance guarantee. No reference-image deletion fixture, real user-file cleanup, external mutation or restore is performed. Full keyboard/VoiceOver and physical-drive hotplug coverage remain unverified manual checks; the mounted APFS-image unmount is real.

The boot-volume picker uses an explicit internal inspection-only descriptor option for `/`; ordinary mutation pins retain root rejection. The volume choice captures its expected UUID/device/mount/filesystem identity, checked before hierarchy traversal. Unsupported filesystems remain behind the existing provider-capability policy; an initial HFS+ probe did not produce supported inspection results and does not establish HFS+ support.
