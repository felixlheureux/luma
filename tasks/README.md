# Luma task queue

Plan prepared on 2026-10-17 against Luma 0.2.0, commit `d471bbcee58d816b5c5cc8ec0036fcdc1546d6e9`. Task states below track implementation separately from planning; creating a task never marks its feature implemented. The [complete specification](../Documentation/Product-Spec.md) remains canonical.

## Next milestone: 0.3.0

Make storage exploration and application review useful enough for daily use. Start with core selection guarantees, provider-aware access, and visible cleanup sessions with Stop/Undo. Then expand verified cache discovery, improve scan responsiveness, storage navigation, app footprints, and reset. Finish with a focused native UI and release review.

The 0.2.0 baseline provided the reason for this order; tasks 001–003 now close the first three gaps:

- Duplicate keep-one protection is checked in `AppModel.review`; the core mutation API validates individual items. Selection-wide guarantees belong at the mutation boundary.
- `Filesystem.validatePath` and the final Trash call use pathnames. Descriptor-based checks can strengthen identity validation, but the remaining native API race needs an honest boundary.
- `AppModel` shares one busy flag and scan task; application inspection starts a separate, untracked task. Inventory waits for bundle sizes before returning anything.
- Storage lists immediate children, and its map opens Finder instead of navigating. It cannot answer where space went inside a large folder.
- Installed-app footprints use four exact identifier paths. Named ownership mappings already used for leftovers are missing from that workflow, and one unreadable relationship can fail the whole inspection.
- Provider/cloud exclusions need a shared filesystem policy rather than per-feature checks. Current cleanup cancellation and Activity records also need a dedicated session lifecycle and grouped recovery UX.

## Early engineering foundation

Start [028 phase A](028-contributor-tooling.md) now: code ownership/layout conventions, a pinned formatting baseline and incremental state/service boundaries. It has no release/catalog dependency. [Architecture.md](../Documentation/Architecture.md) records the current assessment and target structure. Keep behavior changes and mechanical moves/formatting separately reviewable; fold the relevant responsibility refactors into each feature rather than delaying every feature for a full rewrite. Phase B contribution/rule-validator integration follows 008.

## Execution order

| ID | Task | Priority | Status | Dependencies |
| --- | --- | --- | --- | --- |
| 001 | [Validate complete cleanup plans in the core](001-cleanup-plans.md) | P0 | Done | None |
| 002 | [Strengthen filesystem identity checks](002-filesystem-identity.md) | P0 | Done | 001 |
| 003 | [Make scans progressive and cancellable](003-scan-sessions.md) | P0 | Done | None |
| 047 | [Centralize provider-aware filesystem policy](047-provider-aware-filesystem.md) | P0 | Done | 001, 002, 003 |
| 050 | [Early expanded cache discovery](050-expanded-cache-discovery.md) | P1 | Done | 001, 002, 003, 047 |
| 048 | [Cleanup progress, safe Stop, and session Undo](048-cleanup-session-undo.md) | P1 | Done | 001, 002, 003, 047 |
| 004 | [Build a hierarchical storage browser](004-storage-browser.md) | P1 | Done | 001, 002, 003, 047 |
| 005 | [Unify app ownership and footprint review](005-application-footprints.md) | P1 | Done | 001, 003 |
| 006 | [Add explicit application reset](006-application-reset.md) | P1 | Done | 001, 002, 005 |
| 007 | [Review native UX and ship 0.3.0](007-native-ux-and-release.md) | P1 | Closed by request; release checks deferred | 001–006, 047, 048, 050 |
| 008 | [Move cleanup knowledge into validated rule files](008-community-rules.md) | P2 | Done | 001, 005 |
| 009 | [Prepare a personal Homebrew tap](009-homebrew-distribution.md) | P2 | Done | 007; preparation can start earlier |
| 010 | [Review developer projects](010-developer-projects.md) | P2 | Done | 001–004, 008 |
| 011 | [Review Downloads](011-downloads-review.md) | P2 | Done | 001–004 |
| 012 | [Inspect local device backups](012-device-backups.md) | P2 | Done; inspection-only, removal unsupported | 001–004 |

The P0/P1 rows above define the 0.3.0 milestone. Near-term monitoring/optimization work below is a separate parallel track and does not silently expand those release gates. P2 does not block that milestone. The user brought 008 forward after explicitly closing 007 with its remaining release checks deferred. Dependency order wins over the numeric order; 003 can proceed independently of 001 and 002. Tasks 047–048 and 050 were added later but belong in this immediate milestone, before release task 007. Task 050 delivers useful cache coverage before task 031's full granular-selection UI and task 008's external catalog. Baseline UX inspection for 007 can begin immediately.

Ready means the task can start. Planned means its dependencies must land first. Backlog means deliberately outside the next milestone. Change a task to In progress when implementation starts, then Done only after its acceptance criteria and evidence are recorded. If part of a task is deferred, state the remaining work explicitly rather than marking the whole task done.

## Near-term monitoring and optimization track

| Order | Task | Priority | Dependencies | Outcome |
| --- | --- | --- | --- | --- |
| 1 | [017 — Passive network and battery details](017-monitoring-depth.md) | P1 | 003 | Deliver live network rates/interface/session usage first; battery depth follows as a separate slice. |
| 2 | [018 — Sustained resource evidence and app actions](018-process-insights.md) | P1 | 003 | Explain pressure/load trends and support verified, explicit app actions. Can run independently of 017. |
| 3 | [051 — Guided memory relief](051-memory-relief.md) | P1 | 003, 018 | Review consumers, quit chosen apps normally and show measured outcomes/no-action-needed states. |
| 4 | [019 — Login/background review](019-startup-background.md) | P1 | 003, 005 | Understand recurring resource use and open supported controls. |
| 5 | [052 — Network quality diagnostics](052-network-diagnostics.md) | P2 | 003, 017 | User-started speed, latency and loaded-responsiveness tests plus native troubleshooting handoffs. |
| 6 | [053 — Live disk activity](053-disk-activity.md) | P2 | 003 | Distinguish supported read/write activity from capacity, hardware health and CPU/memory load. |

Tasks 001–006, 047, 048 and 050 are complete. Task 007 is closed at the user’s request with release checks explicitly deferred; it does not establish a published 0.3.0 release. Tasks 008–012 are complete within their recorded capability gates; 012 supports inspection only, with direct removal unsupported. Continue with 013’s progressive Smart Check. The personal Luma tap pins the verified published 0.2.0 development release. Bring 017/018 forward as soon as scan lifecycle support is ready. Finish the remaining 0.3.0 storage/app/session gates before release; these parallel tasks ship only when complete and included in the release review. Task 051 does not introduce automatic app termination or a system-wide purge button. Task 052 does not turn passive monitoring into background speed testing.

## Follow-up queues

Continue with [tasks 010–030](after-current-queue.md): developer projects, Downloads and backup review, Smart Check, incremental indexing, duplicate comparison, volume analysis, deeper monitoring, privacy, similar photos, and supporting product/distribution work. Each has its own implementation file, dependencies, acceptance criteria, validation, and reference-DMG checkpoints. [010 — Developer projects](010-developer-projects.md), [011 — Downloads review](011-downloads-review.md) and [012 — Device backup inspection](012-device-backups.md) are complete within their documented scope; continue with [013 — Smart Check](013-smart-check.md). Task 027 remains deferred to future credential availability; no other phase waits for it.

Then follow [tasks 031–046](mature-product-queue.md) for remaining feature coverage, conditional capability assessments, and product-wide validation. The [spec coverage map](spec-coverage.md) links current foundations and planned work to the canonical requirements so additions do not duplicate an existing task.

There are 53 task files in total. [049 — AI-tool storage review](049-ai-tool-storage.md) is a reference-driven follow-up for agent caches and local-model assets; it does not block 0.3.0. Tasks 047–048 are the near-term additions shown above, not a requirement to finish the entire backlog before addressing cloud/provider access or session Undo.

## Reference DMGs: check throughout the work

The [compiled reference audit](compiled-reference-audit.md) maps all 48 original tasks to static executable evidence or Luma-specific requirements, records limits, and explains the scope additions. This is scope evidence, not workflow or implementation validation.

The user requires frequent checks of the `.dmg` files in Downloads. For every task:

1. Before implementation, inventory the available reference images and inspect the relevant reference workflow or capability.
2. After the first working UI or behavioral change, compare it again for missing states, unclear actions, and unnecessary steps.
3. Before completing the task, repeat the relevant comparison and record the result in [reference-checks.md](reference-checks.md). Task 007 repeats this across the complete milestone.

For core-only changes, compare relevant visible consequences such as cancellation, review, failure, and recovery; a commercial app's internal safety behavior is unknown. Record the DMG filename, app/version, what was inspected, findings, and what could not be verified. A metadata or resource inspection does not count as a visual or end-to-end workflow check. New reference images should be added to the inventory when they appear.

Mount images read-only and eject them afterward. Use the reference for feature coverage and interaction decisions. Keep Luma's own layout, Liquid Glass treatment, assets, and source. Do not install helpers, run reference cleanup against personal files, or copy proprietary code/resources into the project. Luma's generated installers under `dist/` are release artifacts and do not replace the reference comparison.

## Definition of done

- Acceptance criteria are met, with fixture-based evidence for filesystem behavior and manual evidence for native interactions.
- Relevant reference-DMG checks are recorded, with inspection limits stated accurately.
- Meaningful checks for changed behavior pass; existing safety and journal guarantees remain intact.
- Screens retain System appearance by default, accessible dark-mode contrast, the shared logo vector, consistent view alignment, and full-row action targets.
- Monitoring and the menu companion remain responsive; closing the window preserves the companion, and explicit Quit exits.
- Documentation describes actual coverage and remaining limits. Rule identifiers and developer details stay in inspection surfaces rather than crowding normal workflows.

Scanners remain read-only. Nothing is selected automatically. All mutations use the central validation and operation journal. Existing development releases continue without requiring a paid Apple account. Signing credentials and an in-app updater are future work; they do not block this milestone.

## Scope beyond 0.3.0

These areas are now tracked in the [extended queue](after-current-queue.md), with the following reasons for their placement after the immediate milestone.

| Area | Reason for deferral |
| --- | --- |
| More cache ecosystems and developer-project cleanup | Task 050 brings the first bounded cache batch into 0.3.0. Deeper child selection, additional ecosystems, source/dependency and shared-store review follow separately. |
| Persistent indexing, GRDB, and FSEvents | Measure the transient storage index before adding persistent state and invalidation work. |
| Broader volumes and external-volume cleanup | Preserve the existing volume boundary while the storage browser and mutation checks mature. |
| Similar photos | Exact duplicates and review need stronger execution guarantees first. |
| Network, battery health, login/background items | Promoted to the parallel near-term track above; not implicitly required for the 0.3.0 storage release. |
| Full Smart Check | Compose it from complete, explainable scanners after the scan-session work; do not imply currently unsupported checks run. |
| Sparkle updates and Apple distribution credentials | Revisit when credentials are available; continue GitHub development releases in the meantime. |

