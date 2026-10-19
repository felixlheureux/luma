# 050 — Ship an early batch of broader cache discovery

Status: Done

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

- [x] Each evaluated family has a supported/unsupported decision; every enabled rule has provenance, consequences and positive/negative fixtures.
- [x] Synthetic installed apps expose supported cache leaves while adjacent settings, session state, personal data and shared containers remain untouched.
- [x] Running owners/tools, changed identities, links, forged descendants, protected paths and provider-managed ancestors fail core validation.
- [x] Category/app totals agree with non-overlapping accepted plans and don't imply guaranteed physical savings.
- [x] Reference comparison documents actual coverage differences, not just numbers of rules. No personal data is moved for validation.

## Validation

Use realistic synthetic app/container layouts, absent/denied roots, changed owners, active helpers, aliases, shared containers, nested roots and misleading cache names. Run existing rules, ownership, plan, journal and provider checks. Compare read-only local discovery before/after where authorized; keep private paths and reports out of commits.

## Starting points

[Rules.swift](../Sources/LumaCore/Rules.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), task 005's ownership work where available, and the contemporaneous audit (deleted in the core reset). Primary lead: [Electron app paths](https://www.electronjs.org/docs/latest/api/app). Spec: sections 8–13, 15, 80–86 and 96–97.

Reference checkpoints: compare category coverage, per-app grouping, details, active-owner messaging and partial coverage before/during/completion. Record evidence in [reference-checks.md](reference-checks.md).

## Implementation evidence — 2026-10-17

- [Cache-Support.md](../Documentation/Cache-Support.md) records the supported/unsupported matrix, exact primary provenance, ownership/layout checks, regeneration/diagnostic consequences and limits for every evaluated family. This batch enables four fixed units for VS Code stable 1.142.0, commit `6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1`: Cache, GPUCache, CachedData and logs. It does not infer that other Electron apps, sandbox containers or additional Xcode data have a verified policy. Existing 18 rules retain their scope; 22 bounded rules are now enabled in total.
- Installation metadata must agree on identifier, version, product name and released commit. Unsupported versions or absent/unreadable/changed owners produce skipped coverage when the target exists. Only complete directory units match. Sensitive siblings, parents, descendants, group containers, alias/link substitutions and provider-managed ancestors remain outside authority. The new rules are not automatically promoted into leftover-owner mappings.
- Core validation checks owners/helpers and process evidence again before each move. Unknown process collection blocks cleanup. VS Code/background-helper failures give a relevant quit instruction. Installed-product validation uses the same provider and pinned metadata boundaries as inspection.
- Clean groups results by app/category, offers read-only item details with path/consequence/owner and periodic app-activity hints, and keeps explicit whole-unit selection. Coverage names the app and distinguishes readable/empty/absent/blocked/skipped states. Tool/process evidence is authoritative only when checked at execution.
- Transient inode accounting produces unique logical totals for each category/group/subset and agrees with accepted plans. Cross-group hard links need not make category sums additive; the UI explains this beside both summary and groups. Final review revalidates selected totals. No physical savings guarantee is made.
- Cleanup attempts, partial outcomes and Restore invalidate generated arrays, coverage, selected generated IDs and completed app/controller snapshots, requiring a new scan. An unrelated completed feature remains available. Regression fixtures verify that a cancelled refresh cannot resurrect invalidated evidence.
- All **130 tests in 13 suites pass**. New tests cover synthetic installed metadata, four positive units, adjacent personal/session/offline data, shared/ambiguous containers, mismatched/linked owners, running owners/helpers/tools, stale content, denied/empty/missing/non-directory roots, forged paths, provider ancestors, cross-category hard links, pre-move owner changes and fixture-only journal Trash/Restore. Test-local app roots/activity snapshots avoid dependence on real installed/running apps. No personal data was moved.
- The final debug build succeeds. Native light/dark scan QA passes four-unit/two-group discovery, no default selection, 39 unique fixture bytes, matching review-plan size, actual review-sheet presentation and complete generated-snapshot invalidation, plus existing scan/permission/provider/navigation/window/menu checks. Only generated data is used; native QA does not execute cleanup. Final inventory timings were approximately 1.12/1.05 seconds for 6,000 files, with sampled main-actor delays approximately 0.09/0.07 seconds.
- [reference-checks.md](reference-checks.md) records all reference checkpoints, scope differences and static-only/visual-capture limitations. Real Electron cache regeneration, other product releases, arbitrary sandbox ownership and additional Xcode targets remain explicitly unsupported/unverified; they are not silently marked scanned or eligible. Broader selectable descendants and external rules remain tasks 031/008.
