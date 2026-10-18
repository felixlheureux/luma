# 021 — Build explicit browser privacy and permission workflows

Status: Backlog  
Priority: P3  
Phase: D — Broader application and discovery tools  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [005](005-application-footprints.md), [008](008-community-rules.md)

## Why

Privacy currently provides settings shortcuts. Actual privacy actions need their own review model because history, cookies, sessions, and website storage are personal state with consequences different from cache cleanup.

## Scope

- Add supported browser/profile discovery with separate categories for history, cookies, website/session state, and other explicitly understood records. Keep these out of ordinary Clean results and presets.
- Start with a small, version-verified browser scope. Prefer supported browser controls/handoffs when deleting internal records cannot be implemented and validated safely.
- Explain concrete consequences such as sign-outs, lost sessions, and cleared history. Nothing is selected automatically; a browser/profile must be explicitly chosen.
- Require owning apps to stop, recheck profiles and identities, and preserve transactional database consistency for any supported mutation. Unsupported formats remain inspection-only or use a native handoff.
- Expand permission guidance using information macOS exposes legitimately. Do not read/rewrite private privacy databases or imply a complete permissions inventory when the platform does not provide it.

## Acceptance criteria

- [ ] Cache cleanup and Smart Check cannot silently select or remove privacy state.
- [ ] Each supported action names its browser/profile, affected category, and consequence before review.
- [ ] Running browsers, unknown formats, inconsistent databases, and changed profiles prevent unsupported mutation.
- [ ] Limited permissions and unavailable permission facts have truthful states and useful settings/browser handoffs.

## Validation

Use synthetic browser profiles and disposable database fixtures with transactions, linked paths, corrupt formats, denied reads, and profile replacement. Verify current primary browser/platform documentation before supporting a format. Never inspect or erase real browsing data in tests.

## Starting points

[PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift), task 008's catalog, task 001's executor, and [Rules.swift](../Sources/LumaCore/Rules.swift). Spec: sections 13, 57–60, 91, and 93 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare profile/category separation, consequence explanations, browser-running handling, and permissions handoffs. Record checks in [reference-checks.md](reference-checks.md).

