# 065 — Reconcile hidden home-directory application data

Status: Not started  
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