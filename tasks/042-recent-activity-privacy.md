# 042 — Add supported recent-activity privacy actions

Status: Backlog  
Priority: P3  
Phase: F follow-up — Complete explicit privacy review  
Depends on: [001](001-cleanup-plans.md), [003](003-scan-sessions.md), [021](021-privacy-workflows.md)

## Why

Recent-item references and application activity records are distinct from the documents they point to. A privacy action should explain which references change without implying the underlying files will be deleted or every app's private history can be cleared.

## Scope

- Inventory supported recent-item/activity mechanisms using current documented capabilities and bounded evidence. Identify the responsible app/system scope and unknown/unsupported mechanisms.
- Offer native controls/handoffs where supported. Do not modify arbitrary preference files, privacy databases, or app-private history stores based on guessed names.
- Separate removing references from removing files, browser history, and caches. Keep actions in Privacy with explicit category selection and concrete consequences.
- Use typed operation outcomes for reference-only actions that cannot use Trash. Show an actual recovery capability if one exists; otherwise do not offer fictitious Restore.
- Keep these actions outside automatic scans/cleanup and record minimal local outcomes without preserving the private history being cleared in logs.

## Acceptance criteria

- [ ] Each supported action identifies its exact scope and distinguishes references from underlying files.
- [ ] Unsupported or restricted mechanisms produce honest handoffs/unavailable states, not a claim of complete history removal.
- [ ] No document, app-private store, or protected privacy database is changed by an unrelated recent-items action.
- [ ] Outcome and recovery presentation match the actual supported operation, including failure/cancellation limits.

## Validation

Use injected providers and disposable fixture apps for recent references, denied access, stale entries, and operation failures. Verify current primary platform capabilities and never clear the user's real activity history as a test.

## Starting points

[PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift), task 021's category/consent model, and task 001's typed operation boundary. Spec: sections 57, 59–60, 91, and 93 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare recent-item categories, consequence language, action scope, and recovery claims before, during, and after implementation. Record in [reference-checks.md](reference-checks.md).

