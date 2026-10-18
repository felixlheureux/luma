# 008 — Move cleanup knowledge into validated rule files

Status: Backlog  
Priority: P2  
Milestone: After 0.3.0  
Depends on: [001](001-cleanup-plans.md), [005](005-application-footprints.md)

## Why

Open-source contributors should be able to add a supported cache path or ownership mapping without editing scanner logic. The existing 18 rules and named app mappings need a versioned format that cannot bypass core safety.

## Scope

- Define a versioned schema for stable IDs, exact bounded paths/profile leaves, owners, classification, explanations, consequences, regeneration, tool guards, and localized display text or keys.
- Add a project-owned `RuleLoader` boundary and evaluate Yams at implementation time under the spec's dependency policy. Keep parser types outside scanners and SafetyEngine.
- Migrate the current rules and ownership mappings without widening paths, lowering classifications, changing IDs, or losing active-tool checks. Package the validated catalog with the app.
- Validate duplicate IDs, traversal, protected roots, unsupported tokens, unrestricted globs, ambiguous ownership, missing explanations, and unsupported schema versions. Reject invalid catalogs with actionable diagnostics.
- Keep protected-path policy and runtime ownership/path validation in Swift. A catalog is evidence for a rule, not authority to override those checks. No remote rule downloads in this task.
- Add contributor instructions and a local/CI validation command using disposable positive and negative fixtures.

## Acceptance criteria

- [ ] The migrated catalog produces the same supported candidates and exclusions as the existing 18-rule baseline.
- [ ] A contributor can add one bounded rule and validate its fixtures without changing scanner control flow.
- [ ] Invalid catalogs cannot produce executable cleanup plans or partially activate an unsafe rule set.
- [ ] Runtime SafetyEngine checks still reject forged, stale, protected, or ownership-mismatched candidates even when their rule IDs exist.
- [ ] Rules have reviewable provenance and version metadata, with no parser dependency in deletion decisions.

## Validation

Run schema-negative fixtures, candidate-equivalence fixtures, generated-data/leftover tests, and safety/journal tests. Review the chosen dependency's current maintenance and license before adding it; the plan does not pin an unverified version.

## Starting points

[Rules.swift](../Sources/LumaCore/Rules.swift), [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Package.swift](../Package.swift), and task 005's resolver.

Spec: sections 84–86, 99, 105, 106.5, and 110–111 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare the visible coverage and explanation of any migrated category against the reference where observable. Resource names alone do not validate cleanup paths. Record the comparison in [reference-checks.md](reference-checks.md).

