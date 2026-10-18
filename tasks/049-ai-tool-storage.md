# 049 — Review AI-tool caches and local-model storage

Status: Backlog  
Priority: P2  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [005](005-application-footprints.md), [008](008-community-rules.md), [047](047-provider-aware-filesystem.md)

## Why

The compiled reference includes agent-footprint and local-model scanners that are not explicitly covered by the existing developer queue. AI tools can retain substantial generated data, but conversations, credentials, installed versions, and model assets require distinct handling. This is a demonstrated reference gap, not an implemented Luma capability.

## Scope

- Begin with read-only inventory for independently documented, version-verified tool layouts. Evaluate Claude, Codex, Cursor, Gemini/Antigravity, Ollama, and LM Studio separately; a name in the reference does not establish support or regeneration.
- Separate generated caches/logs, browser automation profiles, installed tool versions, downloaded model assets, and user state. Conversation history, memory, prompts, credentials, settings, project/worktree data, and unknown files are excluded from generated-data cleanup.
- Verify provenance using current primary vendor documentation and disposable fixtures. Do not copy reference rules, inspect credentials, execute agent tools to discover data, or assume a directory called cache is entirely disposable.
- For any supported generated-data rule, preserve exact path/child boundaries, owners, active-process checks, ignores, revalidation, normal review, Trash and verified Restore. Active/unknown tool state blocks mutation.
- Treat downloaded model weights as deliberately retained assets. Inventory model identity, size, store coverage and known sharing/reference information where supported. Do not sum shared blobs repeatedly or count assets as ordinary cleanup opportunities.
- Assess model/version removal separately against supported vendor interfaces, active-version/reference/lock checks and recovery limits. Provider/runtime operations need typed durable outcomes; never offer fictitious Trash/Restore or delete shared store internals directly.
- Use ordinary local files only under the shared provider policy. Unsupported/custom/remote layouts remain unknown or inspection-only; no background downloads or hosted-service connection is introduced.

## Acceptance criteria

- [ ] Every evaluated tool has an explicit supported/unsupported layout and version matrix with primary-source provenance.
- [ ] Inventory and review clearly distinguish cache, installed versions, model assets, and excluded user state; logical totals account for known shared content.
- [ ] Each enabled rule has positive and negative fixtures for active tools, links, replaced paths, ignored targets, unknown formats, and state adjacent to supported leaves.
- [ ] Installed active versions, shared/referenced model blobs, credentials, conversations, and projects cannot enter a generated-data plan.
- [ ] Any model/version mutation has its own reviewed support decision, verified operation semantics and honest recovery behavior; unsupported actions remain unavailable.

## Validation

Use synthetic profiles/stores, multiple manifests referencing one blob, active and stale locks, malformed metadata, custom locations, cloud-managed ancestors, and cancellation. Test core bypass attempts and regress existing rule, plan, ownership, and recovery checks. Never test removal against personal agent histories or installed models.

## Starting points

Task 008's catalog, task 005's ownership resolver, task 036's ecosystem support matrix, and [Rules.swift](../Sources/LumaCore/Rules.swift). See the [compiled reference audit](compiled-reference-audit.md) for the observed framework types and inspection limits. This is a reference-driven product extension; it is not claimed as an existing explicit requirement in the canonical specification.

Reference checkpoints: inspect agent/model category separation, footprint totals, active-version protection, review and failure states before implementation, during the working flow, and at completion. Record evidence and inaccessible states in [reference-checks.md](reference-checks.md).
