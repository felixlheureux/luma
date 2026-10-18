# 041 — Assess binary and language-resource cleanup integrity

Status: Conditional backlog — omit mutation unless integrity can be preserved  
Priority: P3  
Phase: H — Optional bundle-integrity assessment  
Depends on: [002](002-filesystem-identity.md), [005](005-application-footprints.md), [020](020-application-updates.md)

## Why

Unused architecture slices and language resources may look reclaimable, but modifying a bundle can break its signature, runtime behavior, or updates. The spec explicitly permits omitting unsafe implementations.

## Scope

- Begin with read-only estimates for supported binary/resource structures, accounting for nested code, helpers, current architecture, translation/runtime compatibility, selected languages, and uncertain shared resources.
- On disposable fixture bundles, evaluate original signing integrity, launch behavior, nested code, updates, resource lookup, and complete recovery after any proposed transformation.
- Do not ad-hoc re-sign a third-party app to disguise loss of its original identity, silently rewrite installed bundles, or assume a backup copy makes an unsupported transformation acceptable.
- Produce a documented go/no-go decision. Only propose implementation if original integrity, supported updates, runtime behavior, and complete rollback can be demonstrated for a narrowly supported class.
- If the requirements cannot be met, keep mutations unavailable and document the omission. Read-only estimates must not inflate ordinary cleanup totals or imply guaranteed savings.

## Acceptance criteria

- [ ] Assessment evidence distinguishes read-only potential from a supported removable resource.
- [ ] Signing, nested components, runtime/resource use, updates, and rollback are evaluated with documented limits.
- [ ] Unsupported or integrity-breaking cases remain unavailable; no replacement signature is presented as preservation of the original.
- [ ] The final outcome is an explicit bounded implementation proposal or a no-go report, with no modifications to the user's/reference app bundles.

## Validation

Use original disposable fixture apps and legally available read-only metadata, with architecture/resource variations and intentional signing breakage. A fixture signature test is not proof of compatibility with arbitrary vendor apps. No paid credentials are requested for this assessment.

## Starting points

[Filesystem.swift](../Sources/LumaCore/Filesystem.swift), task 005's app model, task 020's update compatibility context, and [Safety.md](../Documentation/Safety.md). Spec: sections 20–21, 39, 93, and 104 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare estimates, support exclusions, consequences, and integrity claims without running reference bundle modification. Record observed claims separately from demonstrated guarantees in [reference-checks.md](reference-checks.md).

