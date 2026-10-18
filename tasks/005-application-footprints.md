# 005 — Unify app ownership and footprint review

Status: Done
Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [003](003-scan-sessions.md)

## Why

Installed-app inspection checks four exact identifier paths, while leftovers also know named support directories. The two workflows should share ownership evidence and explain what part of an app's footprint is generated data, settings, or potentially valuable content.

## Scope

- Create a shared relationship resolver used by installed-app footprints, leftover discovery, and mutation validation. Reuse existing exact identifiers, explicit named mappings, and verified helper/container evidence without fuzzy folder-name inference.
- Model the relationship's evidence, classification, consequence, and read status. A match establishes ownership evidence, not permission to call all of its contents disposable.
- Present separate totals for the application bundle, generated data, settings/state, and potential user/application data, with a clear inspected total and coverage limits.
- Return readable relationships when another path is denied or changes during inspection. Distinguish absent data from unavailable size, and expose permission guidance where relevant.
- Extend app details with a clear review flow and scoped sorting/search. Show a total-footprint value only when that footprint was actually inspected; do not present bundle size as total app usage.
- Make known named paths available consistently for installed and removed owners. Shared group containers and ambiguous multi-owner data remain excluded from removal; running-owner and reinstall checks still apply.

## Acceptance criteria

- [x] A fixture app with an explicit named support mapping shows the same relationship evidence in installed and leftover workflows.
- [x] Similarly named unrelated apps/folders do not match, and helper ownership protects data while a parent owner remains installed.
- [x] Denying one relationship does not discard every other result or turn the missing size into zero.
- [x] Footprint categories and totals do not double-count overlapping paths and match the reviewed core plan.
- [x] Nothing is selected by default; uninstalling the bundle and removing related data remain explicit, separate choices.
- [x] SafetyEngine resolves/rechecks the same ownership policy used to display the candidate.

## Validation

Extend fixtures for explicit mappings, exact identifiers, helpers, reinstallation, denied reads, overlapping roots, ambiguous ownership, and shared groups. Use native previews for footprint groups, evidence disclosure, partial results, and review. All new mutation behavior must also pass task 002's boundary checks before release.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Models.swift](../Sources/LumaCore/Models.swift).

Spec: sections 36–43 and 108.4 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect application details, related-file grouping, leftover presentation, and uninstall review in the Downloads reference. Record what is observable in [reference-checks.md](reference-checks.md); keep Luma's stronger evidence disclosures and original layout.


## Implementation and evidence — 2026-10-18

- ApplicationRelationships centralizes approved identifier paths and the existing named mappings, evidence, category and consequences. Installed footprints and leftovers use it; SafetyEngine resolves it again at execution. Container metadata must match freshly. Conflicting explicit roots, shared groups, Apple/Luma data and fuzzy ownership remain excluded. Installed/embedded helpers protect leftovers; running identifiers, namespaces and verified embedded helpers gate app/data mutation.
- ApplicationFootprintScanner retains each readable relationship independently and distinguishes absent paths from unavailable sizes. A missing container metadata file does not claim that the container itself is absent. Categories cover bundle, generated data, settings/state and potential app/user data. Every candidate requires review; a generated classification alone is not disposal authority. Broader helper-owned data discovery and shared-group removal are not offered.
- Root suppression prevents overlapping selections. Per-object accounting counts hard links once across all categories and any selected subset; cross-category shared bytes are assigned in displayed category order. Inspected totals match core review plans. A footprint is only shown after inspection and makes no claim to cover every app location. Inventory continues to label measured bundle storage separately.
- Native details offer scoped path filtering, size sorting, visible coverage and permission/retry actions, category totals and evidence/consequence disclosure. Nothing starts selected. Bundle uninstall and related data are separate checkboxes. Filtering clears selection. Cleanup/Restore outcomes invalidate both completed footprint snapshot owners.
- `bash Scripts/test.sh`: 160 tests in 15 suites pass. Ten new tests cover named ownership parity, unrelated names, denied/absent sizes, overlapping roots and hard links, container metadata changes, conflicting ownership, embedded helper guards, provider changes, stale/ignored/symlink paths, and a generated-fixture journal move/restore preserving adjacent backup data. Existing reinstallation and task 002 boundary fixtures remain passing.
- Debug build succeeds. `bash Scripts/check-application-footprint.sh` passes native light/dark sheets, four groups, no initial selection, named evidence, partial/absent reads, separate bundle choice, actual review presentation with matching unique totals, permission retry and completed-snapshot invalidation. No native QA cleanup is executed.
- Own-window captures of partial, complete and review sheets were inspected in both appearances. Coverage text wrapping and permission-action dark contrast were corrected from those captures. Scroll content includes lower categories; captures only establish the visible portion and may omit native/layer-backed elements. Full keyboard/VoiceOver traversal remains task 007. The first checker run passed assertions but timed out exiting with a sheet open; dismissing the sheet before termination fixed the rerun. Reports/screenshots are temporary and untracked.
- Reference checkpoints and runtime inspection limits are recorded in reference-checks.md. App reset remains task 006; release/accessibility review remains task 007.

- Scan/session regressions pass in both appearances: 6,000-file inventory 0.936/0.947 seconds, maximum sampled main-actor delay 0.080/0.075 seconds, with cancellation, scoped retry, preview boundaries and window/menu/monitor lifecycle intact. These are fixture measurements on this machine.
