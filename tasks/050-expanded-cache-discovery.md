# 050 — Ship an early batch of broader cache discovery

Status: Planned  
Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [047](047-provider-aware-filesystem.md)

## Why

The compiled reference exposes more cache families than Luma's 18 current rules. More useful discovery should not wait for the full storage browser and external rule catalog. Split the first bounded rule batch from task 031's deeper child-selection UI.

## Scope

- Build a support matrix for named Electron apps, exact sandbox-container cache leaves, application/diagnostic logs, and additional Xcode generated data. Prioritize supported layouts that add useful coverage on ordinary Macs, not an arbitrary rule-count target.
- Independently verify each path, owner, supported layout/version, regeneration behavior and active-app/tool guard from current primary documentation and disposable fixtures. Static reference constants are leads, not deletion authorization.
- Enable only verified exact cache/log targets. Electron session data may mix caches, cookies, local storage and state; supported cache leaves must exclude adjacent sessions, offline content, credentials and application data. Container ownership must be verified; shared/ambiguous containers remain excluded.
- Use the current Swift rule boundary for this first batch. Task 008 later migrates validated rules without widening them. Support fixed, rule-declared leaves under a verified owner root where necessary; no arbitrary descendant cleanup or unrestricted Library traversal.
- Keep system/Darwin/App Store stores and simulator devices/runtimes out of this batch unless a separately documented supported policy establishes eligibility. No privileged helper is introduced.
- Present findings grouped by app/category with size, path, consequence, owner/activity status and readable/empty/absent/blocked/skipped coverage. Provide read-only expandable details; removal selects complete supported rule units. Deeper selectable descendants remain task 031.
- Reuse complete plans, unique logical totals, provider policy, explicit selection, durable journal, Activity and Restore. Invalidate affected findings after changes or partial outcomes.

## Acceptance criteria

- [ ] Each evaluated family has a supported/unsupported decision; every enabled rule has provenance, consequences and positive/negative fixtures.
- [ ] Synthetic installed apps expose supported cache leaves while adjacent settings, session state, personal data and shared containers remain untouched.
- [ ] Running owners/tools, changed identities, links, forged descendants, protected paths and provider-managed ancestors fail core validation.
- [ ] Category/app totals agree with non-overlapping accepted plans and don't imply guaranteed physical savings.
- [ ] Reference comparison documents actual coverage differences, not just numbers of rules. No personal data is moved for validation.

## Validation

Use realistic synthetic app/container layouts, absent/denied roots, changed owners, active helpers, aliases, shared containers, nested roots and misleading cache names. Run existing rules, ownership, plan, journal and provider checks. Compare read-only local discovery before/after where authorized; keep private paths and reports out of commits.

## Starting points

[Rules.swift](../Sources/LumaCore/Rules.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), task 005's ownership work where available, and the [compiled audit](compiled-reference-audit.md). Primary lead: [Electron app paths](https://www.electronjs.org/docs/latest/api/app). Spec: sections 8–13, 15, 80–86 and 96–97.

Reference checkpoints: compare category coverage, per-app grouping, details, active-owner messaging and partial coverage before/during/completion. Record evidence in [reference-checks.md](reference-checks.md).
