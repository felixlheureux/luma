# 005 — Unify app ownership and footprint review

Status: Ready
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

- [ ] A fixture app with an explicit named support mapping shows the same relationship evidence in installed and leftover workflows.
- [ ] Similarly named unrelated apps/folders do not match, and helper ownership protects data while a parent owner remains installed.
- [ ] Denying one relationship does not discard every other result or turn the missing size into zero.
- [ ] Footprint categories and totals do not double-count overlapping paths and match the reviewed core plan.
- [ ] Nothing is selected by default; uninstalling the bundle and removing related data remain explicit, separate choices.
- [ ] SafetyEngine resolves/rechecks the same ownership policy used to display the candidate.

## Validation

Extend fixtures for explicit mappings, exact identifiers, helpers, reinstallation, denied reads, overlapping roots, ambiguous ownership, and shared groups. Use native previews for footprint groups, evidence disclosure, partial results, and review. All new mutation behavior must also pass task 002's boundary checks before release.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Models.swift](../Sources/LumaCore/Models.swift).

Spec: sections 36–43 and 108.4 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect application details, related-file grouping, leftover presentation, and uninstall review in the Downloads reference. Record what is observable in [reference-checks.md](reference-checks.md); keep Luma's stronger evidence disclosures and original layout.

