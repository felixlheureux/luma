# 003 — Make scans progressive and cancellable

Status: Done  
Priority: P0  
Milestone: 0.3.0  
Depends on: None

## Why

The generated-data scan has progress, but other scanners mostly return at the end. `AppModel` shares global state across features, and `inspect(_:)` launches work outside the tracked scan task. Users need visible progress and reliable cancellation across the app.

## Scope

- Introduce isolated scan-session state with an operation ID, target, phase, progress, exclusions, completion state, and cancellation handle. Track application inspection through the same lifecycle.
- Track last-progress time separately from total elapsed time. Detect stalls/timeouts with operation-specific bounds and a clear stopping/partial state; an expensive valid file read is not automatically a failed scan. Prevent abandoned workers from publishing results.
- Bound expensive work and make queueing or replacement explicit. Keep navigation and lightweight system monitoring responsive while a scan runs.
- Stream metadata and completed result batches for app inventory, footprints, storage, leftovers, and duplicates. Start app rows before recursive bundle sizing; distinguish pending/unavailable sizes from real zero-byte values.
- Reject events from cancelled or replaced sessions. Keep previous completed results clearly separate from current partial results, with per-feature timestamps.
- Treat progressive output as inspection-only until a completed, validated snapshot is available for review. Cancellation must not publish an unfinished executable cleanup plan.
- Apply consistent permission/skip reporting beyond generated-data scanning. Preserve useful readable results without presenting incomplete coverage as a complete disk analysis.
- Make permission guidance contextual to the requested feature, with a useful limited-access path. Retrying after a permission change preserves the chosen scope and does not silently select results or request every permission at first launch.
- Integrate task 047's centralized provider-access policy before shipping expanded file traversal. Keep scan cancellation distinct from task 048's cleanup Stop/Undo lifecycle.

## Acceptance criteria

- [x] Every expensive scan and app inspection has a working cancel control and an accurate terminal state.
- [x] Cancelling or replacing a job prevents its later events from overwriting newer results or clearing another job's busy state.
- [x] App rows appear before all bundle sizes finish. Unknown sizes are labeled accurately.
- [x] Partial/cancelled results cannot become cleanup selections. Existing completed results are not silently relabeled as current.
- [x] Sidebar interaction, window reopening, Settings, and menu monitoring remain usable during a large fixture scan.
- [x] Denied-access retry works without restarting the app or widening the selected scope, and unrelated features remain usable with limited permissions.

## Validation

Use deterministic event-order fixtures for cancellation, replacement, errors, queueing, and late callbacks. Check cancellation between filesystem operations; if an OS call cannot be interrupted immediately, show a stopping state until it returns. Measure a large disposable inventory/tree and record responsiveness evidence without inventing a universal timing guarantee.

## Starting points

[AppModel.swift](../Sources/LumaApp/AppModel.swift), [Scanners.swift](../Sources/LumaCore/Scanners.swift), [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [Models.swift](../Sources/LumaCore/Models.swift), [ScanSummaryView.swift](../Sources/LumaApp/ScanSummaryView.swift).

Spec: sections 6–7, 78, 89–91, and 94 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare scan stages, cancellation feedback, navigation while scanning, and permission/error recovery. Check the reference before implementation, after the first working flow, and before completion; record evidence in [reference-checks.md](reference-checks.md).


## Completion evidence — 2026-10-17

- `ScanController` owns scan identity, captured scope, phase, progress/exclusions, total/last-progress time, cancellation, completed feature snapshots and a single queued replacement. Its per-worker bounded mailbox coalesces UI events every 150 ms. Cancellation/timeout retains the busy slot until the worker actually exits; deinitialization cancels owned work. Deterministic gates verify late callbacks, queued replacement, last-request-wins, queue cancellation, errors, timeout versus stall, snapshot retention and teardown.
- `ScanEngine` dispatches every expensive scan and app footprint through a detached utility worker. AppModel composes scan busy state with separate review/mutation state, retains per-feature completed timestamps and gates review on completed-snapshot membership. Footprints now have a real progressive sheet and explicit Cancel inspection control. Cancelling a partial scan cannot publish a cleanup selection; completed scans with readable candidates plus exclusions remain usable with coverage clearly identified.
- Application metadata rows precede every recursive size pass. Sizes have pending, available (including zero) and unavailable states. Folder items, footprints, leftovers and full-hash duplicate groups stream inspection-only results; cancellation is checked between traversal and hash operations. Coverage extends across scanner families and incomplete installed-owner inventories fail closed. Result/preview row presentation is bounded to protect navigation; full completed results are retained.
- Denied/readable sibling fixtures and native same-process retry retain readable results, exact folder scope, timestamps and empty selection. Privacy guidance is contextual and optional; no broad permission is requested at launch. Actual macOS TCC setting changes remain an environment-specific manual validation limit; fixture permissions are not represented as a TCC toggle test.
- 111 tests in 11 suites pass in optimized release validation, including native disposable journal Trash/Restore. Core scan tests cover all lifecycle/streaming invariants, metadata-first rows, unavailable sizes, scoped permission retry, readable footprints, streamed leftovers and duplicate groups. Existing safety, generated-data, leftover, duplicate, plan and journal tests remain green.
- Native light/dark QA (`Scripts/check-scan-sessions.sh`) passed against 30 generated apps and 6,000 resource files: early pending rows, held-worker Stop, no cancelled inventory/footprint snapshot, actual attached footprint sheet, rejected partial review, navigation and Settings while scanning, continued monitoring/menu presence, close/reopen and exact-scope permission retry. It never invokes cleanup. A controlled blocked-call seam makes Stop deterministic; the subsequent real inventory was timed separately. The final recorded fixture runs took approximately 0.47 seconds with 30 ms main-actor heartbeats (maximum sampled delays 0.112/0.081 seconds); these are machine/fixture observations, not universal guarantees.
- The main toolbar appearance control was removed at the user's request; System/Light/Dark remains in Settings. Native snapshots are synthetic QA artifacts, not shipped assets. Window fallback capture can omit native layer-backed content; it does not replace complete visual/accessibility review in task 007.
- Existing traversal scopes remain bounded; task 047's shared provider/no-materialization policy is still required before expanded traversal or 0.3.0 release. Cleanup session Stop/Undo remains task 048. Reference before/working/completion resource checks and their runtime limits are in [reference-checks.md](reference-checks.md).

- Final verification: all 111 tests pass in debug and optimized release configurations; the final release build passes. The existing native cleanup-review check still attaches the real sheet, reports two trees as 7 unique bytes rather than 14 raw bytes, rejects unsupported evidence and leaves fixtures unchanged. `git diff --check` passes. Reference images are ejected.
