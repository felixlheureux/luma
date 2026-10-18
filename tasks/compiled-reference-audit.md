# Compiled reference audit

Audit date: 2026-10-17. Reference: `protoypeopensourcemac.dmg`, CleanMyMac 5.7.2, build `50702.0.2610141002`. Luma comparison: 0.2.0 (`d471bbc`) plus the uncommitted task 001 implementation. This audits task scope, not task completion.

## Method and limits

Mounted the image read-only. Inspected the main executable's linked frameworks with `otool`, extracted static strings from 134 top-level framework binaries, and inspected arm64 symbols in `SystemJunkScanning` with `nm`. Reconciled each of the 48 existing task scopes below with the canonical specification and Luma's existing code. Raw binary output stays outside the repository; the table records minimal symbol names as evidence, without copying implementations or proprietary resources.

**Compiled** means a relevant named type, selector, or constant exists in the shipped executable. It does not establish that the feature is enabled, correct, reachable, safe, or available without a subscription. **Luma requirement** means the task follows Luma's specification, engineering needs, or user requests; reference internals are not verified. **Mixed** means the visible capability has compiled evidence while Luma's implementation guarantees remain independently required. A negative string search is not evidence of absence.

No function-body decompilation or runtime tracing was performed. Neither the exact rule catalog nor the reference's validation, accounting, journal, or recovery algorithms have been established. `KnowledgeBaseService` exposes knowledge-base and cipher-compatibility identifiers; that is not a decoded rule database. No encryption or licensing controls were bypassed.

Opening the reference routed to an already-running installed instance. Accessibility automation is unavailable. No reference scan result, cleanup, paid flow, visual layout, or end-to-end interaction was verified. Existing reference processes were left running. These limits do not prevent a scope audit, but they do prevent claiming behavioral parity.

## Every existing task

| Task | Evidence class | Compiled evidence and scope decision |
| --- | --- | --- |
| [001](001-cleanup-plans.md) | Mixed | `ModuleCore.ReviewBeforeCleaningViewModelType`, `CleaningScreenCoordinator`; `CleaningCore.ControllableCancelledError`. Keep review and partial-result work. Whole-plan validation, durable intents, and keeper guarantees are Luma requirements, not verified reference internals. |
| [002](002-filesystem-identity.md) | Luma requirement | Filesystem identity/race protection is required by Luma's mutation boundary. Symbols do not prove descriptor-relative validation in the reference. |
| [003](003-scan-sessions.md) | Compiled | `ScanningCore.ScanningSession`, `CompoundProgress`, stale-progress cancellation diagnostics. Supports explicit sessions, meaningful progress, cancellation, and stalled-work handling; streaming implementation remains Luma's design. |
| [004](004-storage-browser.md) | Compiled | `SpaceLensScanning.SpaceLensEntityTree`, `SpaceLensScanTask`; `SpaceLensModule.SpaceLensFolderRefresher`. Confirms hierarchical storage capability. Does not verify exact map behavior or navigation layout. |
| [005](005-application-footprints.md) | Compiled | `UninstallerScanning.CMApplicationContainerFetcher`, resource/container selectors, vendor-mark support-path resolution. Confirms broader relationship discovery than Luma's current exact paths; retain explicit ownership evidence. |
| [006](006-application-reset.md) | Mixed | Uninstaller reset identifiers and related-resource types exist. `ResetCacheScanTask` can mean internal cache invalidation and alone does not prove a user reset flow. Keep independently specified explicit reset and recovery requirements. |
| [007](007-native-ux-and-release.md) | Luma requirement | Design and UI frameworks exist, but cannot establish contrast, accessibility, responsiveness, lifecycle, release quality, or parity. Requires actual Luma QA. |
| [008](008-community-rules.md) | Mixed | `KnowledgeBaseService` exposes user/system/Xcode cache categories and knowledge-base configuration. Supports a maintained knowledge layer; does not establish its schema or justify copying it. YAML validation is Luma's design. |
| [009](009-homebrew-distribution.md) | Luma requirement | Personal tap, release automation, and installation validation are user-requested distribution work, not inferred from the reference. |
| [010](010-developer-projects.md) | Mixed | System-junk Xcode tasks and `CMGradleCacheScanTask` support developer-data scope. No verified compiled evidence here for Luma's proposed Node/Rust/Swift project-root discovery. Keep that scope spec-driven. |
| [011](011-downloads-review.md) | Compiled | `DownloadsScanning.DownloadsItemModel`, Chrome/Safari/Slack download identifiers; `UnusedDiskImagesScanning` exists. Add distinction between browser download records, actual files, and installed-app evidence. |
| [012](012-device-backups.md) | Compiled | `SystemJunkScanning.CMMobileBackupsTask`, dated/device backup models; JunkCleanup latest-backup alert identifiers. Keep backup review separate from ordinary cache cleanup. |
| [013](013-smart-check.md) | Compiled | `SmartCareModule` has separate junk, applications, organize, performance, and protection scan configuration types. Compose only Luma-supported checks; protection is excluded by Luma's spec. |
| [014](014-incremental-index.md) | Luma requirement | `SpaceLensFolderRefresher` and duplicate progress persistence do not prove a persistent filesystem index or FSEvents strategy. Measure before choosing GRDB/index architecture. |
| [015](015-duplicate-review.md) | Compiled | `OrganizeModule.DuplicateAutoselector`, selection prioritizers, duplicate scan rules and group collector. Supports richer explicit keeper review; no inference about core keep-one enforcement. |
| [016](016-volume-analysis.md) | Compiled | `SpaceLensScanning.VolumeChecker`, mounted-volume enumeration, external-volume selectors. Keep Luma's first expansion read-only. |
| [017](017-monitoring-depth.md) | Compiled | `HealthMonitoringReports.NetworkInterfaceThroughput`, `NetworkReport`, `BatteryHealth`, `BatteryReport`. Supports network/battery depth; hardware/API accuracy still needs independent verification. |
| [018](018-process-insights.md) | Mixed | Terminator and performance modules exist; this audit does not establish sustained-load thresholds or safe force-quit validation. Keep evidence intervals and PID checks as Luma requirements. |
| [019](019-startup-background.md) | Compiled | `PerformanceScanning.LaunchAgentsScanTask`, `LaunchServicesLoginItemsScanTask`, background-item factory. Confirms mechanisms; public API feasibility must be checked independently. |
| [020](020-application-updates.md) | Compiled | `UpdaterScanning.MASApplicationsDataSource`, `SparkleAppFeedProvider`, `SparkleAppValidator`, system-update task. Add explicit App Store/native handoff assessment; no reference evidence found here for Homebrew updates. |
| [021](021-privacy-workflows.md) | Compiled | `PrivacyScanning` has distinct Safari/Chrome/Firefox history, cookies, download-history tasks and application-permission tasks. Keep separate categories and version/API feasibility gates. |
| [022](022-similar-photos.md) | Compiled | `OrganizeModule.SimilarImagesScanResult`, similar-image details, path-based and Photos similarity rules. Folder-only first slice remains a deliberate Luma boundary. |
| [023](023-history-scheduling-alerts.md) | Mixed | Statistics and notification frameworks plus low-space/low-battery report types exist. They do not establish scan scheduling or history comparability. Keep those spec-driven and opt-in. |
| [024](024-search-favorites.md) | Luma requirement | Routing/navigation frameworks do not establish global search, favorites, or command palette behavior. Keep as Luma UX work. |
| [025](025-localization-accessibility.md) | Mixed | Accessibility utilities and localized resources exist. That does not demonstrate accessibility quality, RTL support, or Luma's localization packaging. |
| [026](026-maintenance-tools.md) | Compiled | `PerformanceService.FlushDNSCacheTaskRunner`, `ReindexSpotlightTaskRunner`, explicit errors and cancellation reporting. Confirms task categories, not the suitability of reference commands for Luma. |
| [027](027-luma-secure-updates.md) | Mixed | `SparkleUpdaterService` exists. Luma's signing, CI credentials, channels, and authenticated update policy remain independent and deferred. |
| [028](028-contributor-tooling.md) | Luma requirement | Contributor tooling, formatting, fixtures, and CI quality cannot be established from the shipped reference. |
| [029](029-mail-storage-review.md) | Compiled | `MailJunkScanning.CMMailTask`, mailbox attachment models, mailbox-ignore selectors. Confirms mailbox-aware discovery; Luma initially stays read-only. |
| [030](030-trash-review.md) | Compiled | `TrashJunkScanning.CMMountedTrashesScanTask`, mail and volume Trash models, iCloud-Trash flag. Keep Luma's explicit first slice limited to inspection and Finder handoff. |
| [031](031-granular-cleanup.md) | Compiled | `CMUserCachesScanTask`, sandbox/Electron/hardcoded-path cache tasks, user/sandbox/diagnostic log providers, `CacheFileModel`. Major current coverage gap: expand bounded supported locations and child review; do not scan all Library data as disposable. |
| [032](032-unused-applications.md) | Compiled | `ApplicationsModule.UnusedAppsFlowCoordinator` and unused-app identifiers. Supports review capability, not accuracy or source of usage timestamps. |
| [033](033-purgeable-snapshots.md) | Compiled | `PerformanceService.ThinLocalSnapshotsTaskRunner`, `PurgeableSpaceCleaner`, snapshot-listing/thinning constants. Preserve Luma's feasibility gate and exclude synthetic disk filling. |
| [034](034-disk-and-thermal-diagnostics.md) | Compiled | `HealthMonitoringReports.SMARTStatusReport`, SMART errors, temperature/thermal-management fields. Does not establish reliable readings on every Mac; keep capability-based support. |
| [035](035-connected-devices.md) | Compiled | Bluetooth/HID battery, mobile-device and external-volume report types. Confirms useful depth beyond Luma's current menu. |
| [036](036-more-developer-ecosystems.md) | Mixed | `CMGradleCacheScanTask`, additional Xcode task classes. Other planned ecosystems remain spec-driven, with separate evidence needed for each exact path/version. AI-tool scope is separated into new task 049. |
| [037](037-container-storage.md) | Luma requirement | No dedicated Docker inventory/prune capability established by this inspection. Preserve independently specified runtime/API assessment; filesystem caches are not container volumes. |
| [038](038-external-cleanup-support.md) | Mixed | Mounted-Trash scanning and volume checking exist. These do not prove native move, disconnect recovery, or safe Restore behavior. Keep full feasibility matrix. |
| [039](039-mail-cache-feasibility.md) | Mixed | Mail attachment models and cleanup integration exist. Regeneration, database consistency, and recoverability are not established. Retain narrow go/no-go assessment. |
| [040](040-photos-library-support.md) | Compiled | `OrganizeModule.PhotoLibraryRemovalItem`, `PhotoLibraryRemover`, Photos similarity rule. Confirms provider-specific operation concepts; no permission or recovery guarantees inferred. |
| [041](041-bundle-resource-integrity.md) | Mixed | `CMApplicationLanguagesScanTask`, localization-language models, architecture selectors. Language inspection is evidenced; thinning/signature-preserving mutation is not. Retain integrity assessment and no-go option. |
| [042](042-recent-activity-privacy.md) | Compiled | `PrivacyScanning.RecentItemsScanTask`, `PrivacyService.RecentItemRemover`. Keep reference-only actions distinct from deleting files and cache cleanup. |
| [043](043-ignore-policies.md) | Compiled | `ModuleCore.NodeIgnorer`, ignore dispatch/update types; knowledge-base ignore selectors for language, mailbox, caches and duplicates. Supports cross-feature policies, not a known persistence schema. |
| [044](044-scale-and-resilience.md) | Luma requirement | Reference progress/cancellation machinery reinforces the need, but does not establish performance budgets, concurrency limits, or race resilience. Benchmark Luma independently. |
| [045](045-local-diagnostics.md) | Luma requirement | Logger/analytics frameworks do not establish privacy-preserving diagnostics. Luma's local retention/export policy remains independent; no telemetry is added. |
| [046](046-stable-milestone-audit.md) | Luma requirement | Release acceptance must be proven against Luma's implementation and artifacts, not the reference's framework inventory. |
| [047](047-provider-aware-filesystem.md) | Compiled | `CloudStorageScanning` provider/downloading-state types; `SpaceLensCloudScannerStrategy`, evicted-protection and local-cloud alert identifiers. Confirms distinct cloud states; does not prove no-materialization guarantees. Keep provider-managed mutations blocked. |
| [048](048-cleanup-session-undo.md) | Mixed | Cleaning cancellation/coordinator types support visible cleanup lifecycle. `IgnoreUndoManager` is undo for ignores, not evidence of file recovery or session-wide Undo. Keep Luma's grouped journal/Restore work independently required. |

## Scope corrections

- Task 031 now explicitly evaluates sandbox-container cache leaves, Electron cache families, application/diagnostic logs, and additional Xcode generated data. System/Darwin/App Store caches are assessed separately for permissions and support; no blanket privileged cleanup.
- Task 011 distinguishes download records from file inventory. Task 020 explicitly assesses App Store handoffs alongside vendor/Sparkle/Homebrew sources.
- Add [049 — AI-tool storage review](049-ai-tool-storage.md). Compiled `AIToolScanning` and `LocalModelScanning` contain agent-footprint scans, active-version guards, LM Studio and Ollama store scanners. Tool caches, installed versions, conversations/configuration, and downloaded model assets need separate classifications and operation/recovery semantics. Models are not ordinary cache junk.
- Keep antivirus/protection, account-connected cloud cleanup, and online mailbox cleanup outside Luma's current scope. The reference includes protection, cloud-storage, Gmail/Microsoft and email-cleanup frameworks, but Luma's canonical specification explicitly excludes antivirus and cloud cleanup. Their presence does not authorize copying the reference's entire product.
- Keep engineering tasks without reference evidence. The binary cannot validate Luma's safety architecture, schema choice, release pipeline, accessibility quality, or privacy commitments.

All 48 original scopes have now been audited for static evidence and limits. None has been marked implemented because of this audit. Recheck the relevant behavior during implementation when interaction evidence is available.

## Subsequent planning update — tasks 050–052

Task 050 brings the first bounded cache batch forward from 031. A further pass over the saved static inventory found explicit timeout/stale-progress machinery in ScanningCore; this is now named in task 003. `AIToolScanning.ActiveVersionResolver`/`StaleVersionGuard` and `LocalModelScanning` manifest/blob-reference identifiers reinforce task 049's separate treatment of active versions and shared assets. These remain symbol/constant observations, not verified function-body behavior.

Tasks 051 (memory relief) and 052 (network diagnostics) follow the canonical spec and current Apple documentation, not an inferred reference reclaim algorithm. The static audit of all 48 original tasks remains valid as a planning snapshot; task 050 changes timing, not proof of reference safety.
