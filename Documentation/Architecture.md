# Code organization and maintenance

Reviewed on 2026-10-17 against the working tree after tasks 001–003. This records the intended boundaries and incremental migration; the folder tree below is a target, not the current layout.

## Current assessment

The package already separates LumaCore from the executable UI, and filesystem mutation has one journal execution boundary. `DescriptorFilesystem.swift` owns pinned path traversal and exact-byte location evidence; `Filesystem.swift` owns bounded tree inspection and hashing. `FilesystemAccess.swift` owns shared provider capabilities and synchronous thread-scoped no-materialization access; future scanners/indexers/previews must use it. Object equality excludes location so journal recovery can identify a renamed item; cleanup separately requires its saved location, and Restore requires its original parent chain. Safety, ownership, hashing, memory accounting, and process grouping have useful fixture coverage. Build products and screenshots are ignored.

The main growth risks are responsibility rather than file size: AppModel still composes feature results and cleanup operations, SystemSample combines collection with presentation, Scanners.swift still combines independent scanners, and some UI files group unrelated screens. Formatting is not automated. Task 028 now addresses these concerns early rather than waiting for community rules and a release.

## Target layout

The app and core remain separate Swift package targets; task 008 adds a small core-dependent `LumaRuleValidator` executable for contributor/CI validation. Introduce another target only when dependency direction or a practical testing requirement warrants it. Swift Package Manager can discover nested source folders; folder reorganization does not need a new framework per feature.

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

Use folder names consistently when migration lands; do not add empty placeholders. A small private helper can stay beside its only caller. Split unrelated screens/scanners as their feature changes. Avoid generic Utils/Managers/Helpers dumping grounds and giant Models.swift files as new domains arrive.

## Dependency and state boundaries

- Views display state and dispatch explicit user actions. They do not traverse files, hash content, mutate the filesystem, or run subprocesses while rendering.
- Keep an app-level composition/lifecycle/navigation owner. ScanController now owns scan lifecycle; ScanEngine dispatches requests and ScanReporting shares coverage. AppModel maps completed snapshots into feature state and gates review on their membership. Move cleanup/recovery, monitoring and further feature selection into focused owners as tasks 048/017 land. The menu and main window share services; they do not create duplicate polling loops.
- Prefer explicit construction of dependencies at the composition root. Existing AppModel.shared is a migration boundary; new features must not reach into it for hidden dependencies. Do not replace one global object with a global service locator.
- Core values do not depend on SwiftUI, colors, localized display strings for logic, or view models. Platform code may use AppKit/CoreServices where needed, isolated behind narrow adapters. The package is macOS-specific; making every file platform-neutral is not a goal.
- Inject clocks, filesystem/provider inspection, process/system sampling and subprocess boundaries where deterministic tests or alternate real providers need them. Simple pure functions and values need no protocol/factory hierarchy.
- Prefer enums and typed outcomes for operation/metric states. Unknown, unavailable, partial, cancelled and stale are different from zero, healthy or completed. Convert these into localized labels/colors in the UI.
- Keep user intent and immutable reviewed plans distinct from live observations. Only CleanupJournal.execute may perform ordinary cleanup; Restore remains identity-verified and non-overwriting. Typed future provider/runtime operations must not pretend to have file Trash semantics.

## Concurrency and errors

Use MainActor for UI state. Keep expensive inspection, hashing and sampling off that actor using bounded workers with explicit cancellation and lifetime ownership. Detached work must have a documented reason and cancellation propagation; actor isolation is not permission to block cooperative executors with unbounded work.

Every long job owns an ID and terminal state. Reject late events after cancellation/replacement, preserve valid completed outcomes, and keep monitoring independent of feature scans. Do not hold thread-local filesystem policies across suspension. Journal locking and reentrant actor calls need explicit invariants and regression fixtures.

Surface meaningful operation errors and partial coverage. Avoid catch-and-empty results, indiscriminate try?, forced casts and force unwraps on external state. Best-effort cleanup/snapshot paths may intentionally tolerate errors if the reason and effect are clear. Bound subprocess runtime/output and use fixed argument arrays, not shell interpolation.

## Style and documentation

Use clear Swift names, explicit access control, focused methods and readable statements. Avoid packing unrelated mutations onto one line to save space. Document safety/concurrency/units invariants and the reasons for exceptions; routine syntax needs no narration. File length is a review signal, not an arbitrary hard limit.

Task 028 pins a compatible SwiftFormat version and a small configuration shared by local and CI checks. Keep the first mechanical format commit separate from behavior changes. Do not introduce competing formatters or broad lint rule sets without demonstrated value. Follow [Swift API design guidance](https://www.swift.org/documentation/api-design-guidelines/) and [SwiftFormat's documented check mode](https://github.com/nicklockwood/SwiftFormat).

## Tests and repository hygiene

- Keep deterministic core tests around behavior and failure boundaries, especially changed paths, ignored/provider-owned files, duplicates, recovery and process identity. Share small fixture builders rather than duplicating fake filesystems throughout tests.
- State/lifecycle tests cover replacement, cancellation and late events; native QA covers sheet/window/menu integration. Do not mirror implementation details or add screenshot snapshots for every cosmetic change.
- Keep fixtures synthetic and temporary. Exclude personal reports, logs, extracted reference content, credentials, build products and distribution images from commits. Generated original assets already tracked are changed only through the documented asset workflow.
- Make formatter/test/build/signature checks reproducible from a clean checkout. Introduce narrowly useful static boundary checks only where they protect a real invariant; avoid a fragile custom architecture-lint framework.
- Reorganization, formatting and behavioral changes should be separate reviewable commits. Validate the supported behavior after meaningful moves, preserve public rule IDs/journal compatibility, and avoid unrelated churn.
- The canonical spec, roadmap and tasks have distinct roles. Update status and evidence in their existing locations; do not create another competing feature inventory. Record architectural decisions here or in a focused decision note when a real tradeoff arises.

## Migration order

Task 028 phase A establishes the conventions and formatting baseline now. Task 003 delivered isolated scan ownership, immutable request scopes, bounded event mailboxes and explicit completed-snapshot boundaries. Task 048 extracts cleanup/recovery presentation state. Tasks 017/018 isolate typed samples and system adapters from colors/UI. Split and relocate feature files during these focused changes; retain the existing core execution guarantees throughout.

## Scan execution boundary

One ScanController worker owns expensive analysis. A stopped worker retains its slot until it exits; a single queued replacement cannot run alongside it. Main-actor polling coalesces synchronous scanner events, instead of spawning an unbounded Task per file. AppModel's scan busy state is composed with its separate review/mutation busy state; scan completion never calls the mutation finish helper. Monitoring has its independent lightweight sampling loop.

The controller exposes read-only previews and completed snapshots separately. AppModel accepts cleanup review only from its completed feature snapshot. Generated data, inventory, leftovers, footprints, storage and duplicates share the same lifecycle. Overview commits its generated-data plus inventory result together. A native fixture runner is injected only by the debug QA entry point; production uses ScanEngine. The new files stay beside the existing core code for now; broader mechanical folder moves remain task 028.


Task 050 adds `VerifiedGeneratedOwner.swift` for released product-layout evidence, `GeneratedDataSummary.swift` for transient logical-content accounting and app/category grouping, and `GeneratedDataGroupsView.swift` for Clean presentation. Views use recorded scan evidence for sizes rather than traversing files. ScanController now exposes completed-snapshot invalidation so mutation outcomes cannot retain stale generated evidence in either state owner. The catalog remains in Rules.swift until task 008. Test-only owner-root and process-collection seams are task-local and do not alter production wiring.

Task 048 introduces `CleanupSessionModel` as the observable mutation lifetime/presentation owner, with its own cancellable task, running/stopping state, progress, session summaries and Undo review. AppModel composes it with scan/review busy state and applies journal snapshots; scan cancellation cannot cancel a mutation. `CleanupSession.swift` contains durable session/Undo values. The journal retains its exclusive lock across awaited callbacks. Synchronous post-mutation verification and commits use a narrowly scoped task-local cancellation exemption; filesystem/provider/identity checks still run, and the next-item boundary remains cancellable. Debug native session QA injects a disposable journal and never redirects production mutation paths.

Task 004 introduces `StorageIndex` and `StorageNode` as transient read-only observations, separate from cleanup candidates. A bounded scan records the hierarchy once; navigation never traverses the filesystem. Exact UTF-8 traversal order assigns shared inode bytes to the first observed path, so child totals add up even across hard links. Packages are opaque navigation leaves. The index stores unknown/partial coverage and never converts an excluded subtree to an empty result. `StorageView` provides native list controls for every map action; synthetic remainder entries carry no cleanup authority. On explicit review, the completed index checks current-directory membership, age and observed object metadata, then captures fresh full descriptor/tree evidence off the main actor for the ordinary cleanup plan. SafetyEngine shares its metadata-free manual-scope check with selection controls; execution retains full validation. Cleanup and Restore invalidate the transient hierarchy. Persistent indexing and invalidation remain task 014.

ApplicationRelationships owns exact locations, named mappings, classifications, consequences and container metadata validation. ApplicationFootprintScanner returns typed readable/absent/unavailable relationships plus unique content accounting; ScanEngine transports this completed value separately from cleanup candidates. AppFootprintView renders those observations and uses the existing explicit review boundary. LeftoverScanner and SafetyEngine resolve the same policy; embedded helper inventory also gates running-owner checks. Mutation and Restore outcomes invalidate both owners of completed footprint snapshots.


ApplicationReset.swift owns reset categories, supported selection and installed owner/helper activity checks. CleanupPlan captures reset intent and app identity; CleanupJournal remains the only executor. AppFootprintView composes the reset review and ordinary footprint from the same completed snapshot. Process collection runs off the main actor, and no thread I/O policy spans an await.

Task 008 moves generated rule data and named ownership mappings to the bundled versioned YAML catalog. `RuleLoader.swift` alone imports pinned Yams and validates its node tree/schema before constructing a `RuleCatalog`; parser types never cross that boundary. `Rules.catalog()` returns the atomically loaded immutable catalog or its actionable error. Display-only compatibility accessors return no findings on failure; generated/leftover/footprint scans, relationship resolution and SafetyEngine require a successful catalog, so missing/invalid resources cannot become partial cleanup authority. The catalog’s resource is bundled before signing and verified in the mounted installer. The internal task-local override accepts only an already validated catalog or an explicit failure for synthetic tests; no app setting/environment/remote download selects a runtime catalog. Core protected roots and filesystem/provider/identity/owner/activity/journal checks remain independent Swift policy. Existing implicit build/package guards are explicit catalog fields; the loader enforces their path-specific minimums and SafetyEngine enforces current tool activity.

Task 010 introduces `DeveloperProjects.swift` for bounded project discovery, typed non-candidate breakdowns and compiled version-1 Node/Rust/Swift policy. `ProjectEvidence` accompanies only project findings and captures the project directory location, manifest identity and content hash. SafetyEngine resolves the exact rule/path again and rejects stale manifests, unsupported scope, sensitive/shared content or active/unknown build tools. `ScanResult` transports `ProjectInventory` through the existing controller; `ProjectsView` renders completed evidence and the existing selection/review controls. CleanupPlan/Journal own all mutations and recovery. Execution contexts carry a fresh tool snapshot for project rules; other generated rules retain their existing simulator-aware collection. No package command or manifest evaluation is introduced. See [Developer-Projects.md](Developer-Projects.md) for supported paths and limits.

Task 011 introduces `Downloads.swift` for bounded chosen-tree local-file inventory, exclusive type categories, intersecting age/size filters, optional bounded where-from metadata and explicit keeper selection. `DuplicateScanner.verify` now provides one shared size/partial/full-SHA256 pipeline for both ordinary duplicate discovery and the completed Downloads inventory. Download group members replace their manual items with duplicate-rule evidence, so keep-one checks cannot be bypassed by selecting the same known group in the Files view. `DownloadPreview.swift` reads bounded pinned bytes under the non-materializing policy and returns literal text or a small in-memory PNG; no path or source URL goes to an external preview handler. AppModel owns the completed inventory and cancellable preview task, while DownloadsView owns presentation filters. Review uses the manual storage scope gate and CleanupPlan; mutations and recovery invalidate inventory/preview. Final review renders lazily to keep large selections bounded in the native view. See [Downloads.md](Downloads.md) for policy and limits.

Task 012 introduces `DeviceBackups.swift` for typed inspection observations at the exact standard MobileSync location. The model intentionally has no CleanupItem/removal capability. Only three bounded summary plists are read, with identity/content rechecks after metadata-only sizing; no manifest database/payload content is opened. Separate location, metadata and size states avoid conflating inaccessible/corrupt/partial data with an empty backup. Process evidence can only report possible activity or unknown, never idle. DeviceBackupsView renders per-folder personal-data records without exposing unnecessary identifiers or selection controls. ScanController owns this explicit scan; Overview does not compose it automatically. SafetyEngine rejects the standard backup subtree and backup namespace independently of UI or reported state. Test-local activity/read observers cannot grant mutation authority. The task's conditional format/activity assessment yields inspection-only support; there is no fixture-only removal path. See [Device-Backups.md](Device-Backups.md).
