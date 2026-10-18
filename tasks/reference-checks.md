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

## 2026-10-17 — Task 047 provider-access checkpoints

- Inventory: the only reference image remains `../protoypeopensourcemac.dmg`, CleanMyMac 5.7.2. Mounted read-only without browsing. Compared pushed Luma baseline `3a068ec` plus task 047 working changes and the final debug app.
- Before implementation: inspected the bundle version and SpaceLensModule English cloud-only protection, cloud-file labeling and downloaded-cloud removal-warning resource entries. The reference distinguishes cloud-only items from downloaded cloud files and warns of effects on other devices; resource presence does not establish runtime behavior or safety.
- First working change: repeated the same cloud-state entries after Luma's shared capability policy and no-materialization scopes compiled. Decision: exclude downloaded provider-managed files as well as placeholders, explain skipped coverage and offer Finder handoffs. No reference feature layout or resources were copied.
- Completion: repeated the cloud protection/warning comparison. Luma deliberately provides no cloud deletion or Remove Download operation. Provider metadata that cannot establish local access is an unknown exclusion, not cleanup authority.
- Independent platform evidence: Apple TN3150's current documentation JSON, SDK headers and `getattrlist(2)` guided thread-scoped dataless opt-out, dataless flags, local-volume checks and reported sync roots. Apple's caller-scoped File Provider identifier API cannot establish universal unmanaged status. The detection envelope and custom/legacy-client limits are documented in Safety.md.
- Luma evidence: 119 tests in 12 suites pass, including the opt-in real native Trash/Restore round trip of generated metadata fixtures. Fixtures cover rejected dataless ancestors, downloaded providers, network/unknown outcomes, both hash stages, metadata reads, state changes before moves/Restore, actual opaque provider-attribute changes, skipped bytes, cancellation/error policy restoration and deferred recovery when Trash metadata is unreadable. No personal file was moved.
- Native light/dark QA: retained final reports pass provider exclusions/no-selection/totals and existing scan, inspection, window/menu, navigation and retry checks using 30 synthetic apps/6,000 synthetic files. Final inventory timings were 1.032/1.033 seconds; maximum sampled main-actor delays 0.082/0.071 seconds. One earlier run exited without its dark report; a fresh build and full rerun produced passing reports in both appearances. Reports/screenshots remain temporary and untracked.
- Own-window provider-state images were inspected in both appearances. They show two local entries totaling 30 bytes and the finished-with-exclusions status. Fallback capture omits layer-backed header/coverage content, so these images do not establish full coverage-row layout, Finder activation or VoiceOver behavior. The Finder actions were not invoked on personal/provider data. Generic application symbols avoid automatic external icon/thumbnail reads.
- Limits: reference inspection is metadata/resources only, not visual or end-to-end workflow validation; the previous runtime/Accessibility gap remains. No real provider account, download/eviction, network-mount or relocated-domain integration was performed. Injected capability fixtures establish rejection behavior, not universal provider detection or remote-system behavior.
- Mount cleanup: reference image ejected after completion comparison. No proprietary assets or personal screenshots were added to the repository.


## 2026-10-17 — Task 050 early cache batch checkpoints

- Inventory/before implementation: the only reference remains `../protoypeopensourcemac.dmg`, CleanMyMac 5.7.2, mounted read-only without browsing. Compared Luma baseline `3a068ec` plus completed task 047 and task 050 working changes. Inspected bundle version and JunkCleanupModule English user-cache, user-log, Xcode-cache, Xcode-derived-data and running-app/failure resources. Earlier compiled evidence identifies Electron and sandbox cache families, but does not authorize any Luma path.
- First working change: repeated user-cache/log and Xcode resource inspection after the verified-product rule boundary and app/category grouping compiled. Luma's supported additions are exact VS Code HTTP/GPU/compiled-code caches and diagnostic logs; general system caches/logs, arbitrary Electron profiles and further Xcode data remain unavailable. The reference's broad category resources are not evidence of an equivalent enabled per-app layout.
- Completion: repeated the same category/failure comparison. Coverage difference is explicit: Luma verifies one released VS Code default layout and four complete units, requires owner/helper shutdown at execution, keeps diagnostics as Review first, and does not equate session data, archived builds, sandbox paths or unknown owners with generated cache authority. The support matrix records the evaluated families and reasons for exclusions instead of comparing rule counts alone.
- Independent primary sources: current Electron app-path documentation, Microsoft's stable update metadata, released VS Code 1.142.0 bootstrap/default-data-path/environment/cache-cleaner/log-cleaner source, and Apple's cache contract/generated-file-location guidance. Source/lifecycle evidence and synthetic fixtures support the enabled layouts; no real Electron restart, performance experiment or personal-app cleanup was run.
- Luma evidence: 130 tests in 13 suites pass and the final debug app builds. Fixture Trash/Restore moves only generated rule units and preserves adjacent backups, settings, offline/session storage and shared/container data. Provider, owner/helper, identity, unsupported-layout, permissions and hard-link totals have rejection/accounting fixtures. Post-mutation invalidation clears both app/controller generated evidence, while unrelated feature snapshots remain available.
- Native light/dark QA passes four units, two app/category groups, no selection, 39 unique logical bytes, matching actual review-sheet plan totals and generated-snapshot invalidation. Final 6,000-file inventory timings were 1.119/1.046 seconds; maximum sampled main-actor delays 0.087/0.070 seconds. Native QA never invokes cleanup. Reports and screenshots remain temporary and untracked.
- Own-window captures were inspected in both appearances: category counts, unique overall total, group heading/activity guidance and first rule row are visible. Initial captures included full header content; fallback capture in the final run omits native layer-backed header/control content. Below-fold detail expansion, complete contrast/VoiceOver behavior and external reference interactions were not established by these captures. The existing read-only detail component is reused; ownership and consequence fields were reviewed in source.
- Limits: the reference comparison is metadata/resources, not visual or end-to-end reference workflow evidence. The existing reference runtime/Accessibility gap remains. No proprietary source/resources/artwork, personal paths, logs or screenshots were copied into the repository. Sandbox ownership, other Electron releases/products, additional Xcode targets and real-provider integration are not claimed verified by this task.
- Mount cleanup: reference image ejected after the completion comparison.

## 2026-10-17 — Task 048 cleanup sessions, Stop and reviewed Undo

- Inventory/before: Downloads still contains only `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2. Mounted read-only at a temporary path without browsing. Compared pushed Luma baseline `8bb1ec5` and task 048 working changes. Inspected bundle metadata and ModuleCore English cleanup-progress Stop, stopped-item, partially-cleaned and stop-confirmation resources before implementation.
- First working change: repeated ModuleCore cleanup Stop/partial entries after the durable session/core Undo and first UI compiled. Luma keeps Stop pending until the native operation outcome is recorded, and exposes moved versus unattempted/blocked paths. Resource presence cannot establish the reference's worker lifetime or journal behavior.
- Completion: repeated the same version and stopped/partial resources after native fixture checks. The reference's Put Back entry belongs to ignored-item management; it is not evidence of cleanup batch rollback. No reference session Undo/recovery behavior is claimed. Luma's reviewed eligible-only session Undo is independently specified and tested, with explicit conflict and partial-result states.
- Independent evidence: 143 tests in 13 suites pass, including injected native-operation cancellation, Stop before preflight, selected-session isolation, mixed/changed/missing/occupied/restored targets, provider change after review, replaced parents, restart and completion-write failure recovery without retry. The new native light/dark checker uses a generated home and injected mover, asserts actual Undo sheet attachment, durable partial cleanup and restore outcomes, unchanged remaining files and menu/monitor continuity. It never calls real macOS Trash or touches personal files.
- Own captures were inspected in both appearances. Undo eligibility/consequence text is visible in captured sheet content. Some captures omit layer-backed progress/history/button content or retain an earlier rendered state; they do not establish full native contrast, keyboard focus, VoiceOver or reference-app interactions. Observable running state was corrected after the initial capture review, and native behavior rerun. Full accessibility review remains task 007.
- Limits: reference comparison is metadata/resources only, not visual or end-to-end workflow validation. The earlier reference runtime/Accessibility gap remains. No helpers, reference cleanup, personal-file mutation or copied proprietary resources were used. Native QA does not extend the existing real-provider or native Trash integration envelope.
- Mount cleanup: reference ejected after the completion comparison.

- Final task 048 regression: native scan/window/menu checks pass in both appearances (6,000-file inventory 1.137s/1.033s, maximum sampled main-actor delay 0.073s/0.078s). One earlier dark scan-QA run timed out; the rebuilt rerun retained complete passing reports in both appearances. The 143-test suite also covers a failed Undo summary write after a committed restore, preserving the successful outcome. Reports/captures stay temporary and untracked.

## 2026-10-18 — Task 004 hierarchical storage browser

- Inventory: Downloads still contains `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2. Mounted read-only without browsing at a temporary mountpoint; compared the existing Luma task 048 baseline plus task 004 changes and debug build.
- Before implementation: inventoried the image and SpaceLensModule/SpaceLensUI framework locations and bundle version. Initial sandboxed mounting failed; the authorized read-only mount succeeded. Relevant English Space Lens resources were examined during initial implementation, before the first working UI; this was not an interactive reference hierarchy check.
- First working change: repeated the hidden-file, large-folder, empty-result, cloud exclusion/warning and review resource comparison after the hierarchy/UI compiled. The reference review resource describes items spanning selected folders; Luma deliberately clears selection at directory/filter boundaries to avoid hidden selections. Luma exposes a visible synthetic remainder, partial/unknown coverage and separate folder navigation/Reveal actions. Resource presence does not establish the reference’s map accounting, actual navigation controls or safety implementation.
- Completion: repeated the same empty/review/hidden/folder resource inspection. The reference runtime/Accessibility gap from earlier tasks remains open; no visual or end-to-end reference workflow verification, scan, cleanup, helper installation or provider action was performed. No proprietary resources or interface design were copied.
- Independent Luma evidence: 150 tests pass in 14 suites, including a nested fixture-only journal Trash/Restore round trip. Native light/dark storage checks pass cached three-level navigation, breadcrumbs/back, selection clearing, map/remainder accounting, partial/unreadable/provider and empty states, actual review-sheet presentation and stale-selection rejection using 1,030 generated nodes. Scan-session regressions also pass both appearances with continued monitoring/menu/window behavior.
- Own-window loading/partial/empty/selected captures were inspected. Dark selected captures establish visible focus/details/actions; explicit storage control colors corrected dark label contrast. Some fallback captures omit layer-backed/native content, including one blank light selected capture, so images alone do not prove full native composition, keyboard focus or VoiceOver behavior. Full accessibility review remains task 007. Reports/captures are temporary; no personal data or proprietary material was added to the repository.
- Mount cleanup: the reference image was ejected after the completion comparison.

## 2026-10-18 — Task 005 shared ownership and application footprints

- Inventory/before implementation: Downloads still contains only `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2. Mounted read-only without browsing at a temporary mountpoint. Compared committed Luma storage baseline `7798692` and the task 005 working changes. Examined ApplicationsModule English app-related-file, leftover, preference/support grouping and running-app removal-failure resources before implementation.
- First working change: repeated related-file, preference/support and leftover resource inspection after the shared resolver, typed footprint and grouped native UI compiled. Luma preserves useful user data as review-only, separates bundle and data selection, distinguishes absent/denied reads and exposes explicit evidence. Reference wording that treats old preferences as redundant does not establish disposability or ownership authority for Luma.
- Completion: repeated preference/support grouping, leftover and running-app/failure entries after native light/dark fixture checks. The reference resources support capability comparisons only. The existing reference runtime/Accessibility gap remains; no visual or end-to-end reference application workflow is claimed. No helpers, personal cleanup, proprietary assets/code or interface copying were used.
- Luma evidence: 160 tests in 15 suites pass, including provider/stale/container/helper/ambiguous-path rejection, hard-link/overlap accounting and a generated named-support-folder journal round trip preserving adjacent data. Native light/dark checks pass actual grouped footprint and review sheets, no initial selection, explicit bundle/data separation, partial versus absent sizes, named ownership, matching review totals, retry and post-mutation snapshot invalidation. Native QA never invokes cleanup.
- Own partial/complete/review sheet captures were inspected. Coverage text wrapping and dark permission-button contrast were corrected. Visible grouped rows and partial-read guidance are observable; lower groups require scrolling and screenshots can omit native/layer-backed content. No full keyboard/VoiceOver session is claimed; task 007 retains that review. Temporary synthetic reports/captures remain untracked. An initial checker termination timeout was corrected by dismissing the sheet before quitting.
- Mount cleanup: reference image ejected after the completion comparison.


## 2026-10-18 — Task 006 explicit application reset

- Inventory/before: Downloads contains `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2. Mounted read-only without browsing at a temporary mountpoint. Compared Luma storage commit `7798692`, the existing task 005 working tree and task 006 changes. Before implementation, inspected ApplicationsModule English reset, preferences/support grouping and related-running-app failure entries.
- First working change: repeated those resource entries after the reset-specific plan and first review UI were implemented. The reference describes removing related files while retaining a protected app and distinguishes preferences/supporting files. This supports the capability comparison, not reference ownership or mutation guarantees. Luma keeps support data as an explicit separate selection, explains possible documents/account-state loss and requires activity checks.
- Completion: repeated the same reset/grouping/running-app resource comparison. No reference cleanup, personal reset, helper installation or proprietary resource/code/design copying occurred. The image was ejected after inspection.
- Luma evidence: 168 tests in 16 suites pass; the debug app builds. Generated fixtures cover bundle exclusion, all reset groups, selected data subsets, valuable adjacent data, known helpers, unknown process/ownership states, per-move activity recheck, provider/ignore/symlink/stale evidence, cancellation, failed-move reconciliation, partial outcomes, restart and non-overwriting Restore. Native light/dark footprint/reset and cleanup-session checks pass without invoking personal cleanup.
- Own reset and confirmation captures were inspected in both appearances. Native checks assert actual sheet presentation, no selected defaults, group classification, keyboard focus, reset-only final plan and invalidation. Lower groups require scrolling; native/layer-backed capture omissions remain. These checks do not establish a full keyboard/VoiceOver session or real-app quit/save-prompt behavior. Fixture ownership intentionally fails against the real home; core tests independently exercise idle/running/unknown states. Full native accessibility remains task 007.
- Limits: the reference comparison is metadata/resources only. The existing reference runtime/Accessibility gap remains; no visual or end-to-end reference reset workflow is claimed. The existing native Trash/provider integration limits and process-start race remain documented. Temporary fixture reports/captures are untracked.

- Final task 006 regression: scan/window/menu checks pass in both appearances (6,000-file inventory 0.963s/0.962s; maximum sampled main-actor delay 0.083s/0.070s). The user accidentally closed Luma during the first dark run, which produced no report; the retained rerun completed both reports. All retained artifacts are temporary and untracked.
