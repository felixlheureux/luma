# Reference DMG checks

Check the images in Downloads before implementation, after the first working change, and before completing each task. Repeat relevant checks during the release review. See the [task queue](README.md#reference-dmgs-check-throughout-the-work) for the workflow.

## Reference inventory

| File | App identified on 2026-10-17 | Role |
| --- | --- | --- |
| `../protoypeopensourcemac.dmg` relative to the repository root | CleanMyMac 5.7.2, bundle `com.macpaw.CleanMyMac5`, build `50702.0.2610141002` | Product behavior and feature reference |

Refresh this inventory when checking Downloads; filenames and app versions may change. Luma's own `dist/*.dmg` files are release payloads, not replacements for this reference.

## 2026-10-17 — Next-milestone planning

- Task: planning baseline for 001–009.
- Image: `protoypeopensourcemac.dmg`, mounted read-only and ejected after inspection.
- Inspected: app bundle metadata and English localization resource keys. No reference app execution, helper installation, or cleanup was performed.
- Observed: the image identifies CleanMyMac 5.7.2. Resource entries include a storage explorer menu action and distinct cancellation prompts for scanning and cleaning.
- Planning impact: prioritize usable storage navigation and consistent scan/cancel feedback alongside the spec's safety and application-review requirements.
- Limits: resource presence does not establish layout, enabled features, actual workflow behavior, or internal cleanup safety. Visual and interaction checks remain required during implementation; this record does not satisfy those future checkpoints.
- Luma comparison: reviewed 0.2.0's Storage, scan coordination, cleanup review, ownership matching, and journal code. Current gaps and selected work are documented in the task files.

## 2026-10-17 — Remaining feature coverage, tasks 031–046

- Checkpoint: task-definition planning; implementation workflow comparisons are still pending.
- Image: `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2, build `50702.0.2610141002`; mounted read-only and ejected after inspection.
- Inspected: bundle metadata and keys from 44 English `Localizable.strings` resources across the app. No reference executable, cleanup, or helper installation was run.
- Observed: matching resource keys include unused-app recommendations, purgeable-space explanations, connected-device monitor states, binary-resource categories, and detailed ignore-list categories.
- Planning impact: add concrete tasks for the remaining spec coverage, including unused-app evidence, reclaimability explanation, device monitoring, ignore policy, and a conditional binary/resource-integrity assessment.
- Limits: these observations establish resource presence only. They do not prove enabled functionality, visual quality, workflow behavior, sensor accuracy, or internal safety. No matching diagnostic resource key was found by this limited search; that is not evidence that diagnostics are absent.
- Luma comparison: reviewed the existing task queue and product-spec sections 10–21, 30–31, 44, 65, 68–72, and the mature feature tree. No task has been marked implemented on the basis of this comparison.

## Record each subsequent check

Append an entry with:

- Date, task ID, and checkpoint: before implementation / first working change / completion / release.
- Exact image filename, app version, and Luma commit/build compared.
- Relevant flow, states, or packaging contents inspected, and the inspection method.
- Concrete observations, resulting decisions, and regressions or missing states found.
- Anything not accessible or not verified; distinguish metadata/resource inspection from visual/interactive evidence.
- Mount cleanup: image ejected after use.

Do not commit the DMG, extracted proprietary assets, personal filesystem screenshots, or private diagnostic paths. Keep observations factual and concise.


## 2026-10-17 — Compiled scope audit and task 001 checkpoints

- Reference: the same CleanMyMac 5.7.2 image, mounted read-only at a temporary path. Luma baseline `d471bbc` plus task 001 working changes.
- Method: linked-framework inventory, static strings from top-level framework executables, arm64 SystemJunkScanning symbol inspection, and relevant localization resources. All 48 original task scopes mapped in [compiled-reference-audit.md](compiled-reference-audit.md).
- Findings: explicit user/sandbox/Electron cache and log scanners, Xcode/Gradle categories, per-file cache models, provider-aware storage states, agent-footprint and local-model scanners. Broadened task 031's named assessment batches, clarified tasks 011/020, and added task 049.
- Task 001: review/cleaning coordinators, cancellation types, incomplete-scan and partial-cleaned resource entries support the need for clear review/cancellation/outcome states. No evidence establishes the reference's core keep-one, journal, full-hash, identity, or recovery algorithms. Those guarantees are validated independently in Luma fixtures.
- Interaction limit: opening the mounted app routed to an already-running installed reference. Accessibility automation was unavailable. No reference scan or cleanup was run, no helpers installed, and existing reference processes were left running. No visual or end-to-end validation is claimed.
- Task 001 completion: all 83 fixture tests pass; native light/dark checks confirmed actual sheet presentation, unique totals, rejected missing duplicate evidence and unchanged fixtures. No personal files were moved. Static inspection is the available reference checkpoint, with the interaction gap explicitly retained.
- Mount cleanup: reference image ejected after the compiled audit; existing installed-app processes were left running.

## 2026-10-17 — Cache priority, memory relief and network planning

- Downloads inventory still contains `protoypeopensourcemac.dmg`. Reused the previously extracted static framework inventory from CleanMyMac 5.7.2; no new mount, execution or reference behavior test was needed or claimed for this planning update.
- Additional observations: ScanningCore has distinct timeout/stale-progress states; agent scanning has active-version guards; local-model scanning has manifest/blob-reference identifiers. Added explicit stall handling to 003 and retained separate AI/model scope in 049.
- Planning decisions: added 050 for an early bounded cache batch, 051 for measured memory relief and 052 for user-started network tests; promoted existing monitoring/process/startup tasks instead of duplicating them.
- Independent primary evidence: Apple Activity Monitor memory guide, Apple Network Responsiveness/Wireless Diagnostics guides, and installed Apple `purge(8)`/`networkQuality(8)` manuals. `purge` documents disk-cache performance analysis rather than freeing anonymous app memory; `networkQuality` documents active Internet traffic and structured results. No purge, memory-pressure experiment, app quit or active network test was run.
- The reference image remains ejected; previous Accessibility/runtime-validation limits remain in force.

- Additional gap: task 053 records a public-API assessment for live disk I/O, distinct from capacity/SMART. This is a Luma troubleshooting extension, not newly verified reference behavior.

## 2026-10-17 — Task 002 filesystem identity checkpoints

- Inventory: `../protoypeopensourcemac.dmg`, CleanMyMac 5.7.2, unchanged reference filename/version. Mounted read-only at a temporary mountpoint; Luma comparison is baseline `d471bbc` plus the existing task 001 work and task 002 changes.
- Before implementation: inspected bundle metadata and relevant resource locations. Task 002 concerns core filesystem behavior; the reference cannot establish descriptor, owner, volume, fingerprint or race guarantees.
- First working change: inspected the Space Lens English resource entries for removal failure after Luma's adapter and guarded move paths compiled. Retained actionable Luma rejection messages that direct a rescan or Finder review instead of suggesting cleanup succeeded.
- Completion: repeated the failure-state resource comparison across Space Lens, Organize and Applications. Those resources distinguish failed storage removal, uninstall and leftover cleanup. Their presence supports keeping rejected operations distinct from completed history; it does not establish runtime layout, enabled actions or actual recovery behavior. Purchase-restoration resources were excluded from filesystem-recovery conclusions.
- Independent Luma evidence: 96 tests in nine suites passed with native Trash and the case-sensitive APFS corpus enabled. Deterministic hooks rejected ancestor/target/link replacements and Restore source/parent/destination changes. The real journal moved only a disposable generated corpus to native Trash and restored it; contents, tags, xattrs, ACLs, permissions, hard links and synchronized allocation counts were checked. No personal cleanup or reference helper installation occurred.
- Limits: these are metadata/resource comparisons, not visual or end-to-end reference workflow checks. The earlier runtime/Accessibility gap remains open; no reference internal safety behavior or race resistance is claimed. Luma's residual native Trash pathname/source-basename races are documented in Safety.md. There is no new UI layout in this task.
- Mount cleanup: both the reference image and the disposable case-sensitive APFS fixture were ejected after their checks. No extracted proprietary resources were added to the repository.

## 2026-10-17 — Task 003 scan-session checkpoints

- Inventory/before: `../protoypeopensourcemac.dmg`, CleanMyMac 5.7.2, mounted read-only. Compared Luma baseline `d471bbc` plus tasks 001–003 working changes. Inspected bundle version and English Space Lens/Applications scan-stage and current-path resource entries before implementation.
- First working flow: inspected ModuleCore/SmartCare cancellation resource keys after Luma's isolated worker/progressive UI compiled. ModuleCore distinguishes requesting scan stop, confirming it and cancelling that request. This supports explicit stopping feedback; it does not prove how its internal workers cancel.
- Completion: repeated ModuleCore stop-scan and permission-error resource inspection. Luma supplies a visible Stop-pending state, a one-slot replacement queue, contextual permission guidance and same-scope retry. No external reference scan, cleanup, helper or permission change was run.
- Independent Luma native validation: light/dark QA passed early pending app rows, actual footprint-sheet presentation/cancellation, blocked-worker Stop, no partial cleanup review, navigation/Settings, monitoring/menu continuity, main-window close/reopen and scoped denied-access retry. Only 30 synthetic apps/6,000 synthetic resource files and disposable permission fixtures were used. The real inventory timing is separate from the controlled cancellation gate; no universal responsiveness or TCC-toggle guarantee is claimed.
- Own-window snapshots were inspected for progress/preview state, pending-size labeling and light/dark readability. Fallback view capture omits some native layer-backed content; screenshots alone do not establish toolbar or full accessibility behavior. The toolbar appearance control was subsequently removed in favor of Settings at the user's request.
- Limits: reference evidence is static metadata/resources, not visual or end-to-end reference workflow behavior. The existing reference runtime/Accessibility gap remains open. Its concurrency, timeout, permission and cancellation implementations are unknown; Luma's guarantees come from deterministic fixtures and native checks.
- Mount cleanup: the reference image is ejected after the completion check. No proprietary resources, personal paths/screenshots or diagnostic reports were added to the repository.
