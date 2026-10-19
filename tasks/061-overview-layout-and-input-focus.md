# 061 — Restore Overview and simplify layout and input focus

Status: Done
Priority: P1
Depends on: [054](054-direct-uninstall.md), [055](055-residues.md), [056](056-storage-discovery.md), [057](057-icloud-discovery.md)

## Outcome

Luma opens on Overview, daily views contain less repeated explanation, and clicking outside an input ends editing. Keep direct cleanup and the owner's idle-on-open Storage behavior.

## Scope

- Use the primary route order Overview, Storage, Apps, Residues, Maintenance, System consistently in the sidebar, Navigate and global Search, with Command-1 through Command-6 in that order and Activity on Command-9. Each new app launch opens Overview, superseding last-page startup even when an older saved page points to Storage. Give it a real route: `openCore(.overview)` must not redirect to Storage. Reopening an existing window preserves its current page; explicit destination actions still open their requested page.
- Reuse current live measurements and available observations for a concise Overview with shortcuts to Apps, Residues, Storage, Maintenance and System. Show collecting/unavailable states honestly. Do not restore the old Smart Check hero, separate Clean/Optimizer pages, duplicate-folder prompt or a scan prerequisite. Opening Overview or following its Storage shortcut does not start storage discovery; saved observations and explicit Scan remain as approved.
- Remove duplicated page headings and repeated common instructions. Apps needs one concise uninstall-scope explanation rather than the same paragraph under every app; technical ownership summaries belong in optional details. Keep action-specific exclusions, consequences, permission failures and outcomes accessible without making details a prerequisite.
- Make residue hierarchy clear: indent child rows beneath their exact owner header. Give an item's explanation a small gap below its path and align explanation/consequence text with the path text, not with the checkbox or owner header. Keep routine rows concise and longer evidence/coverage in optional disclosure; preserve group selection, hidden selections and the direct fixed-footer action. Add no panel or confirmation.
- Add consistent click-away editing behavior to Apps, Residues, Storage and global Search. Clicking noneditable background ends input focus without clearing values or selection. Clicking another field transfers focus normally; the first click on a button, checkbox, row or menu still performs its action. Preserve Search's intentional opening focus, typing, arrow/Return navigation, Escape dismissal and Tab/Shift-Tab. Scope any native handling to the relevant window and its lifecycle; no application-wide click interception or polling.
- Compact `StorageActionBar` to one action row with selection count/size, Deselect and the relevant Trash/Stop/Undo actions; Activity remains reachable. Show an additional concise status only for useful availability, progress or outcome information. Remove blank reserved text rows and repeated default instructions. Keep partial/failure/recovery outcomes, safe Stop and Undo intact, with usable narrow-window controls and stable feedback during an operation.
- Menu geometry and its two primary actions belong to [058](058-menu-panel.md); Storage Selected/map correctness belongs to 062; battery behavior belongs to 063. This task changes presentation and focus, not scanners, deletion authority or monitoring scope.

## Acceptance

- [x] Each new launch opens Overview; the six primary routes, Command-1–6, Activity Command-9, Search and explicit Overview routing agree. Existing-window reopening does not reset navigation.
- [x] Overview is a concise live summary with current core shortcuts; neither Overview nor entering Storage starts discovery or revives old scan-first workflows.
- [x] Apps/residue views avoid repeated headings and common paragraphs; residue child indentation, path alignment and explanation spacing remain clear at narrow widths. Details stay optional and selection/Trash behavior is unchanged.
- [x] Click-away ends editing on all four input surfaces while preserving values, first-click actions and keyboard access.
- [x] Storage's footer has one compact action row and conditional meaningful status, without blank reserved rows; Stop, Undo, availability and partial outcomes remain accurate and accessible.

## Validation and starting points

Source evidence at `c03e185`: `Destination.core` and startup state exclude Overview in `AppModel.swift`; `StorageActions.openCore` redirects it. `OverviewView` retains old Smart Check/Clean/duplicate links. `ApplicationsView` repeats uninstall scope per row and expands residue explanation/coverage. `StorageActionBar` reserves two fixed-height text rows, including a blank placeholder. Only Search currently owns explicit input focus.

Reuse native UI, residue and storage checkers with synthetic observations and injected movers. Check cold launch with fresh and old saved-page preferences, every Overview entry point, idle Storage, narrow layouts, residue alignment and footer states in Light/Dark/System. Exercise actual pointer and keyboard input: background, another field, action controls, Search arrows/Return/Escape and Tab traversal. Screenshots or direct model calls alone do not establish first-click/focus behavior. Record unavailable native checks as limits, not passes; follow [README](README.md) for relevant reference evidence.

## Implementation

- Restored the shared six-page primary route order and launch default; `openCore(.overview)` opens Overview without changing Storage state. Existing-window reopening retains its destination. Sidebar, Navigate shortcuts and Search consume the same route list.
- Replaced Overview's Smart Check hero and legacy workflows with availability-aware CPU/memory/disk summaries and five core shortcuts. Narrow layouts use compact metric rows. The sidebar also distinguishes collecting/unavailable/stale disk observations.
- Apps shows uninstall scope once above its filter and keeps per-app failures/eligibility inline. Residues has one page heading, optional coverage, indented children and explanations/consequences aligned beneath the path with a top gap.
- Added a window-content gesture observer owned by each main/Search host. It never recognizes or delays clicks, leaves editable hit-test ancestors to AppKit, and removes itself when the host leaves its window. No global event interception or polling is used.
- Storage's footer now has one action row (with a narrow fallback) and optional meaningful progress/outcome/availability text. Deselect, Stop, Undo and Activity remain available through the existing action owners. Outcomes remain visible alongside a newly blocked selection.
- Owner privacy correction: removed both screen-capture tool invocations from native QA and preview. Both now use a shared in-process AppKit view renderer without screen/audio recording permission. Fixed hit testing to use the content view’s superview coordinates, as AppKit requires.
- Added generated-observation native pointer/keyboard checks with debug-only geometry markers; updated Storage's previous five-route assertion for the restored Overview.

## Validation

- Dedicated native Overview/input checks pass 60 assertions on each of default and old Storage-preference launches. They cover all five Overview shortcuts, Command-1–6/9/K, idle Storage, all four input surfaces, first-click buttons/checkboxes, native field transfers, observer teardown, Search arrows/Return/Escape/Tab and reopened-window navigation. Fresh full-size in-process renders are verified and inspected in Light/Dark/System, including narrow layouts and collecting/unavailable/stale observations.
- Swift suite: 327 tests across 33 suites pass (five opt-in skips); debug arm64 app builds and strict deep signature verification pass. Diff whitespace and local documentation links pass.
- Existing native residue feedback checks pass Light/Dark/System, preserving exact groups, hidden selections, direct fixture Trash/Undo and narrow layout. Existing Stop/partial-session/Undo checks pass Light/Dark. Menu panel and window lifecycle checks pass; the appearance smoke checker passes 42 page/layout samples across Light/Dark/System and standard/increased-contrast appearances.
- Native Storage checks pass Light/Dark/System with 1,037 fixture nodes, idle cold/warm entry, actual Search, preserved selections, injected Trash/Undo, scope/outcome retention, narrow windows and settling. Requested discovery completed in 1.84–1.87 seconds on the final permission-free fixture run; timings are observations, not performance guarantees.
- `Scripts/preview.sh` was run before and after the privacy correction. Its old stale 38×38 output is now rejected/removed, and the standalone launcher still fails to write its main-window image, including when launched through LaunchServices. This launcher is excluded from acceptance. Dedicated native runs verify fresh full-size in-process renders in Light/Dark/System and supply the inspected layout evidence. View renders do not establish fully composited glass/window chrome. No recording permission is used by either image path.
- Intermediate checker failures are excluded: in-process SwiftUI accessibility traversal lacked control labels; geometry markers replaced it. The obsolete Storage route assertion was updated. Search presentation now waits for the native popover instead of assuming a fixed delay. A temporary checker window needed `isReleasedWhenClosed = false` under ARC; its diagnostic report locates the crash in the checker, outside production input handling. Intermediate checker compile errors were corrected before acceptance. Responder diagnostics also exposed a checker activation issue after closing the temporary window; pointer checks now use LaunchServices foreground launch, require an active key window, and wait for event completion. The shell passes an explicit fixture root because LaunchServices does not preserve its working directory. Auxiliary-window and close/reopen checks run after main-view input checks.
- No real Trash, personal-folder discovery, reference execution or proprietary asset copying was used. Full manual keyboard traversal/VoiceOver, system accessibility preference changes and macOS 26-specific integration remain unverified; the available native desktop is Apple M2/macOS 27.

Completion: task 061 is closed with the explicit standalone-preview and manual accessibility/platform limits above. Task 062 is next; Storage selection/map/continuation and M2 battery collection were not changed here.
