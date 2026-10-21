# 066 — Homebrew unused-dependency discovery and package-aware app uninstall

Status: Not started  
Priority: P0 for cask-uninstall correctness; P1 for discovery/cleanup UI  
Depends on: Completed 054, 059, 060

## Outcome

Luma identifies **orphan Homebrew formula dependencies** and stale caches, shows manually installed formulae/casks without falsely claiming they are unused, and does not leave Homebrew receipts inconsistent when uninstalling a Brew-managed `.app`.

## Existing code

- `Sources/LumaApp/ApplicationActions.swift` and `Sources/LumaCore/ApplicationUninstall.swift`: currently always use the native Trash bundle path; no Brew provenance check.
- `Sources/LumaApp/ApplicationsView.swift`: origin badge/action can be integrated without a duplicate app listing.
- `Sources/LumaApp/MaintenanceEntryView.swift`: appropriate small **Homebrew** section for discoverability.
- `Sources/LumaCore/Resources/CleanupRules.yaml`: covers `~/Library/Caches/Homebrew` only, not installed packages/dependency usage.

## Scope

1. Implement a small, injected **HomebrewProvider** read-only inventory. Detect installed Apple Silicon Homebrew executable/prefix from the actual current-user installation (typically `/opt/homebrew` but do not hardcode all file locations), verify executable owner/path, and execute fixed arguments using Foundation `Process` **without `/bin/sh`, sudo, or interpolation**. Bound/cancel subprocess work and report missing, broken, permission-denied or partial results explicitly. Use synthetic stub executable in tests.
2. Prefer machine-readable `brew info --json=v2 --installed` for formula/cask inventory and metadata. Compare with `brew list`/installed-on-request information as necessary. Obtain **authoritative orphan-dependency candidates** using `brew autoremove --dry-run`; obtain cleanup suggestions using `brew cleanup --dry-run` (outdated downloads/versions). `brew leaves` gives leaves, **not** unused packages; `--installed-on-request` marks manual origin, **not** frequency of use. Fail closed on unexpected CLI/schema output; never infer safe removal from a path name or age.
3. Show three clearly different states inside Maintenance's compact Homebrew section: **unneeded dependencies (Brew dry-run candidates)**; **stale downloads/versions (Brew cleanup candidates)**; **manually installed packages (usage unknown)**. Offer optional filter/badge **Installed with Homebrew** in Apps for casks. Avoid a new root page and avoid duplicating generic Cache/Storage results; explain overlap before totaling bytes.
4. Casks may install apps, fonts, services or command-line tools; absence of an `.app` is not proof the cask is unused. Link a cask to an Apps row only with verified installed artifact/provenance, not fuzzy basename. App last-opened Spotlight/Launch Services metadata, where present, is *supplemental*; do not infer 'never used' from missing dates, especially for CLI formulae.
5. **Correct the current uninstall seam:** if a row is verified as Homebrew-cask-managed, do not silently move only its `.app` to Trash while Brew still believes it is installed. Route to a provider-specific **Uninstall with Homebrew** action with clear irreversible-effect copy, accurate package/receipt changes, per-command result and post-action refresh, OR suppress the native row action with a precise explanation until that safe route is implemented. Keep native direct-to-Trash behavior for unmanaged apps. Do not claim Homebrew uninstall has Luma Trash Undo.
6. For optional Brew mutations, show current exact dry-run candidates and one explicit consequential approval, re-evaluate Homebrew state before executing the fixed command, and use the real Brew operation (not manual filesystem removal). Record success/partial/failure and re-inventory Apps/Residues/Storage only where relevant. Do not default to `brew uninstall --zap` (it may remove shared files), silently run `brew autoremove`, change pinned/manual package marks, delete Homebrew prefix directories, or create a general privileged helper. Consider services and active executable processes as conservative blockers/warnings; the Brew dependency graph does not capture every possible ad-hoc consumer.
7. Display unavailable last-used and size measurements honestly. Installation age, file modification time, 'leaf' status and unused-dependency status are four **different** facts. Homebrew may use separate, irreversible mutations; keep their status/history separate from native Trash Undo.

## Acceptance fixtures

- Absent/broken Brew executable yields an honest unavailable state, no crash and no mutation.
- Formula `app -> lib` keeps `lib`; a dependency `orphan-lib` reported by `autoremove --dry-run` is shown as **unneeded dependency**; manually installed leaf `git` is *not* labeled unused.
- A cask that installs only fonts/CLI is not classified as a missing `.app`. An installed matching cask app is marked Brew-managed; its native Trash-only uninstall is not permitted.
- Stub Brew changes its dry-run set between observation and action: Luma aborts/reviews changed candidates, does not silently execute an earlier set.
- Cask uninstall failure, auto-removal of dependent formulae, concurrent process/active service, invalid JSON and unexpected stdout retain precise partial outcomes. No fake Undo is offered.
- Refresh after genuine provider success updates Apps, residues and relevant saved observations, not unrelated selections or workflows.

## Validation

Add injected provider tests, fake Brew fixture output/commands, UI fixture coverage of provider-aware Apps and Maintenance behavior, and app-uninstall regression tests. Never execute commands against a real tester's Homebrew prefix. Use normal focused Swift tests and one final native M2 check.

## Primary sources

- `brew autoremove --dry-run`, `brew leaves --installed-on-request`, `brew cleanup --dry-run`, `brew uninstall --cask --zap` warning: https://docs.brew.sh/Manpage
- JSON info v2 behavior: https://docs.brew.sh/Querying-Brew
- Launch Services last-opened metadata limitations: https://developer.apple.com/documentation/coreservices/kmditemlastuseddate