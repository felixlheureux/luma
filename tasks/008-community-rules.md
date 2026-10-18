# 008 — Move cleanup knowledge into validated rule files

Status: Done
Priority: P2  
Milestone: Catalog foundation; brought forward by user request after closing 007
Depends on: [001](001-cleanup-plans.md), [005](005-application-footprints.md)

## Why

Open-source contributors should be able to add a supported cache path or ownership mapping without editing scanner logic. The existing 22 rules and named app mappings need a versioned format that cannot bypass core safety.

## Scope

- Define a versioned schema for stable IDs, exact bounded paths/profile leaves, owners, classification, explanations, consequences, regeneration, tool guards, and localized display text or keys.
- Add a project-owned `RuleLoader` boundary and evaluate Yams at implementation time under the spec's dependency policy. Keep parser types outside scanners and SafetyEngine.
- Migrate the current rules and ownership mappings without widening paths, lowering classifications, changing IDs, or losing active-tool checks. Package the validated catalog with the app.
- Validate duplicate IDs, traversal, protected roots, unsupported tokens, unrestricted globs, ambiguous ownership, missing explanations, and unsupported schema versions. Reject invalid catalogs with actionable diagnostics.
- Keep protected-path policy and runtime ownership/path validation in Swift. A catalog is evidence for a rule, not authority to override those checks. No remote rule downloads in this task.
- Add contributor instructions and a local/CI validation command using disposable positive and negative fixtures.

## Acceptance criteria

- [x] The migrated catalog produces the same supported candidates and exclusions as the existing 22-rule baseline.
- [x] A contributor can add one bounded rule and validate its fixtures without changing scanner control flow.
- [x] Invalid catalogs cannot produce executable cleanup plans or partially activate an unsafe rule set.
- [x] Runtime SafetyEngine checks still reject forged, stale, protected, or ownership-mismatched candidates even when their rule IDs exist.
- [x] Rules have reviewable provenance and version metadata, with no parser dependency in deletion decisions.

## Validation

Run schema-negative fixtures, candidate-equivalence fixtures, generated-data/leftover tests, and safety/journal tests. Review the chosen dependency's current maintenance and license before adding it; the plan does not pin an unverified version.

## Starting points

[Rules.swift](../Sources/LumaCore/Rules.swift), [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Package.swift](../Package.swift), and task 005's resolver.

Spec: sections 84–86, 99, 105, 106.5, and 110–111 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare the visible coverage and explanation of any migrated category against the reference where observable. Resource names alone do not validate cleanup paths. Record the comparison in [reference-checks.md](reference-checks.md).


## 2026-10-18 implementation and evidence

- Migrated the 22-rule baseline and five named ownership mappings from `ea11b37` into `Sources/LumaCore/Resources/CleanupRules.yaml`, schema 1/catalog `2026.10.18.1`. IDs, paths, classification, owners, profile leaves, product version/commit and existing display/removal text remain unchanged. The three Xcode/SwiftPM/Homebrew guards previously inferred from IDs are explicit fields with equivalent effective behavior. Named mapping explanations/consequences feed the actual relationship review and preserve their preceding wording.
- `RuleLoader` alone imports Yams. It returns immutable project-owned catalog values only after every record passes validation. Scans, relationship resolution and SafetyEngine require a successful catalog; display compatibility accessors provide no findings on failure. Invalid/missing catalogs cannot partially activate or pass mutation preflight. Installed apps resolve resources only inside their own resource directory; CLI/XCTest also support standard adjacent SwiftPM bundle layouts. There is no external runtime catalog setting or download.
- Rejections cover unsupported schemas/locales/fields, duplicate/reserved IDs, duplicate/overlapping roots, traversal/absolute/protected/unsupported paths, tokens/globs, missing explanations/consequences/regeneration/provenance, conflicting owners, unsupported profiles/product verifiers, broadened known browser profile roots/direct profile targets, and missing path-specific tool guards (including cache descendants). Parsing requires one mapping document, rejects aliases/anchors/custom tags and reports bounded parser diagnostics without dumping the entire YAML. Runtime filesystem/provider/ownership/identity/activity/plan/journal protections remain Swift policy.
- Evaluated and pinned the current Yams 6.2.2 release (`a27b21e0c81c5bf42049b897a62aaf387e80f279`, published 2026-05-26) and its MIT/libyaml licensing using upstream release/README/license evidence. `Package.resolved` pins the revision, and complete Yams/libyaml notices ship with the app. The parser remains isolated and statically linked; no parser values enter scanners or SafetyEngine.
- `bash Scripts/validate-rules.sh [catalog.yaml]` is the local/CI validator. Both workflows run it and the full Swift fixtures. Contributor instructions cover the schema, original path/lifecycle evidence, a disposable example and fixture commands. A proposed local file is validated without activating it. A duplicated-key CLI fixture exits nonzero with an actionable diagnostic.
- **175 Swift tests in 17 suites pass**, including seven new catalog tests: every legacy decision field and named mapping, every rule’s supported candidates/adjacent exclusions, schema-negative cases, conflicting/protected ownership, actual ownership review text, YAML failure modes and a contributor rule through the unchanged scanner with runtime rejection/preflight fixtures. Four Python release-validation tests pass; changed shell scripts and workflow YAML pass syntax checks. Full actionlint is not installed locally.
- Native light/dark scan checks pass from the app’s bundled resource: cache units/groups/39 unique bytes/no selection, actual review totals/invalidation, cancellation, exclusions and monitoring/menu/window behavior. 6,000-file timings: 1.011/0.967 seconds; maximum sampled main-actor delays: 0.076/0.081 seconds. Native footprint/reset checks pass again after mapping text integration. Cleanup Stop/Undo and window lifecycle regressions pass. All mutations remain injected/disposable; no personal files are cleaned.
- Hardened the debug scan checker to request its main window and allow SwiftUI to detach review/error sheets before Quit. An initial all-true report timed out at termination; a subsequent missing-window report was not treated as success. The final complete light/dark run passes and exits normally.
- Reference comparisons and limitations are recorded in `reference-checks.md`. This core catalog migration adds no supported cleanup family or path. Task 007 remains closed by user request with its manual/public-release gates deferred; this work does not claim a published 0.3.0 release.

Final packaged evidence: the release build and strict signature pass. The local 0.2.0 arm64 DMG passes image integrity, mounted executable/icon/version/license/readme checks, exact bundled YAML/third-party-notice comparisons, SHA-256 verification and release window/menu lifecycle. The image is ejected; generated installers, checksums and fixture reports remain untracked. This verifies distribution of the catalog without claiming the deferred public 0.3.0 release.
