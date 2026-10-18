# 015 — Improve exact-duplicate comparison and keeper choices

Status: Done
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

- [x] Every selection retains a verified, accessible keeper; direct core calls still cannot remove all copies.
- [x] Explicit keeper actions show which paths would move before confirmation and never run automatically after a scan.
- [x] Different same-name files and visually similar images stay outside exact groups.
- [x] Keyboard/VoiceOver users can compare metadata, choose a keeper, and review removals without relying on thumbnails.

## Validation

Use fixture groups with matching/different contents, duplicate dates, nested paths, hard links, renamed files, unsupported previews, and changed keepers. Test group ordering and explicit selection policy, plus a fixture-only Trash/Restore cycle.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), task 001's executor, and task 014's hash cache. Spec: sections 53–55 and 94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare grouping, side-by-side information, keeper decisions, and final review where the reference supports them. Record observations in [reference-checks.md](reference-checks.md).


## Implementation

Shared folder/Downloads comparison now supports complete-group path/size filters, deterministic savings/path/modification ordering, per-copy full paths and modification dates, explicit bounded local text/raster previews, creation dates and filesystem-link counts. At most 100 previews are loaded for one explicitly opened group; additional paths and keeper actions remain paginated. Unsupported previews retain metadata and ordinary controls. Hard-linked aliases count once, and shared-byte recovery limits are explicit.

Explicit path or oldest/newest-modified choices produce a separate preview of the keeper and every proposed removal. Applying replaces only that group's selection after current full-content, identity, location, access, ignore and age checks. No file moves during preparation or application. Ordinary cleanup review and journal execution retain their independent full-content keeper checks. Filter changes clear the affected selection; rescans and invalidation clear comparison/proposal state.

Eleven new synthetic fixtures cover stable filters/date ties, nested/renamed/unsupported files, mismatched names/encodings, hard links, forged digests and same-size/restored-date edits, missing/stale/ignored/provider/denied/linked paths, cancellation and fixture journal/Restore. All 259 tests in 24 suites pass. Native light/dark fixtures verify comparison metadata/previews, no initial selection, proposal-before-selection, ordinary confirmation, changed-keeper rejection, preserved Activity/ignores and continued monitoring. Downloads checks pass in both appearances; 72 appearance/contrast/page layout samples pass.

All decisions use native text, checkboxes and buttons with full-path accessibility labels and explicit keyboard-cancellable proposal sheets; thumbnails are supplementary. Own light/dark comparison captures were inspected. An in-process accessibility-tree probe exposed only the window, so it was removed rather than presented as a passing VoiceOver action. Full keyboard/VoiceOver traversal remains an unverified manual release gate. Native cleanup is never invoked; only the injected fixture mover exercises Trash/Restore.

Final native captures target the actual attached keeper and confirmation sheets, rather than the underlying main window. Both appearances pass after the QA-only correction. The final reference comparison repeats the same OrganizeModule date/group/filter resources; runtime reference and complete VoiceOver sessions remain unverified.
