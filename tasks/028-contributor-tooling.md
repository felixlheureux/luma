# 028 — Establish code structure, quality checks and contributor tooling

Status: Ready — phase A  
Priority: P1  
Phase: Early engineering foundation; later community tooling  
Depends on: None for phase A; phase B rule-validation integration depends on [008](008-community-rules.md)

## Why

An open-source alternative needs an understandable contribution path and consistent review standards. Rule additions, regression fixtures, native UI checks, and release preparation should be reproducible by someone outside this conversation.

## Scope

Phase A starts now. Establish conventions and a formatting baseline before broad feature growth; integrate responsibility refactors into tasks 003/048/017 instead of blocking all feature work on a whole-repo rewrite. Phase B adds rule-validator/contribution integration after 008. Mark the full task Done only after both phases meet their criteria.

- Apply the target ownership/layout in [Architecture.md](../Documentation/Architecture.md) incrementally: app composition, feature-owned state/views, shared UI, core domains and narrow macOS adapters. Keep two package targets until a concrete dependency/testing need justifies another.
- Split unrelated screens/scanners during focused changes. Reduce AppModel's responsibilities as session, monitoring and cleanup state owners are introduced; new features use explicit composition instead of hidden singleton/service-locator dependencies.
- Keep SwiftUI/presentation out of core values and system-sampling policy. Inject clocks/filesystem/process/subprocess boundaries where meaningful deterministic fixtures need them; do not add protocols for every type.
- Define typed unavailable/partial/cancelled/stale states, async ownership and actor boundaries. Preserve one ordinary cleanup executor and documented journal/recovery invariants.

- Add a small, pinned formatting setup using the spec-approved SwiftFormat after checking current compatibility/license. Separate a one-time mechanical formatting change from behavioral work.
- Document local build/test prerequisites, rule validation, disposable fixtures, reference-DMG checkpoints, native preview limitations, and release validation.
- Add concise issue/PR templates that capture the actual problem, expected behavior, affected paths/rules, and relevant evidence without demanding irrelevant boilerplate.
- In phase A, make formatter checks reproducible locally/CI with the pinned version. In phase B, add the catalog validator when it exists. Preserve the existing safety/release/build/signature checks. Keep dependencies and action versions reviewable; avoid broad new tooling without a demonstrated benefit.
- Document how to add a supported app mapping or cache rule, including negative ownership/path fixtures and the boundary between rules and core safety policy.

## Acceptance criteria

- [ ] Phase A: architecture/contribution guidance defines code ownership, dependency direction, concurrency, test seams, error/metric states and artifact hygiene without claiming planned reorganization is already done.
- [ ] Phase A: formatting is pinned and checked consistently in local/CI workflows; mechanical churn is isolated from behavioral changes.
- [ ] Phase A: the first focused feature migration demonstrates the documented boundaries and preserves behavior; no unneeded framework/target explosion is introduced.

- [ ] A new contributor can build, validate a bounded rule change, and run its safety fixtures from documented instructions.
- [ ] Formatting is deterministic and can be checked locally with the same version/configuration as CI.
- [ ] Templates and review guidance reinforce evidence and safety boundaries without treating every cosmetic change as a filesystem-risk change.
- [ ] No third-party asset, private diagnostic path, reference DMG, or secret is required in the repository for routine contribution checks.

## Validation

Follow the contributor instructions from a clean checkout and create a disposable example rule change plus a rejected unsafe rule. Verify formatting idempotence and CI behavior. Keep any new automated checks proportionate to the behavior they protect.

## Starting points

[CONTRIBUTING.md](../CONTRIBUTING.md), [ci.yml](../.github/workflows/ci.yml), [Scripts](../Scripts), task 008's rule validator, and [reference-checks.md](reference-checks.md). Spec: sections 86, 94, 105–106, and 110–111 in the [product specification](../Documentation/Product-Spec.md).

Architecture planning uses Luma code/CI inspection; compiled reference metadata cannot establish maintainable source structure. No reference UI parity is required for a file-only move or mechanical formatting change. Feature changes still perform their relevant reference checkpoints.

Reference checkpoints: verify that contributor documentation preserves the recurring reference review process and clearly separates reference observations from copied assets or assumed internals. Record any documentation gaps in [reference-checks.md](reference-checks.md).

