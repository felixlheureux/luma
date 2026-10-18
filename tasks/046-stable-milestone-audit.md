# 046 — Audit the supported product scope before a stable milestone

Status: Backlog  
Priority: P2  
Phase: I — Release readiness across the supported product  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [007](007-native-ux-and-release.md), [025](025-localization-accessibility.md), [028](028-contributor-tooling.md), [044](044-scale-and-resilience.md), [045](045-local-diagnostics.md)

## Why

The task count is not a measure of product completeness. A stable milestone needs a supported-feature manifest, evidence against the canonical spec, and truthful limits for optional or unsupported capabilities.

## Scope

- Audit [spec-coverage.md](spec-coverage.md) against the actual code, tests, UI, packaged app, and completed task evidence. Distinguish Implemented, Partial, Planned, Unsupported, Deferred, and conditional No-go.
- Define the release's included capabilities and their OS/architecture/hardware matrix. Every included task must meet its acceptance criteria; excluded backlog does not become a hidden promise.
- Run end-to-end fixture workflows for scan, ignore, review, core validation, Trash/typed operations, partial failure, restart recovery, and appropriate Restore/handoffs.
- Review accessibility, appearance, progress/error states, monitoring overhead, local privacy, support diagnostics, licensing, documentation, and contributor reproducibility across the included feature set.
- Reuse and extend release validation, lifecycle checks, final-DMG payload inspection, published checksum verification, and the reference-comparison matrix. Plan recovery from a bad release without overwriting published artifacts or weakening validation.
- Track distribution credentials separately from engineering evidence. Task 027 remains conditional; do not request enrollment again or block unrelated supported development work on it.

## Acceptance criteria

- [ ] Every mature-spec area has an honest status and evidence link; planned navigation/screens are not counted as complete features.
- [ ] Included capabilities pass their acceptance criteria and the tested platform matrix matches public claims.
- [ ] Optional/no-go/deferred features are documented accurately, without false safety, recovery, hardware, or distribution guarantees.
- [ ] Fixture-based end-to-end and packaged-release checks pass, and remaining release-scope decisions are explicitly recorded.
- [ ] The release notes/README describe the actual supported product, with no claim that the full canonical spec is finished while gaps remain.

## Validation

Use the current relevant test suites, task 044's benchmark/fault evidence, native accessibility/lifecycle review, a clean checkout build, and the actual downloaded release artifact. Record real test counts and hardware coverage rather than carrying forward an old baseline number.

## Starting points

[spec-coverage.md](spec-coverage.md), [Roadmap.md](../Documentation/Roadmap.md), [Safety.md](../Documentation/Safety.md), [Distribution.md](../Documentation/Distribution.md), and [release.yml](../.github/workflows/release.yml). Spec: sections 93–104 and 110–113 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: perform a feature-by-feature comparison of the supported release with the current Downloads reference images, inspect the final Luma installer separately, and log actual workflow evidence/limits in [reference-checks.md](reference-checks.md).

