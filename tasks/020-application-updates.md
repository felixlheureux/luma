# 020 — Discover updates for installed applications

Status: Backlog  
Priority: P3  
Phase: D — Broader application and discovery tools  
Depends on: [003](003-scan-sessions.md), [005](005-application-footprints.md), [008](008-community-rules.md)

## Why

Applications should help users find supported updates and understand their source. This is separate from updating Luma itself and should start with trustworthy discovery rather than a general-purpose app replacement engine.

## Scope

- Define project-owned update-source adapters for supported vendor/Sparkle metadata and Homebrew metadata where applicable. Verify source ownership, channel, architecture, and version comparison for each supported rule.
- Assess App Store-managed applications and supported native update handoffs explicitly. The compiled reference includes a separate MAS source; do not scrape account state, infer unsupported availability, or silently install updates.
- Make network checks explicit and user-controlled, with caching, cancellation, timeouts, and clear last-checked/source details. Preserve local-first behavior outside the opted-in check.
- Distinguish available, current, unsupported, unknown, and failed checks. Do not infer update availability from a lexical version-string comparison alone.
- Prefer opening the app's native updater or verified official download page. Do not silently replace app bundles or run arbitrary installer URLs from untrusted metadata.
- Keep any future installation capability separately scoped to authenticated metadata and artifact verification. Discovery does not automatically authorize installation.

## Acceptance criteria

- [ ] Supported version/channel fixtures produce accurate outcomes, including prereleases and incomparable versions.
- [ ] Redirects, malformed feeds, source mismatches, and network errors cannot become trusted install actions.
- [ ] Every result identifies its source and check time; unsupported apps remain labeled unsupported.
- [ ] No background network request or app replacement begins without the relevant user action/preference.

## Validation

Use local feed fixtures and an injected network client for redirects, errors, channels, signatures/metadata fields, and cancellation. Review current source formats and dependency health at implementation time. Exercise handoffs with disposable app fixtures.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), task 005's inventory/evidence model, task 008's validated metadata, and task 003's coordinator. Spec: sections 37, 45, 71, and 93 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare update-source disclosure, unsupported/error states, version presentation, and native-updater handoffs. Log findings in [reference-checks.md](reference-checks.md).

