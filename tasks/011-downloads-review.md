# 011 — Build a focused Downloads review

Status: Done
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

- [x] Filters and category totals have clear overlap semantics and do not inflate an executable selection's total.
- [x] A similarly named or differently encoded installer is not presented as an exact duplicate without content verification.
- [x] File previews and source metadata do not launch installers, download cloud contents, or open source URLs automatically.
- [x] Selected personal files pass the same authorization and stale-result checks as manual storage actions.

## Validation

Use disposable Downloads fixtures with mixed extensions, missing metadata, nested folders, duplicate content, different same-name files, and changed keepers. Never use the user's reference DMGs as deletion fixtures.

## Starting points

[CleanStorageViews.swift](../Sources/LumaApp/CleanStorageViews.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), task 004's browser, and task 001's executor. Spec: sections 17–18, 50–51, and 55 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare file review, installer categories, previews, and duplicate-download decisions at the three required checkpoints. Log observations in [reference-checks.md](reference-checks.md).


## Implementation and evidence — 2026-10-18

- Added a Downloads destination and explicit folder chooser. Files show exclusive disk-image/package/archive/other/incomplete categories, intersecting size and modification-age filters, dates/paths/size, optional recorded origins and inline details. Type totals partition the inventory; overlapping large/old/duplicate views are never summed into an executable selection. Files remain Your files, with no default selection or installed-app-based removal.
- Bounded local discovery honors ignores and provider policy. Possible incomplete-name files/directories remain read-only unavailable entries; hidden/package/linked/shared/cross-owner/volume/provider contents are excluded. Only regular files are selectable; folders cannot overlap selected descendants. Browser/app history is explicitly separate: no Chrome/Safari/Slack databases are read or claimed. Generated installer caches remain in Clean.
- Refactored the existing duplicate hash pipeline into a shared verifier. Both tools use size, partial content and full SHA-256 with original identities; Downloads replaces known members with ordinary duplicate-rule items in every view. Explicit keeper selection selects only the other group members; manual selection is also available. Core keep-one proof, authorized scope, stale scan/tree/keeper checks and durable Activity/Restore remain authoritative. Filters/tabs clear selection, and mutation/Restore/Undo invalidate completed Downloads evidence and previews.
- Inline previews use only pinned bounded local bytes: plain literal UTF-8 text up to 64 KiB, or a small PNG/JPEG ImageIO thumbnail. Source metadata is an optional bounded property-list string array displayed as unverified literal text. No file URL is handed to Quick Look/extensions or a renderer, no installer/archive/code/HTML is executed, and no source URL is opened. Unknown, malformed, unsupported, changed or provider content remains unavailable.
- Sixteen disposable fixture tests cover mixed categories, overlap/intersection totals, nested folders, same-name different installers, Unicode-encoded/content differences, equal partial prefixes with different full hashes, deliberate keepers and keep-all rejection, same-size/timestamp-restored keeper edits, partial directories/files, source metadata bounds/malformed/missing states, literal/truncated/binary text, small raster previews, provider/link/hardlink changes, ignored roots/subtrees/keepers, unauthorized/forged/stale/replaced scopes, explicit limits/cancellation and recoverable Trash/Restore without overwriting a recreated download. The reference DMG is never a deletion fixture.
- Native light/dark checks of the built debug executable use only generated files: separate file/incomplete rows and type totals, all-personal classification, no default selection, plain text preview and unknown source state, one verified group, explicit keeper selection, actual Downloads-source confirmation sheet, stale-selection rejection, snapshot/preview invalidation and continued monitoring. These checks do not invoke Trash, an installer or a source URL. Saved Activity/history, ignore list and appearance/menu preferences retain their pre-check hashes.
- Own Files/preview, duplicate-group and confirmation captures are inspected in light/dark. They show filters/type totals, dates/path, unknown/unverified source wording, literal URL text, Your files badges and explicit copy choices. Lower entries/details require scrolling; fallback captures can omit native control fills. These checks do not replace a full manual folder-picker, keyboard/VoiceOver or actual Trash UI session. Core fixtures independently exercise moves/Restore in a disposable home.
- Reference checkpoints inspect CleanMyMac 5.7.2 in `protoypeopensourcemac.dmg`, read-only: installer review wording before implementation, OrganizeModule's local-download/provider-group and duplicate/filter wording during the working flow, and the same entries at completion. This is metadata/resource comparison, not a visual/end-to-end reference download or preview workflow. No reference executable/helper/cleanup, browser-history access or proprietary resource/code copying occurs.
- Remaining intentional scope: partial-state detection is name-based and cannot establish downloader activity; browser history integrations, PDF/HTML/third-party previews and linked/shared/provider files remain unsupported. These exclusions do not gain cleanup authority through a missing preview. Task 007's deferred manual accessibility/release checks and published Homebrew 0.2.0 asset remain unchanged.

Final validation: all **206 Swift tests in 19 suites** pass, including the shared duplicate verifier regression suite and 16 Downloads fixtures. Native light/dark Downloads checks and **66 navigation/layout samples across eleven pages** pass with monitoring/menu continuity and no mutations. Debug/release builds and strict local signature verification pass. The reference image is ejected; QA captures/reports and user-data hashes remain temporary and untracked.
