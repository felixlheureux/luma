# 011 — Build a focused Downloads review

Status: Backlog  
Priority: P2  
Phase: A — More useful space recovery  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md)

## Why

Users should be able to review installers, archives, large downloads, and old files without navigating every folder or being told personal files are junk.

## Scope

- Add a dedicated review surface for an explicitly selected Downloads folder, with disk images, packages, archives, large files, age filters, and exact duplicate-download groups.
- Show previews where supported, paths, sizes, dates, and available download-source metadata. Missing source metadata stays unknown; a URL does not establish that a file is disposable.
- Distinguish browser/app download-history records from actual local files, including incomplete downloads and unavailable source metadata. Compiled reference tasks cover Chrome/Safari/Slack records; do not claim those integrations until independently supported.
- Separate user-downloaded installers from rule-backed generated installer caches. File extension or age alone never creates a Safe cleanup classification.
- Reuse the exact-duplicate engine and core keep-one policy. Let a user deliberately choose a keeper or select manually; no default removal selections.
- Reuse storage review, ignore rules, journal, and Restore. Do not move files just because a matching application appears installed.

## Acceptance criteria

- [ ] Filters and category totals have clear overlap semantics and do not inflate an executable selection's total.
- [ ] A similarly named or differently encoded installer is not presented as an exact duplicate without content verification.
- [ ] File previews and source metadata do not launch installers, download cloud contents, or open source URLs automatically.
- [ ] Selected personal files pass the same authorization and stale-result checks as manual storage actions.

## Validation

Use disposable Downloads fixtures with mixed extensions, missing metadata, nested folders, duplicate content, different same-name files, and changed keepers. Never use the user's reference DMGs as deletion fixtures.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), task 004's browser, and task 001's executor. Spec: sections 17–18, 50–51, and 55 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare file review, installer categories, previews, and duplicate-download decisions at the three required checkpoints. Log observations in [reference-checks.md](reference-checks.md).

