# 061 — Restore Overview and simplify layout and input focus

Status: Planned
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

- [ ] Each new launch opens Overview; the six primary routes, Command-1–6, Activity Command-9, Search and explicit Overview routing agree. Existing-window reopening does not reset navigation.
- [ ] Overview is a concise live summary with current core shortcuts; neither Overview nor entering Storage starts discovery or revives old scan-first workflows.
- [ ] Apps/residue views avoid repeated headings and common paragraphs; residue child indentation, path alignment and explanation spacing remain clear at narrow widths. Details stay optional and selection/Trash behavior is unchanged.
- [ ] Click-away ends editing on all four input surfaces while preserving values, first-click actions and keyboard access.
- [ ] Storage's footer has one compact action row and conditional meaningful status, without blank reserved rows; Stop, Undo, availability and partial outcomes remain accurate and accessible.

## Validation and starting points

Source evidence at `c03e185`: `Destination.core` and startup state exclude Overview in `AppModel.swift`; `StorageActions.openCore` redirects it. `OverviewView` retains old Smart Check/Clean/duplicate links. `ApplicationsView` repeats uninstall scope per row and expands residue explanation/coverage. `StorageActionBar` reserves two fixed-height text rows, including a blank placeholder. Only Search currently owns explicit input focus.

Reuse native UI, residue and storage checkers with synthetic observations and injected movers. Check cold launch with fresh and old saved-page preferences, every Overview entry point, idle Storage, narrow layouts, residue alignment and footer states in Light/Dark/System. Exercise actual pointer and keyboard input: background, another field, action controls, Search arrows/Return/Escape and Tab traversal. Screenshots or direct model calls alone do not establish first-click/focus behavior. Record unavailable native checks as limits, not passes; follow [README](README.md) for relevant reference evidence.
