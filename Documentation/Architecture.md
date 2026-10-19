# Code organization and maintenance

Core scope revised on 2026-10-19, including the owner's follow-up review of `c03e185`. [Product-Spec.md](Product-Spec.md) defines current scope and [tasks/README.md](../tasks/README.md) is the sole execution order for 054–063; 054–057 are completed foundations and 058–063 are remaining work. The implementation notes below retain observed behavior from completed work, not authorization to expand it. The folder tree is organizational guidance, not the current layout or a required migration.

## Current assessment

The package already separates LumaCore from the executable UI, and filesystem mutation has one journal execution boundary. `DescriptorFilesystem.swift` owns pinned path traversal and exact-byte location evidence; `Filesystem.swift` owns bounded tree inspection and hashing. `FilesystemAccess.swift` owns shared provider capabilities and synchronous thread-scoped no-materialization access; future scanners/indexers/previews must use it. Object equality excludes location so journal recovery can identify a renamed item; cleanup separately requires its saved location, and Restore requires its original parent chain. Safety, ownership, hashing, memory accounting, and process grouping have useful fixture coverage. Build products and screenshots are ignored.

The main growth risks are responsibility rather than file size: AppModel still composes feature results and cleanup operations, SystemSample combines collection with presentation, Scanners.swift still combines independent scanners, and some UI files group unrelated screens. Formatting is not automated. Address a boundary only when an active core task needs it; broad refactoring, directory migration and formatter adoption are not prerequisites.

## Organization guidance

The app and core remain separate Swift package targets; completed task 008 added the small core-dependent `LumaRuleValidator` executable for contributor/CI validation. Introduce another target only when dependency direction or a practical testing requirement warrants it. Swift Package Manager can discover nested source folders; folder reorganization does not need a new framework per feature. Names below describe responsibilities and existing features; they do not add product scope to the active queue.

```text
Sources/
  LumaApp/
    App/                 entry point, composition, navigation, lifecycle
    Features/
      Clean/             feature state and views
      Storage/
      Applications/
      Duplicates/
      Optimizer/
      System/
      Activity/
      Privacy/
      Settings/
    MenuBar/             status item, companion, window handoffs
    SharedUI/            original design system and shared components
    Diagnostics/         opt-in native QA and snapshot entry points
  LumaCore/
    Cleanup/             plans, execution, durable journal, recovery
    Filesystem/          identity, traversal, hashing, provider policy
    Scanning/            session lifecycle, coverage, progress
    Applications/        relationship evidence, inventory, leftovers
    Rules/               bounded rule values, bundled catalog and loader
    Monitoring/          typed samples, accounting, grouping, trends
    Platform/macOS/      narrow system API adapters
Tests/
  LumaCoreTests/          grouped by behavior, shared fixture support
Scripts/                 reproducible build, test, formatting and release commands
Resources/               original shipped assets and bundle metadata
Documentation/           architecture, safety, distribution, roadmap and spec
tasks/                  acceptance criteria, dependencies and evidence
```

If an active task needs a file move, use folder names consistently; do not add empty placeholders. A small private helper can stay beside its only caller. Split unrelated screens/scanners only as needed for that task. Avoid generic Utils/Managers/Helpers dumping grounds and giant Models.swift files as new domains arrive.

## Dependency and state boundaries

- Views display state and dispatch explicit user actions. They do not traverse files, hash content, mutate the filesystem, or run subprocesses while rendering.
- Keep an app-level composition/lifecycle/navigation owner. ScanController owns scan lifecycle; ScanEngine dispatches requests and ScanReporting shares coverage. AppModel maps completed snapshots into feature state and gates cleanup intent on their membership. CleanupSessionModel owns mutation/recovery presentation, and the existing monitoring loop remains shared. The menu and main window share services; they do not create duplicate polling loops.
- Prefer explicit construction of dependencies at the composition root. Existing AppModel.shared is a migration boundary; new features must not reach into it for hidden dependencies. Do not replace one global object with a global service locator.
- Core values do not depend on SwiftUI, colors, localized display strings for logic, or view models. Platform code may use AppKit/CoreServices where needed, isolated behind narrow adapters. The package is macOS-specific; making every file platform-neutral is not a goal.
- Inject clocks, filesystem/provider inspection, process/system sampling and subprocess boundaries where deterministic tests or alternate real providers need them. Simple pure functions and values need no protocol/factory hierarchy.
- Prefer enums and typed outcomes for operation/metric states. Unknown, unavailable, partial, cancelled and stale are different from zero, healthy or completed. Convert these into localized labels/colors in the UI.
- Keep user intent and immutable authorized plans distinct from live observations. Direct list actions for app uninstall and selected residues prepare their plans internally; no mandatory ReviewSheet, second selection panel or extra acknowledgement belongs in those flows. Only CleanupJournal.execute may perform ordinary cleanup; Restore remains identity-verified and non-overwriting. Cache removal and permanent Trash emptying retain their specific maintenance approval. Typed provider/runtime operations must not pretend to have file Trash semantics.
- Keep metadata discovery, safe local-content access and supported mutation capabilities distinct. The current provider policy excludes cloud items; the active iCloud work must add supported discovery without triggering downloads or interpreting discovery alone as cleanup authority.

## Concurrency and errors

Use MainActor for UI state. Keep expensive inspection, hashing and sampling off that actor using bounded workers with explicit cancellation and lifetime ownership. Detached work must have a documented reason and cancellation propagation; actor isolation is not permission to block cooperative executors with unbounded work.

Every long job owns an ID and terminal state. Reject late events after cancellation/replacement, preserve valid completed outcomes, and keep monitoring independent of feature scans. Do not hold thread-local filesystem policies across suspension. Journal locking and reentrant actor calls need explicit invariants and regression fixtures.

Surface meaningful operation errors and partial coverage. Avoid catch-and-empty results, indiscriminate try?, forced casts and force unwraps on external state. Best-effort cleanup/snapshot paths may intentionally tolerate errors if the reason and effect are clear. Bound subprocess runtime/output and use fixed argument arrays, not shell interpolation.

## Style and documentation

Use clear Swift names, explicit access control, focused methods and readable statements. Avoid packing unrelated mutations onto one line to save space. Document safety/concurrency/units invariants and the reasons for exceptions; routine syntax needs no narration. File length is a review signal, not an arbitrary hard limit.

Keep formatting consistent with the existing Swift source. Do not introduce a formatter, broad lint rule set or mechanical cleanup as a prerequisite for the core tasks. Any necessary mechanical changes should remain separately reviewable from behavior changes. Follow [Swift API design guidance](https://www.swift.org/documentation/api-design-guidelines/).

## Tests and repository hygiene

- Keep deterministic core tests around behavior and failure boundaries, especially changed paths, ignored/provider-owned files, duplicates, recovery and process identity. Share small fixture builders rather than duplicating fake filesystems throughout tests.
- State/lifecycle tests cover replacement, cancellation and late events; native QA covers approved action/window/menu integration. Existing assertions that require review sheets or separate bundle/data selection describe the old UI; replace them during the corresponding core task while preserving core safety, stale-evidence and recovery tests. Do not mirror implementation details or add screenshot snapshots for every cosmetic change.
- Keep fixtures synthetic and temporary. Exclude personal reports, logs, extracted reference content, credentials, build products and distribution images from commits. Generated original assets already tracked are changed only through the documented asset workflow.
- Make formatter/test/build/signature checks reproducible from a clean checkout. Introduce narrowly useful static boundary checks only where they protect a real invariant; avoid a fragile custom architecture-lint framework.
- Reorganization, formatting and behavioral changes should be separate reviewable commits. Validate the supported behavior after meaningful moves, preserve public rule IDs/journal compatibility, and avoid unrelated churn.
- Product-Spec.md defines current scope, tasks/README.md alone orders active work, and the roadmap records status. Update evidence in its existing location; do not create another competing feature inventory or infer new work from completed-task notes. Record architectural decisions here or in a focused decision note when a real tradeoff arises.
- Documentation/planning-only changes need diff and link checks; native builds and implementation QA are required when the corresponding behavior changes.

## Changes within the core tasks

Follow tasks 054–063 in the queue's stated order, with only the structural changes each needs. Task 003 delivered isolated scan ownership, immutable request scopes, bounded event mailboxes and explicit completed-snapshot boundaries; task 048 delivered cleanup/recovery presentation state, and task 017 delivered passive provider boundaries. These are existing foundations. Keep System's metric set, correct existing battery reporting in 063 and retain core execution guarantees while simplifying the active flows.

## Observed implementation boundaries

The following notes describe completed implementation. References to review sheets, explicit folder/volume pickers or excluded provider content record the behavior being revised; the current spec and active task acceptance criteria determine the new UI and capability boundaries.

### Scan execution boundary

One ScanController worker owns expensive analysis. A stopped worker retains its slot until it exits; a single queued replacement cannot run alongside it. Main-actor polling coalesces synchronous scanner events, instead of spawning an unbounded Task per file. AppModel's scan busy state is composed with its separate review/mutation busy state; scan completion never calls the mutation finish helper. Monitoring has its independent lightweight sampling loop.

The controller exposes read-only previews and completed snapshots separately. AppModel currently accepts cleanup review only from its completed feature snapshot; direct actions must retain fresh executable evidence without requiring that review UI. Generated data, inventory, leftovers, footprints, storage and duplicates share the same lifecycle. Overview composes supported checks sequentially and commits each completed subcheck independently through the same mailbox; partial events remain read-only previews. A native fixture runner is injected only by the debug QA entry point; production uses ScanEngine. The files stay beside the existing core code unless an active task needs a focused move.


Task 050 adds `VerifiedGeneratedOwner.swift` for released product-layout evidence, `GeneratedDataSummary.swift` for transient logical-content accounting and app/category grouping, and `GeneratedDataGroupsView.swift` for Clean presentation. Views use recorded scan evidence for sizes rather than traversing files. ScanController now exposes completed-snapshot invalidation so mutation outcomes cannot retain stale generated evidence in either state owner. The catalog remains in Rules.swift until task 008. Test-only owner-root and process-collection seams are task-local and do not alter production wiring.

Task 048 introduces `CleanupSessionModel` as the observable mutation lifetime/presentation owner, with its own cancellable task, running/stopping state, progress, session summaries and Undo review. AppModel composes it with scan/review busy state and applies journal snapshots; scan cancellation cannot cancel a mutation. `CleanupSession.swift` contains durable session/Undo values. The journal retains its exclusive lock across awaited callbacks. Synchronous post-mutation verification and commits use a narrowly scoped task-local cancellation exemption; filesystem/provider/identity checks still run, and the next-item boundary remains cancellable. Debug native session QA injects a disposable journal and never redirects production mutation paths.

Task 004 introduces `StorageIndex` and `StorageNode` as transient read-only observations, separate from cleanup candidates. A bounded scan records the hierarchy once; navigation never traverses the filesystem. Exact UTF-8 traversal order assigns shared inode bytes to the first observed path, so child totals add up even across hard links. Packages are opaque navigation leaves. The index stores unknown/partial coverage and never converts an excluded subtree to an empty result. `StorageView` provides native list controls for every map action; synthetic remainder entries carry no cleanup authority. On explicit review, the completed index checks current-directory membership, age and observed object metadata, then captures fresh full descriptor/tree evidence off the main actor for the ordinary cleanup plan. SafetyEngine shares its metadata-free manual-scope check with selection controls; execution retains full validation. Cleanup and Restore invalidate the transient hierarchy. Task 014 adds disposable metadata/hash persistence and conservative invalidation; the displayed hierarchy still comes from a fresh traversal.

ApplicationRelationships owns exact locations, named mappings, classifications, consequences and container metadata validation. ApplicationFootprintScanner returns typed readable/absent/unavailable relationships plus unique content accounting; ScanEngine transports this completed value separately from cleanup candidates. AppFootprintView renders those observations and uses the existing explicit review boundary. LeftoverScanner and SafetyEngine resolve the same policy; embedded helper inventory also gates running-owner checks. Mutation and Restore outcomes invalidate both owners of completed footprint snapshots.


ApplicationReset.swift owns reset categories, supported selection and installed owner/helper activity checks. CleanupPlan captures reset intent and app identity; CleanupJournal remains the only executor. AppFootprintView composes the reset review and ordinary footprint from the same completed snapshot. Process collection runs off the main actor, and no thread I/O policy spans an await.

Task 008 moves generated rule data and named ownership mappings to the bundled versioned YAML catalog. `RuleLoader.swift` alone imports pinned Yams and validates its node tree/schema before constructing a `RuleCatalog`; parser types never cross that boundary. `Rules.catalog()` returns the atomically loaded immutable catalog or its actionable error. Display-only compatibility accessors return no findings on failure; generated/leftover/footprint scans, relationship resolution and SafetyEngine require a successful catalog, so missing/invalid resources cannot become partial cleanup authority. The catalog’s resource is bundled before signing and verified in the mounted installer. The internal task-local override accepts only an already validated catalog or an explicit failure for synthetic tests; no app setting/environment/remote download selects a runtime catalog. Core protected roots and filesystem/provider/identity/owner/activity/journal checks remain independent Swift policy. Existing implicit build/package guards are explicit catalog fields; the loader enforces their path-specific minimums and SafetyEngine enforces current tool activity.

Task 010 introduces `DeveloperProjects.swift` for bounded project discovery, typed non-candidate breakdowns and compiled version-1 Node/Rust/Swift policy. `ProjectEvidence` accompanies only project findings and captures the project directory location, manifest identity and content hash. SafetyEngine resolves the exact rule/path again and rejects stale manifests, unsupported scope, sensitive/shared content or active/unknown build tools. `ScanResult` transports `ProjectInventory` through the existing controller; `ProjectsView` renders completed evidence and the existing selection/review controls. CleanupPlan/Journal own all mutations and recovery. Execution contexts carry a fresh tool snapshot for project rules; other generated rules retain their existing simulator-aware collection. No package command or manifest evaluation is introduced. See [Developer-Projects.md](Developer-Projects.md) for supported paths and limits.

Task 011 introduces `Downloads.swift` for bounded chosen-tree local-file inventory, exclusive type categories, intersecting age/size filters, optional bounded where-from metadata and explicit keeper selection. `DuplicateScanner.verify` now provides one shared size/partial/full-SHA256 pipeline for both ordinary duplicate discovery and the completed Downloads inventory. Download group members replace their manual items with duplicate-rule evidence, so keep-one checks cannot be bypassed by selecting the same known group in the Files view. `DownloadPreview.swift` reads bounded pinned bytes under the non-materializing policy and returns literal text or a small in-memory PNG; no path or source URL goes to an external preview handler. AppModel owns the completed inventory and cancellable preview task, while DownloadsView owns presentation filters. Review uses the manual storage scope gate and CleanupPlan; mutations and recovery invalidate inventory/preview. Final review renders lazily to keep large selections bounded in the native view. See [Downloads.md](Downloads.md) for policy and limits.

Task 012 introduces `DeviceBackups.swift` for typed inspection observations at the exact standard MobileSync location. The model intentionally has no CleanupItem/removal capability. Only three bounded summary plists are read, with identity/content rechecks after metadata-only sizing; no manifest database/payload content is opened. Separate location, metadata and size states avoid conflating inaccessible/corrupt/partial data with an empty backup. Process evidence can only report possible activity or unknown, never idle. DeviceBackupsView renders per-folder personal-data records without exposing unnecessary identifiers or selection controls. ScanController owns this explicit scan; Overview does not compose it automatically. SafetyEngine rejects the standard backup subtree and backup namespace independently of UI or reported state. Test-local activity/read observers cannot grant mutation authority. The task's conditional format/activity assessment yields inspection-only support; there is no fixture-only removal path. See [Device-Backups.md](Device-Backups.md).


Task 013 introduces `SmartCheck.swift` for sequential scanner composition and explainable completion states. The Overview request captures optional authorized project/Downloads roots and ignores. Completed subchecks cross a distinct bounded mailbox event, are matched to the captured request and acquire the parent session ID; cancellation/replacement rejects later events. Each result retains its own report, timestamp and ordinary feature snapshot. The parent has no aggregate candidates or savings total, so overlapping categories never create combined cleanup authority. AppModel retains recommendation references separately and refuses navigation after feature snapshot replacement/invalidation. `SmartCheckView` renders optional scopes, coverage/failure/skipped/stale states and captured live measurements; review and mutation remain in the existing feature flows. Thermal state is now recorded in each system sample rather than recomputed while displaying older evidence.


Task 014 introduces `AnalysisIndex` as the project-owned persistence boundary; only its adapter imports GRDB in production. GRDB 7.11.1 is pinned by exact version/revision and uses system SQLite. Schema migrations create root/entry tables and add generation metadata; migration or integrity failures disable reuse for that scan. Tests may import GRDB to construct malformed and old databases. The app creates the index lazily off the main actor under `~/Library/Caches/app.luma.mac/Analysis`, separate from Activity/preferences, and Settings clears only the owned SQLite database/sidecar files. An epoch prevents a running generation from repopulating a cleared index.

Index rows contain exact UTF-8 paths, a volume/root/ancestor identity, catalog/policy version, scan generation, high-resolution stat fingerprints, ordinary display metadata and optional partial/full SHA-256 state. Reuse is limited to local APFS volumes with a known volume UUID; other filesystems use fresh analysis. Fingerprints include nanosecond ctime/mtime, birth time, mode, flags, ownership and hard-link count. Every scan enumerates current directories and invokes current provider/path checks; cached access/coverage and package sizes never bypass those checks. Sessions use bounded in-memory maps and commit only reached observations transactionally. Up to eight roots and 100,000 records per root are retained. No CleanupItem or review authorization is persisted.

`AnalysisEvents` uses native FSEvents for at most eight explicitly scanned roots. Any event, overflow, root change, ID reset or unmount invalidates the entire root. Streams perform no background traversal or content reads. Event history is advisory: fresh enumeration, volume/root identity and per-file metadata validation run even when a stream is absent or events are lost. Changes detected while scanning prevent cache publication and produce an incomplete report with rescan guidance. ScanController still owns cancellation/replacement and monitoring remains independent. Duplicate plan preflight/per-move validation always recomputes current full hashes through Filesystem; a deliberately poisoned cache cannot authorize a move. Storage rescans preserve the current directory when it still exists in the fresh hierarchy, while clearing selections.


The leftover feedback fix shares one installed-app inventory only within whole-plan preflight. Each actual move still performs fresh ownership discovery, path/rule/provider/identity checks and full duplicate checks after the durable intent and mutation checkpoint. The redundant pre-intent validation was removed; whole-plan preflight and the final full validation before Trash remain. Failed final validation removes the unmoved intent as before. An owner proven absent by the full inventory does not trigger another owner-specific helper traversal. Application reset/footprint helper checks remain separate.

Cleanup detail pulses travel synchronously into a one-value mailbox; the main-actor CleanupSessionModel polls it at 150ms while the journal worker performs ownership discovery or tree inspection. Phase/item changes clear old details. Elapsed time stays live even during a native Trash call, and no fake native move percentage is shown. Post-move inspection/commit still preserves outcomes before observing Stop.

After leftover cleanup, ScanController removes moved/overlapping/uncertain paths from its original completed snapshot, mints a new evidence ID to invalidate old recommendations and retains the old scope/time with explicit refresh guidance. AppModel applies the same remaining subset in both state owners and clears selections. Cleanup/restore outside the leftover workflow retains existing broad invalidation. LeftoverGroup sorts exact owner groups by identifier by default; largest-first and filtering affect presentation, not ownership.

ApplicationIcon reads bounded local Info.plist-named PNG/ICNS resource bytes under the non-materializing provider policy and creates at most a 96-pixel PNG. Inventory carries those bytes through progressive/sized records; views never open an app path or ask Finder/Quick Look to resolve an icon. Missing/unsupported/provider/linked resources use a generic symbol. Asset-catalog-only icons are not resolved through private APIs.

Task 015 introduces `DuplicateReview` for deterministic whole-group presentation and explicit `DuplicateKeeperChoice` proposals. Proposal preparation/application read current full content under the non-materializing policy; neither authorizes mutation. `DuplicateComparison` reuses the bounded local preview reader and records creation/modification/link metadata. `DuplicateGroupsView` shares the folder and Downloads comparison/preview UI; `DuplicateReviewActions` owns asynchronous app integration, cancellation and snapshot membership checks. Ordinary review, CleanupPlan and the journal remain authoritative.

Task 016 introduces `StorageVolume`/`StorageScope` for local volume observations, explicit picker identity and a pinned root generation. `StorageIndex` retains this scope and independently rejects review for outside-home, other-device and read-only analysis. Storage scans carry captured ignores, including package-descendant exclusions. The descriptor adapter has an internal explicit inspection-root option for volume metadata and storage traversal; ordinary filesystem/cleanup pins still reject `/`. `StorageVolumeModel` owns lightweight metadata checks and native unmount notifications, with generation tokens rejecting old callbacks. Loss/replacement clears both completed-snapshot owners. The picker captures expected volume identity in ScanRequest, preventing a replaced mount path from silently selecting new media. Existing cache identity/FSEvents validation and SafetyEngine/journal policies remain authoritative.

## Passive monitoring ownership

Task 017 separates bounded Darwin counter decoding and `NetworkActivityTracker` accounting in LumaCore from `NetworkProvider`/`BatteryProvider` platform adapters. `SystemSample` composes observations; AppModel owns one off-main two-second collection loop shared by System and the companion, including when the main window is closed. ContinuousClock timestamps and wake resets prevent sleep gaps from becoming rates. Selection chooses one interface; physical and tunnel counters are never summed. Counter resets, interface generations and unavailable samples drop the baseline while preserving only measured session intervals.

BatteryDetails validates optional reported fields independently. IOPowerSources is primary; the public legacy IOPMCopyBatteryInfo call only supplements a cycle count for an unambiguous single battery. Missing values stay nil. Reported nominal/design capacity may provide a separate maximum-capacity estimate; normalized current/max charge does not. Neither provider starts active traffic, reads private sensors or mutates system settings.
