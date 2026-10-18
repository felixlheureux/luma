# 045 — Add privacy-preserving local diagnostics and export

Status: Backlog  
Priority: P2  
Phase: I — Explainable support and debugging  
Depends on: [001](001-cleanup-plans.md), [003](003-scan-sessions.md), [014](014-incremental-index.md), [028](028-contributor-tooling.md)

## Why

Users and contributors need to understand scan exclusions, failed operations, and performance problems without sharing a raw filesystem report, browser data, or process arguments that may contain secrets.

## Scope

- Define project-owned structured diagnostic events with operation/session IDs, versions, rule IDs, capability states, timings, and redacted error context. Keep detailed personal paths private by default.
- Add local retention/size limits and a user-visible diagnostics view. Avoid logging file contents, message/browser data, credentials, command arguments, serial numbers, or unneeded identity/content fingerprints.
- Make export explicitly user-triggered, previewable, and redacted, with a clear list of included fields. Apply sanitization to nested errors and free-text fields, not only known JSON keys.
- Keep exported analysis diagnostics distinct from the authoritative operation journal. Export/clear-diagnostics actions must not erase recovery evidence or mutate user files.
- Do not upload diagnostics, add telemetry, or enable automatic crash reporting. A future reporting transport would require its own explicit opt-in scope.

## Acceptance criteria

- [ ] Representative paths, account/device identifiers, tokens, process arguments, and nested error strings are excluded/redacted from default exports.
- [ ] Users can preview the exact export and choose its local destination without a network request.
- [ ] Retention remains bounded and diagnostic failures do not interrupt cleanup validation or journal commits.
- [ ] Clearing diagnostics leaves Activity, unresolved recovery, ignore rules, and analysis authorization intact.

## Validation

Use synthetic sensitive strings and nested event/error fixtures to verify redaction, retention, export previews, and failure paths. Check report usability by reproducing a fixture scan exclusion and interrupted operation without exposing the fixture's secret-like fields.

## Starting points

[LumaApp.swift](../Sources/LumaApp/LumaApp.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 028's support workflow. Spec: sections 2.5, 93, 101, and 108.16 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare diagnostic/help discovery and export explanations where accessible. Never export personal reference-app data merely to compare. Record the checks and limits in [reference-checks.md](reference-checks.md).

