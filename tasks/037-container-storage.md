# 037 — Explain container storage and assess bounded cleanup

Status: Backlog — runtime mutations require a separate verified policy  
Priority: P3  
Phase: F follow-up — Container developer storage  
Depends on: [001](001-cleanup-plans.md), [003](003-scan-sessions.md), [008](008-community-rules.md), [010](010-developer-projects.md)

## Why

Container storage can be large, but a runtime disk image, image layer, build cache, container, and persistent volume have very different ownership and recovery implications.

## Scope

- Begin with read-only supported Docker storage inventory through a verified local runtime interface, with explicit context/daemon identity and capability checks. Remote contexts do not represent local disk savings.
- Separate images/layers, build cache, stopped/running containers, and volumes. Do not add shared/reclaimable estimates together without accounting for their meaning.
- Keep persistent volumes, runtime disk images, and unknown/local-only content outside generated-data cleanup. Never delete runtime backing files directly or run a blanket system-prune command.
- Assess removal only for explicitly addressable supported objects with current usage/reference checks. Do not invent a dry-run or exact-object guarantee that the runtime does not provide.
- Any supported runtime mutation needs a typed core operation, durable intent/outcome evidence, explicit consequences, and honest recovery limits. It is not a FileManager Trash move and must not offer a fictitious Restore.

## Acceptance criteria

- [ ] Local, remote, unavailable, and replaced runtime contexts are distinct and cannot reuse another context's object identities.
- [ ] Shared layers, persistent volumes, running workloads, and ambiguous estimates are handled without inflated savings or broad deletion.
- [ ] Any enabled action targets explicit reviewed objects and stops if references/activity change; unsupported operations stay inspection-only.
- [ ] Runtime actions cannot bypass the core policy by treating a disk image or volume as an ordinary cache folder.

## Validation

Use injected runtime responses for shared layers, context changes, active builds, missing capabilities, and failed operations. Integrate only with disposable containers/images and fixtures; never prune the user's runtime. Verify current official runtime APIs and command semantics before enabling actions.

## Starting points

Task 010's developer review, task 001's operation boundary, [CleanupActivity.swift](../Sources/LumaCore/CleanupActivity.swift), and [Models.swift](../Sources/LumaCore/Models.swift). Spec: sections 15, 52, 80, 93, and 108.3 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare container categories, shared-space terminology, review actions, and consequences where the reference exposes them. Record observable behavior and limitations in [reference-checks.md](reference-checks.md).

