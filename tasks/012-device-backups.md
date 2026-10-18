# 012 — Inspect and review local iPhone and iPad backups

Status: Backlog  
Priority: P2  
Phase: A — More useful space recovery  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md)

## Why

Local device backups can account for substantial space, but they may be the only copy of important data. They need their own review context rather than a generic cache label.

## Scope

- Discover supported local backup locations using bounded, documented metadata checks. Show device name when available, backup date, logical size, completeness/read status, and multiple backups without exposing unnecessary identifiers.
- Treat backups as user data requiring review. Age, encryption, and an absent device are information, not proof that a backup is expendable.
- Build backup-specific validation for any removal path, including active backup/restore activity and unsupported metadata states. Unknown activity or identity blocks mutation.
- Keep a whole backup as the review unit; never offer arbitrary internal chunks as cleanup. Preserve the current global Library protection and use a narrowly verified policy rather than a broad authorization exception.
- Add reviewed Trash and Activity recovery only for backup formats/activity checks proven supportable. Unsupported backups remain inspection-only with a useful Finder handoff.

## Acceptance criteria

- [ ] Supported metadata fixtures show accurate device/date/size information; corrupt or partial backups are distinguished from empty ones.
- [ ] No backup is selected automatically or classified as an ordinary generated cache.
- [ ] Active or unknown backup activity, changed metadata, links, and unrecognized formats prevent removal.
- [ ] Supported fixture moves and Restore preserve the complete backup structure and refuse occupied destinations.

## Validation

Use synthetic backup structures and injected activity providers, including encrypted/partial metadata, multiple devices, denied reads, and interrupted operations. Do not inspect backup contents beyond required metadata or exercise removal against real backups.

## Starting points

[Filesystem.swift](../Sources/LumaCore/Filesystem.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 004's inspection UI. Spec: sections 19, 80–83, and 91 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect backup grouping, metadata, consequences, and unsupported states in the reference where accessible. Record the limits and decisions in [reference-checks.md](reference-checks.md).

