# 039 — Assess narrowly supported Mail cache removal

Status: Conditional backlog — generated-data proof required  
Priority: P3  
Phase: H — Carefully extend mutation boundaries  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [008](008-community-rules.md), [029](029-mail-storage-review.md)

## Why

Mail storage review may identify apparent cache data, but the ability to size a folder is not proof that every attachment is safely downloadable again. Establish whether any bounded supported cache action can meet the safety model.

## Scope

- Evaluate specific current Mail storage layouts using primary evidence and disposable data. Distinguish proven generated copies from unique messages, account databases, local-only attachments, and unknown state.
- Require evidence of regeneration and coherent backup/recovery behavior for an exact supported target. A directory name, account presence, or old access date is insufficient.
- Assess Mail/helper activity, synchronization, version changes, database consistency, and permission behavior before enabling any action. Unknown activity or unsupported formats block mutation.
- If support is established, use a dedicated narrow policy, explicit review, durable intents, and verified recovery. Do not weaken general Apple-data protection or prune arbitrary database/attachment internals.
- If support cannot be established, publish a technical no-go decision and retain task 029's useful read-only review/native handoff. A no-go is a completed assessment, not a shipped cleanup capability.

## Acceptance criteria

- [ ] A reviewed capability decision lists exact supported versions/targets or explains why removal remains unavailable.
- [ ] No unique, local-only, synchronized-but-unverified, or unknown Mail data becomes a generated-cache candidate.
- [ ] Any enabled action passes fixture tests for concurrent sync, format changes, denied access, links, interruption, and occupied Restore destinations.
- [ ] Ordinary Clean and app-reset policies cannot use this work as a broad Apple-data exception.

## Validation

Use synthetic accounts/mail stores or disposable test-machine data only. Record the provenance and limits of regeneration evidence. Do not delete real Mail data, credentials, or messages to validate the feature.

## Starting points

Task 029's storage model, task 008's catalog, [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), and [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift). Spec: sections 14, 35, 80–83, and 91–94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect cache/user-data distinctions, activity handling, consequences, and recovery explanations. Reference labels are not proof of regeneration. Record the three checks and their limits in [reference-checks.md](reference-checks.md).

