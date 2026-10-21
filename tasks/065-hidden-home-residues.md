# 065 — Reconcile hidden home-directory application data

Status: Done
Priority: P0  
Depends on: Completed 055; task 064 for Storage inspection navigation and central dotfolder protection

## Outcome

Residues finds meaningful hidden application data under the current user's home directory, including data left after an app was uninstalled, without calling every dotfolder unused or accidentally deleting developer credentials and shared configurations.

## Existing code

- `Sources/LumaCore/LeftoverScanner.swift`: currently scans explicit Library paths/known ownership rules; `skipsHiddenFiles` is used in Library enumeration.
- `Sources/LumaCore/ApplicationRelationships.swift`: exact owner relationships and conservative resolver.
- `Sources/LumaCore/Resources/CleanupRules.yaml`: versioned explicit paths and owner mappings.
- `Sources/LumaCore/ResidueObservations.swift`, `Sources/LumaApp/ApplicationsView.swift`, `Sources/LumaApp/ApplicationActions.swift`: saved observations, grouped UI, mutation and targeted invalidation.
- `Sources/LumaCore/SafetyEngine.swift`: final eligibility rules.

## Scope

1. Inventory `FileManager.default.homeDirectoryForCurrentUser` (macOS convention `~/` = `/Users/<username>`, not `/home/user`) for **top-level hidden directories**. Do not pass `.skipsHiddenFiles` for this specific inventory. Include possible nested candidates under `~/.config/`, `~/.cache/`, `~/.local/share/` only with bounded, staged enumeration and exact path boundaries. No unbounded recursive sweep on opening Residues.
2. Present a concise **Hidden app data** section/filter inside **Residues** (no new top-level destination), showing absolute/relative path, observed logical size/coverage, recognition reason and whether a matching app/CLI/tool is still installed. Keep observations during refresh; do not label unreadable/unmeasured as zero or clean.
3. Reconcile using explicit, versioned, curated ownership mappings and verifiable bundle/package evidence: bundle identifier, legitimate app inventory/embedded helpers/Launch Services, and (when 066 is available) Homebrew formula/cask installation. A similar folder name, reverse-DNS prefix or absent `.app` alone is **not** ownership evidence; CLI tools and shared folders can still use the data. Give outcomes: **verified absent owner / potential leftover**, **owner installed or shared / keep**, **unknown owner / inspect only**. Never automatically select/delete.
4. Extend the existing exact-path ownership/safety resolver with **known** home-relative dotfolder rules, not a generic 'any hidden folder' cleanup rule. Avoid duplicate residue entries if an explicit catalog rule overlaps another. Do not force unknown results into fabricated bundle-ID groups; retain exact bundle-ID groups where ownership is supported and a clearly separate unknown section.
5. On a successful app removal/Restore, refresh the **affected** owner mappings and hidden candidates (not all of `~/`). The current uninstall deliberately retains user data/Application Support; expose a compact **Review remaining data** link in the completed app outcome if relevant, with no automatic removal.
6. Explicitly protected/inspect-only by default: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config` root, `~/.local` root, `~/.cache` root, `~/.kube`, shell profiles, git configs/credentials, keychains, Luma's own persistence, symlinks/aliases, mounted volumes and all shared/group containers. A user-chosen safe leaf may be reviewed with exact path and consequence, but do not relax generic Storage safety for `~/Library`.

## Acceptance fixtures

- Recognized `~/.vendor-app` mapped to a verified absent owner is shown as a *review candidate* and stays unselected until explicit action; native Trash/Undo only after refreshed exclusive ownership and full identity validation.
- Same folder with owner installed, running helper, unknown lookup or CLI/Brew dependency is retained and non-actionable.
- Unknown `~/.mystery` is visible for inspection but has no invented owner or automatic cleanup eligibility.
- `~/.config/editor-a` and `~/.config/editor-b` are independently classified; `~/.config` itself is never an app-specific cleanup candidate.
- Protected credential folders, dotfiles, symlinks, ignored paths, swapped directories and denied access cannot be removed by residue bulk selection.
- Selection, scroll, exact owner groups and saved/partial results remain stable during refresh and app uninstall/Undo.

## Validation

Extend `Tests/LumaCoreTests/ResidueObservationTests.swift`, ownership resolution and SafetyEngine fixture suites; extend `Sources/LumaApp/CleanupFeedbackCheck.swift` / `Scripts/check-cleanup-feedback.sh` for accessible first results and post-uninstall remaining-data navigation. Use synthetic homes only.


## Implementation — 2026-10-21

- Added metadata-only top-level home inventory and staged `.config`, `.cache`, `.local/share` discovery in `HiddenAppData`. Unknown/protected directories are separate observations without fabricated owner groups or executable cleanup items. Names, paths, recognition reason, owner state and measured/unmeasured logical sizes remain explicit. Discovery is capped at 256 candidates, with bounded name inventories and no recursive unknown-folder measurement; at most eight mapped directories are measured with 2,000-entry limits.
- Catalog 2026.10.21.1 adds the documented default `~/.vscode` mapping, explicit CLI names and alternate owner exclusions. Credential/shared roots, shell/git configuration, keychains and Luma persistence cannot become hidden ownership mappings. The catalog keeps existing generated rules and legacy ownership decisions intact. Additional staged leaves are exercised through fixture-only catalogs; this task does not claim broad ecosystem recognition.
- Current apps, embedded helpers and fail-closed Launch Services evidence are reconciled with CLI metadata/process paths and retained supported Homebrew cask metadata. Unknown or present evidence retains the data. Homebrew dependency usage and comprehensive cask provenance remain task 066. No discovered executable is run.
- Only verified absent, fully measured exact-owner candidates enter the existing unselected residue groups. Fresh plan preparation and the journal recheck identity, location, ignores, ownership, activity, device/provider state and current owner/tool absence. Generic Storage cannot bypass these checks by selecting a mapped hidden root, a case variant or its descendants. No generic Library protection was relaxed.
- Added Hidden app data filtering and a separate inspect-only disclosure in Residues, with saved/progressive observations. A completed uninstall offers an actual pointer/keyboard-accessible Review remaining data control only when supported retained data exists. Navigation selects nothing; app removal and Restore refresh affected mappings, including alternate owners, while retaining unrelated unknown observations and selections.

## Validation evidence

- Full required `bash Scripts/test.sh` passes, then passes again at the owner's explicit rerun request: 368 tests in 38 suites, five opt-in skips; rerun test execution 58.126 seconds; final staged-credential hardening also passes all 368 tests in 50.099 seconds. New synthetic-home fixtures cover independent staged leaves, unknown ownership, installed/shared/CLI evidence, active helpers, protected mappings, stale/replaced directories, symlinks, denied access, measurement limits, ignores and exact-owner journal Trash/Undo while preserving adjacent data. Legacy catalog regression expectations remain unchanged for their original mappings.
- Debug app builds. Task-specific `check-cleanup-feedback.sh` passes Light/Dark/System: initial observations remain unselected; unknown data has no owner or measured size; credential data stays excluded; an installed synthetic Code owner retains `.vscode`; hidden observations persist; an actual native pointer opens the remaining-data owner; refresh stays owner-scoped, preserves unrelated unknown data and removes the link/candidate after app Restore. Existing direct residue Trash/Undo, group/mixed selection, navigation and narrow-window checks remain in this run. Light and Dark in-process window renders were inspected.
- On this M2/16 GB/macOS 27.0.1 environment, the first residue run used three initial residue paths/two owners and four later hidden observations: first results 0.235–0.241 s, saved load 0.005–0.015 s, selection-to-outcome 6.319–6.385 s including the deliberately held synthetic mover. These fixture timings do not represent a scan of a personal home.
- Native application/footprint/reset and direct uninstall/Undo checks pass Light/Dark/System on rerun. The initial direct-uninstall launcher attempt timed out at its unchanged 60-second limit and is excluded from acceptance; retained rerun reports pass without code, timeout or security-setting changes. Native cleanup-session Stop/partial/Undo checks pass Light/Dark.
- All mutation checks use disposable fixture homes and injected movers; no real Trash, personal-data cleanup, download/materialization, screen/audio capture or security-setting change was used. Full VoiceOver review and arbitrary custom CLI installation discovery are not established by these checks.

- Remaining native regressions pass: Storage in Light/Dark/System (1,400 nodes; direct file/folder Trash/Undo, mapped-folder protections, consistent selection and navigation), and scan sessions in Light/Dark (6,000-file inventory, cancellation, retry, partial results and navigation/window lifecycle). The task-specific residue checker was also rerun after the owner requested it; all hidden-data/remaining-data and existing direct-flow assertions pass in all three appearances. Rerun first results 0.230–0.239 s, saved load about 0.005 s, deliberately gated action 6.389–6.421 s.
- The source catalog validates as 22 generated rules and six named ownership mappings. Documentation links, shell syntax and diff whitespace checks pass. Existing task 064 working-tree changes were preserved.

- The required `Scripts/preview.sh` rebuilds the final debug app successfully but still fails its existing missing `Documentation/Screenshots/overview.png` check, also recorded in task 064. This generic launcher result is excluded from visual acceptance; dedicated in-process residue renders in Light/Dark were inspected, and task-specific native checks pass Light/Dark/System. The preview attempt preserved the existing tracked icon assets.
