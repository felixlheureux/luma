# 029 — Explain Mail storage without treating attachments as junk

Status: Backlog  
Priority: P3  
Phase: D — Broader application and discovery tools  
Depends on: [003](003-scan-sessions.md), [004](004-storage-browser.md), [008](008-community-rules.md)

## Why

Mail storage can include downloaded cache copies, synchronized attachments, and unique local message data. Users need a useful breakdown before any removal feature can be justified.

## Scope

- Start with read-only inspection of supported, version-verified Mail storage metadata and explicitly selected exported/downloaded attachment folders.
- Distinguish known regenerable cache evidence, synchronized state, exported user files, and unknown/local-only content. Do not infer regeneration from a directory name or an account being configured.
- Show logical size, scope, coverage, and permission requirements without reading message content unnecessarily. Keep personal metadata out of logs and shared diagnostics.
- Provide Finder/Mail handoffs for supported review actions. Preserve global Apple-data protection; this task does not authorize deleting Mail database internals or attachment caches.
- Describe unsupported storage versions clearly and keep partial readable results separate from a complete mailbox analysis.

## Acceptance criteria

- [ ] Supported fixture layouts produce an understandable breakdown without a blanket junk/reclaimable label.
- [ ] Unknown or local-only data never becomes a cleanup candidate under this read-only feature.
- [ ] Denied access and unsupported formats remain visible and do not turn into zero-byte results.
- [ ] The feature does not modify mailbox databases, trigger message downloads, or expose message contents in diagnostics.

## Validation

Use synthetic layouts and minimal metadata fixtures for multiple accounts, local-only content, missing files, corrupt metadata, and denied access. Verify supported layouts from current primary platform sources where available; unverified formats remain unsupported.

## Starting points

Task 004's inspection model, task 008's rule/evidence format, [ScanSummaryView.swift](../Sources/LumaApp/ScanSummaryView.swift), and [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift). Spec: sections 14, 91, and 93 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare Mail storage categories, cache-versus-user-data distinctions, permissions, and handoffs. Do not run reference Mail cleanup. Record evidence and limits in [reference-checks.md](reference-checks.md).

