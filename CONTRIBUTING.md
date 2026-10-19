# Contributing to Luma

Use [Product-Spec.md](Documentation/Product-Spec.md) for current product scope. [tasks/README.md](tasks/README.md) is the sole execution order; only tasks 054–059 are active in the core reset. Completed task evidence and [Roadmap.md](Documentation/Roadmap.md) describe implementation history, not additional authorized work. Build with Swift 6.2+ and a macOS 26+ SDK. Follow [Architecture.md](Documentation/Architecture.md) for code ownership, state/concurrency boundaries and testing; broad reorganization or formatter adoption is not a prerequisite for the core.

Target native Apple Silicon (`arm64`) on macOS 26+; use M2 as reference hardware. Do not add Intel/x86_64 support, Intel-only features, universal builds, Rosetta compatibility work or Intel validation gates. CleanMyMac features that do not apply to this target are exclusions, not implementation requirements.

Pick work from [tasks/README.md](tasks/README.md), respecting its dependencies and acceptance criteria. The user requires frequent comparisons with the reference DMGs in Downloads: inspect the relevant reference before implementation, after the first working change, and before completing a task. Record the image/version, observations, and inspection limits in [tasks/reference-checks.md](tasks/reference-checks.md). Keep Luma's assets and interface original; mount references read-only and eject them afterward.

Run `bash Scripts/test.sh` before submitting implementation changes. Add regression fixtures for new filesystem behavior. Never test cleanup against real user data. Use `bash Scripts/preview.sh` to inspect native interface changes in both appearances. Planning/documentation-only changes need diff and link checks; they do not require a macOS build or native QA run.

Generated-data rules and explicit named ownership mappings belong in `Sources/LumaCore/Resources/CleanupRules.yaml`, validated through `RuleLoader`. Relationship resolution and protected/runtime policy remain in Swift. Each rule must have an exact bounded path, stable identifier, category, explanation, removal consequences, and owning app identifier when known. Do not use unrestricted globs or infer that old personal files are junk.

No scanner may mutate the filesystem. All cleanup builds an immutable `CleanupPlan` and calls `CleanupJournal.execute`; the journal preflights the whole plan and revalidates each move through SafetyEngine. Individual Trash moves are private. Preserve full-content duplicate keeper checks, unique logical totals, and durable per-item plan metadata. Restore must use the journal's verified recovery path. New paths must include rejection tests for protected folders, symlink escapes, stale identities, and ignore rules. Never add a permanent-delete fallback to make a failing operation succeed.

Direct Uninstall and selected-residue Move to Trash actions express user intent in the list. Prepare and validate their plans internally without a mandatory `ReviewSheet`, second selection panel or extra acknowledgement. Keep execution checks and durable outcomes; a validation failure should explain the blocked action inline. Cache removal and permanent Trash emptying use the specific approval required by the maintenance task.

Keep third-party dependencies small and behind project-owned interfaces. Native Apple APIs are preferred. Formatting should stay consistent with existing Swift; do not add a broad formatter or refactor prerequisite to the active queue.

Use original assets and compatible source licenses. The project is licensed GPL-3.0-or-later.

The native QA descriptions below record the existing implementation. During the relevant core implementation task, replace assertions that require obsolete review sheets or separate bundle/data selection with checks of the approved direct flow. Preserve core plan, identity, ownership, provider, stale-evidence and recovery tests; old presentation assertions cannot override the current scope.

Debug native review QA currently runs after `bash Scripts/build-app.sh debug` with `dist/Luma.app/Contents/MacOS/Luma --check-cleanup-review /tmp/luma-review.json` from the repository. It creates disposable workspace fixtures, checks existing sheet presentation and rejected duplicate evidence, writes its report, and quits. It never invokes cleanup.

Scans use `ScanRequest`/`ScanController` and dispatch through `ScanEngine`. Send bounded progress/coverage events; do not create a Task for each file or publish partial candidates into completed feature state. A cancelled worker must exit before a queued replacement starts. Preserve the captured scope on retry and keep preview-only results out of cleanup review. Run `bash Scripts/check-scan-sessions.sh` after a debug build for native scan/session changes; it uses only generated fixtures and never executes cleanup. Set `LUMA_SCAN_QA_OUTPUT_DIR` to a temporary directory only when retaining the synthetic reports/screenshots for inspection.

Filesystem work must use `FilesystemAccess` and synchronous `NonMaterializingIO.perform` scopes. Never span an `await` with a thread I/O policy or infer unmanaged ownership from a negative caller-scoped File Provider lookup. The current implementation excludes provider/unknown states from cleanup. The core iCloud task must distinguish metadata discovery, local-content access and supported mutation rather than weakening cleanup checks merely to list files. Revalidate capabilities at execution. Do not add automatic file icons, thumbnails or indexing reads through APIs that can delegate downloads outside the guarded thread. See [Safety.md](Documentation/Safety.md) for the current detection envelope and planned changes.

For cache additions, update [Cache-Support.md](Documentation/Cache-Support.md) with current primary provenance, exact layout/version evidence, consequences and unsupported decisions. Preserve installed-product validation and helper/process guards at execution. Record logical content during scans so views can compute unique subset totals; invalidate generated snapshots in both state owners after mutation outcomes.

For cleanup lifecycle changes, build the debug app and run `bash Scripts/check-cleanup-sessions.sh`. Its generated home and injected mover exercise real progress/Activity/Undo presentation in both appearances without invoking real Trash. Keep mutation cancellation separate from scan/review cancellation, and never check Stop between a started native mutation and its durable outcome. New recovery paths must preserve per-item results across restart without automatically repeating unknown moves.

For storage changes, run `bash Scripts/check-storage-browser.sh` after a debug build. It creates its own hierarchy, checks light/dark navigation, partial coverage and review, and never executes cleanup. Storage nodes are read-only observations; selection must capture fresh evidence and use the central cleanup plan/journal. Keep map remainders synthetic and all actions available through native list controls.

For application ownership/footprint changes, run `bash Scripts/check-application-footprint.sh` after a debug build. It creates a disposable app/home, checks native groups, partial/absent reads, separate bundle/data selection, review totals, retry and snapshot invalidation in both appearances without executing cleanup. Ownership paths belong in ApplicationRelationships; do not add per-view path matching or infer disposal permission from the footprint category.

Reset is outside the active core changes. If shared implementation changes affect existing reset behavior, preserve the distinct applicationReset plan intent and bundle exclusion, and run the application-footprint native checker for both modes. Add generated fixtures for changed subsets, helpers/unknown activity, partial outcomes and recreated Restore destinations. Never test reset against a personal application. Normal quit is user-started, may require save prompts, and must not become force termination.

## Contributing cleanup catalog entries

Generated rules and named ownership mappings live in `Sources/LumaCore/Resources/CleanupRules.yaml`. `Rules.swift` owns the runtime rule type and bundled-catalog boundary; `RuleLoader.swift` owns parsing/validation. Scanners and SafetyEngine never consume YAML types. Schema 1 is a single local UTF-8 YAML mapping of at most 1 MiB with `schemaVersion: 1`, a reviewable `catalogVersion`, `locale: en`, and `generated`/`ownership` arrays. Increment the catalog version when changing its content. There are no downloaded catalogs or user-supplied runtime overrides.

Validate the source catalog (or a proposed local file) and its fixtures with:

```sh
bash Scripts/validate-rules.sh
bash Scripts/validate-rules.sh /path/to/proposed-catalog.yaml
bash Scripts/test.sh --filter RuleCatalogTests
bash Scripts/test.sh
```

Both CI workflows validate the catalog and run the negative/equivalence fixtures as part of the Swift suite. The standalone validator reads metadata only; it does not scan or clean target paths. Validation does not install a proposed file into the app. All records must pass before any catalog becomes available. A missing/invalid bundled catalog reports an error at scan, relationship resolution and mutation validation; it cannot partially activate its valid entries. Rebuild the app after changing the bundled YAML.

A generated record requires `id`, `relativePath`, `category`, `safety`, `name`, `explanation`, `consequence`, `regeneration`, `profileLeaves`, `chromiumProfiles`, `tools`, `provenance`, and `reviewedOn`. `owner`, `appName`, and `requiredApplication` are optional (app caches require an owner). Names/explanations/consequences/regeneration are inline English display text; schema 1 does not resolve localization keys. Keep stable IDs and precise consequences. Record real source URLs or versioned source-history evidence in `provenance`, and quote `reviewedOn` as `YYYY-MM-DD`.

For example, a **synthetic fixture only**, appended to a test catalog, can use:

```yaml
- id: app.fixture.cache
  relativePath: Library/Caches/com.example.fixture
  category: caches
  safety: safe
  name: Fixture cache
  explanation: Generated test data in an exact disposable fixture folder.
  consequence: The fixture app must regenerate this data.
  regeneration: The fixture writer creates fresh data.
  owner: com.example.fixture
  profileLeaves: []
  chromiumProfiles: false
  tools: []
  provenance:
  - Disposable fixture; not evidence for a real product.
  reviewedOn: '2026-10-18'
```

Do not add this example to the shipping catalog. Real additions need supported-product path/lifecycle evidence and fixture tests proving adjacent personal/session/shared data is excluded. `RuleCatalogTests.contributorRuleUsesUnchangedScannerAndRuntimeSafety` demonstrates adding a validated fixture rule without changing scanner control flow. The baseline JSON fixture records the pre-migration 22-rule decision fields and five named mappings; do not rewrite it to make a migration regression pass. Add new expectations separately for deliberate scope changes.

Generated categories are `caches`, `logs`, or `developer`; safety is `safe` or `review`. Paths are exact home-relative paths: no `~`, environment substitutions, traversal, empty components, absolute paths, globs or includes. App caches/logs, the existing explicit developer units and the verified VS Code units are the supported generated scopes. Personal files, containers, provider roots and arbitrary application support are outside this schema’s generated authority. Chromium profile leaves are exactly Cache/Code Cache/GPUCache; Mozilla leaves are exactly cache2/startupCache. Arbitrary profile-leaf names and profile-root cleanup are unsupported. The existing four profile roots must retain their audited leaves; direct targets inside those profiles are rejected. Existing package/build/simulator/VS Code tool guards are required by path, including descendants of supported package/build caches. Unknown tool names fail validation.

`requiredApplication` is the existing VS Code verifier contract: `bundleName`, `bundleID`, `productName`, exact `version` and `commit`. Other app-specific support-data verifiers require a separately reviewed Swift boundary; a YAML record cannot invent one. The installed product and activity checks still run at execution. Catalog provenance is review evidence, not cryptographic ownership attestation.

An ownership record requires `relativePath`, exact `owner`, `classification: review`, `explanation`, `consequence`, `provenance`, and `reviewedOn`. Its explanation and consequence appear in the named relationship review; preserve existing wording during migrations. Ownership mappings never grant generated-data status or permission to discard data. Duplicate IDs/paths, reserved runtime IDs, overlapping generated roots, conflicting owners (including parent/child paths), unknown fields, missing text and unsupported versions reject the whole catalog. YAML aliases, anchors, merge keys, multiple documents and custom tags are unsupported.

Yams 6.2.2 is pinned by exact version and `Package.resolved`. Its current upstream release/maintenance and MIT licensing were reviewed during task 008: https://github.com/jpsim/Yams/releases/tag/6.2.2. Yams/libyaml are statically linked parsing dependencies; only the loader imports Yams. Their notices ship in `Resources/Third-Party-Notices.txt`. `build-app.sh` copies the package resource bundle into the app before signing, and the DMG verifier checks the packaged YAML and notices against source. Core protected-path, provider, identity, ownership, activity and journal policy remain in Swift.

Duplicate comparison changes should run `bash Scripts/check-duplicate-review.sh` after a debug build. The checker uses synthetic copies, captures comparison/proposal/final-review surfaces and rejects a changed keeper without cleanup. `LUMA_DUPLICATE_QA_OUTPUT_DIR` retains reports/captures temporarily. Comparison uses bounded pinned local bytes; do not add Quick Look/file-URL preview delegation. Keeper policy must preview every removal and revalidate current contents before applying a selection, while retaining the core plan/journal checks.

Volume-analysis changes should run `bash Scripts/check-storage-volumes.sh` after a debug build. It creates its own APFS image from generated files, mounts it read-only, verifies browsing/core review rejection in both appearances, ejects it while the app observes invalidation, and removes the fixture. It never uses the commercial reference image as a test volume. `LUMA_VOLUME_QA_OUTPUT_DIR` retains temporary reports/captures. Inspection-root descriptors cannot be used by cleanup; unknown provider/volume capabilities remain excluded.

Keep the existing System layout and metric set. Tasks 058/059 may fix availability labels, visible-consumer sampling and action correctness without expanding monitoring. If shared implementation changes affect it, run `bash Scripts/test.sh`, build the debug app and run `bash Scripts/check-monitoring-depth.sh` in a logged-in desktop session. Keep passive counters separate from active diagnostics. Use injected interface/battery observations for resets, gaps, transitions and missing fields; record actual hardware availability separately. The native benchmark compares full collection with the CPU/memory/disk core baseline, not an exact historical-release measurement. Do not substitute normalized charge capacity or private registry fields for unsupported battery health.
