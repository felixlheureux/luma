# 030 — Show Trash usage and clear recovery context

Status: Backlog  
Priority: P2  
Phase: B follow-up — Explain space already in Trash  
Depends on: [003](003-scan-sessions.md), [004](004-storage-browser.md), [016](016-volume-analysis.md)

## Why

Files already in Trash still occupy space. Luma should explain this plainly and connect its own Activity records to Finder's recovery controls without implying that a Trash move immediately reclaimed disk space.

## Scope

- Inspect accessible current-user Trash locations on supported mounted volumes, respecting identity, ownership, permissions, and volume lifecycle. Do not enumerate other users' Trash.
- Show logical usage, readable/partial/unavailable state, and the distinction between Luma's recorded moves and unrelated Trash contents.
- Provide Open Trash/Reveal actions and retain verified Restore for eligible Luma records. Unrecorded items use Finder rather than a guessed original path.
- Keep permanent emptying in Finder for this first slice; no automatic or broad permanent-delete implementation belongs in the cleanup executor.
- Explain that physical recovery depends on filesystem behavior and whether Trash is actually emptied. Do not add Trash usage to new cleanup totals as if the files were still elsewhere.

## Acceptance criteria

- [ ] Permission denial is shown as unavailable/partial, never a falsely empty Trash.
- [ ] Volume removal/replacement invalidates its usage and reveal actions safely.
- [ ] Activity records retain their verified identity/Restore rules; unknown items cannot receive an invented Restore destination.
- [ ] The feature performs no permanent deletion and never describes a simple move to Trash as confirmed physical savings.

## Validation

Use injected Trash/volume providers or disposable image fixtures, including mixed owners, stale records, unreadable folders, hard links, and removed volumes. Verify totals, navigation, and existing journal recovery without touching personal Trash contents.

## Starting points

[CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift), task 016's volume model, and task 004's inspection UI. Spec: sections 16, 47, 66, and 76 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare Trash usage labels, recovery context, permissions, and Finder handoffs. Inspect only; do not empty the user's Trash through either app. Record the required checkpoints in [reference-checks.md](reference-checks.md).

