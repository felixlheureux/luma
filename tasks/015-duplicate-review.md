# 015 — Improve exact-duplicate comparison and keeper choices

Status: Backlog  
Priority: P2  
Phase: B — Speed and deeper storage analysis  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [014](014-incremental-index.md)

## Why

Exact duplicate detection exists, but deciding which location to keep needs better context than a file list. Improve the decision without weakening content verification or selecting removals on arrival.

## Scope

- Add a comparison surface showing previews when supported, full paths, sizes, dates, and whether copies are hard links or independent files.
- Let the user explicitly apply a keeper choice, such as a selected folder or a date preference, with a preview of the resulting selection. Start with no removals selected.
- Support review filters and deterministic ordering for large group sets, including a focused entry point from Downloads.
- Reuse cached work only under task 014's invalidation policy; full content remains the basis for exact groups. Never group by filename or visual resemblance here.
- Keep the core keep-one and live-keeper checks authoritative. Changed or missing copies invalidate the relevant choice and require a fresh review.

## Acceptance criteria

- [ ] Every selection retains a verified, accessible keeper; direct core calls still cannot remove all copies.
- [ ] Explicit keeper actions show which paths would move before confirmation and never run automatically after a scan.
- [ ] Different same-name files and visually similar images stay outside exact groups.
- [ ] Keyboard/VoiceOver users can compare metadata, choose a keeper, and review removals without relying on thumbnails.

## Validation

Use fixture groups with matching/different contents, duplicate dates, nested paths, hard links, renamed files, unsupported previews, and changed keepers. Test group ordering and explicit selection policy, plus a fixture-only Trash/Restore cycle.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), task 001's executor, and task 014's hash cache. Spec: sections 53–55 and 94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare grouping, side-by-side information, keeper decisions, and final review where the reference supports them. Record observations in [reference-checks.md](reference-checks.md).

