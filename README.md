<p align="center"><img src="Resources/Luma.svg" width="88" height="88" alt="Luma icon"></p>
<h1 align="center">Luma</h1>
<p align="center">A clearer view of your Mac.</p>
<p align="center">Native SwiftUI · Liquid Glass · Local-first · GPL-3.0-or-later</p>

Luma is an open-source macOS maintenance app for understanding storage, reviewing app leftovers, finding exact duplicates, and monitoring application resources.

Every proposed cleanup has a path, an explanation, an ownership rule, and a consequence. You choose what changes. App, residue and cache selections move to the macOS Trash, with a local activity record. Maintenance also offers separately approved permanent emptying of supported local Trash contents.

**Status:** working development build for Apple Silicon (`arm64`), macOS 26 and later. The core workflows below are implemented; remaining review limits are recorded with their tasks.

## Implemented core

The owner reset the scope on 2026-10-19, then reviewed implementation at `c03e185`. The [core task queue](tasks/README.md) is 054–063. Tasks 054–057 implement direct app uninstall/Undo, automatic residue observations with in-place Trash, requested Storage discovery with saved browsing, and read-only iCloud metadata with owner-reported integration acceptance. Storage opens without scanning; broad discovery starts only when requested, and the optional folder picker remains available. Task 058 implements a focused native Liquid Glass menu flush below the menu bar, with two primary actions. Task 060 corrects app inventory, supported bundle-only uninstall, optional-data retention and bounded local icon preservation. Task 061 restores Overview/layout/focus. Task 062 keeps selections visible across browsing filters, aligns the map with its list and offers truthful larger fresh scans. Task 063 adds verified on-demand M2 battery condition, cycle count and maximum capacity, with honest charging and estimate states. Task 059 adds Maintenance with independently refreshed cache choices, local home Trash usage and permanent emptying, plus memory pressure and verified normal Quit. Cache cleanup and permanent Trash emptying each have one explicit approval in that view. The unstarted expansion backlog remains deleted; System keeps its current metric set.

## What you can do

- **Maintain your Mac explicitly.** Open Maintenance for independently refreshed supported caches and generated files, local home Trash, and memory pressure. Nothing starts selected. Cache cleanup asks once before moving the captured selection to Trash. Empty Trash asks separately before permanently removing reviewed unchanged entries; external/provider bins, links and changed contents stay excluded. Resource consumers are explicit snapshots so refresh cannot redirect Quit; normal Quit revalidates the sampled app instance and reports requested versus exited. macOS manages reusable memory; no system-wide RAM reclaim is claimed.
- **Review generated data.** Inspect Chrome, Safari, Firefox, Zen, Brave, and Edge caches; npm, Yarn Classic, and pnpm metadata caches; developer build files; simulator caches and logs; and verified VS Code 1.142.0 cache/log units. Cookies, sessions, project dependencies, shared stores, and device contents stay separate.
- **Remove selected residues in place.** Open Residues for automatically discovered findings and saved observations during refresh. Select exact identifier groups or individual paths and use the fixed Move to Trash footer, with Stop, Activity and Undo. Data whose exact bundle identifier has no installed owner remains a review candidate. Luma checks application folders, embedded helpers, and macOS Launch Services. Exact identifiers and explicit rules cover supported named support folders. Ownership is checked again before Trash.
- **Uninstall directly from the app list.** Inventory loads automatically. Click Uninstall on a supported row to move the bundle and verified exclusive caches/logs/preferences/saved state to Trash. Documents, support data and containers stay; shared or unknown ownership keeps all related data. Details remains optional, with separate footprint categories and honest unavailable sizes. Compact Undo checks eligible targets internally; Activity retains conflicts and individual Restore.
- **Scan storage when you choose.** Storage opens without starting a scan. Scan accessible Mac starts bounded, progressive discovery across readable local roots; the existing optional folder picker remains under Locations. Largest files and Explore share one saved index; Explore pairs proportional bubbles with a size-ranked list, breadcrumbs and history. Selection survives folders and filters, with direct home-local Trash/Undo in a fixed footer. Projects and Downloads are locations, with custom folders/external volumes available secondarily. Unknown/excluded contents remain coverage; per-path logical sizes stay separate from unique totals and reported volume capacity.
- **Compare exact duplicates.** Filter complete groups by path or size, compare full paths, dates and bounded local previews, and preview an explicit keeper or modification-date preference before applying a selection. Full SHA-256 content checks remain authoritative; hard-linked objects count once and at least one independent copy must remain per group.
- **Read meaningful system metrics.** See CPU, memory pressure, app/wired/compressed memory, reusable file cache, swap, thermals, passive single-interface network rates/session usage, reported battery details, and resource consumers grouped by app.
- **Follow and cancel scans.** Application rows appear before bundle sizing finishes. Every scan and app inspection has tracked progress and cancellation; replacement scans queue until the old worker stops. Previews stay read-only, completed snapshots retain their timestamps, and permission retries keep the chosen scope.
- **Stop cleanup and review Undo.** Cleanup has its own progress and Stop control. Activity groups reviewed sessions, separates moved and remaining items, and previews eligible Undo items alongside changed, missing and occupied paths. Interrupted moves are reconciled before recovery; Restore verifies identities and preserves occupied destinations.
- **Keep useful information nearby.** Open the compact menu-bar companion for live metrics and shortcuts. Expand an app’s resource row to inspect its helper processes.

For troubleshooting, open an application's footprint and choose **Review reset**. Nothing starts selected. Review caches/logs, preferences, saved state and other app data separately; the bundle stays installed. Request a normal quit and check again if the app or its helpers are running. Other app data may include documents or sign-in state. Cleanup uses the same confirmed Trash, Activity, Stop and non-overwriting Restore/Undo flow. Inspect again afterward to refresh results.

The interface follows **System appearance by default**, with optional Light and Dark overrides. Purple controls retain their deeper fill and white labels. Menu-bar visibility is enabled by default and can be changed in Settings. The main window starts at 1200 × 850 and supports native edge resizing; choose **Window → Restore Default Window Size** to return to that size, fitted to the current display. Closing the main window keeps the menu monitor running; choose Quit Luma to stop it. RAM usage and macOS memory pressure are shown separately: high usage alone does not mean high pressure.

## Core implementation status

| Area | Core change |
| --- | --- |
| Apps | Implemented direct uninstall with corrected eligibility, bounded vendor inventory, narrow companion filtering and preserved local icons |
| Overview and layout | Overview opens first with live summaries; residue hierarchy, click-away focus and compact footer |
| Residues | Implemented automatic observations and in-place Trash/Undo, with indented residue children |
| Storage | Implemented requested discovery/saved browsing/direct Trash, cross-folder Selected, consistent map/list and bounded fresh rescans |
| iCloud | Implemented metadata discovery; owner-reported integration acceptance in 057 |
| Menu companion | Implemented native Liquid Glass panel with Open Luma and Maintenance footer actions |
| System | Existing metrics retained; M2 cycles, condition and maximum capacity verified against the owner’s OS readings |
| Maintenance | Supported cache choices, one approval per cache/Trash action, bounded local permanent removal, memory pressure and verified Quit |

See the [roadmap](Documentation/Roadmap.md), [current specification](Documentation/Product-Spec.md), and [safety model](Documentation/Safety.md) for scope and current limits. No further feature track starts automatically after the core.

## Build and run

Requires an Apple Silicon Mac, macOS 26+, Swift 6.2+, and a macOS 26+ SDK from Xcode or compatible Command Line Tools.

```sh
git clone https://github.com/felixlheureux/luma.git
cd luma
bash Scripts/build-app.sh
open dist/Luma.app
```

Open `Package.swift` in Xcode for development. The bundled YAML catalog uses the MIT-licensed Yams/libyaml parser, and the disposable local analysis cache uses MIT-licensed GRDB with system SQLite, both pinned through Swift Package Manager; scanning and mutation policy remain project-owned. Third-party notices ship with the app.

Apple Silicon (`arm64`) is the only supported target, with M2 as reference hardware. Intel/x86_64, universal binaries and Rosetta compatibility are outside the project scope. The DMG filename includes its version and architecture. Automated releases target Apple Silicon. See [build and distribution details](Documentation/Distribution.md) for signing options. The personal [Luma Homebrew tap](https://github.com/felixlheureux/homebrew-luma) is available for Apple Silicon/macOS 26 or later:

```sh
brew install --cask felixlheureux/luma/luma
```

For an existing Homebrew installation:

```sh
brew upgrade --cask felixlheureux/luma/luma
```

The 0.2.2 development release fixes main-window sizing and keeps the core cleanup, Storage, Overview/menu, M2 battery and Maintenance features described above. It is not notarized; macOS may block first launch. See the [tested distribution behavior](Documentation/Distribution.md#personal-homebrew-tap-task-009). Official Homebrew cask submission remains separate.

Create a local installer after building:

```sh
bash Scripts/package-dmg.sh
```

## Automated releases

Pushing a version tag such as `v0.2.2` runs the Release workflow. It validates the tag against `CFBundleShortVersionString` in `Resources/Info.plist` and the installer README, runs the tests, builds an Apple Silicon app, verifies its signature, and packages a DMG. After those checks pass, it creates a GitHub prerelease with the DMG, `SHA256SUMS`, and generated change notes. Regular branch commits run CI without publishing releases.

For a new version, update the version and build number in `Resources/Info.plist`, update the version heading in `Resources/Installer-ReadMe.txt`, and commit and push those changes before tagging that commit:

```sh
git tag -a v0.2.2 -m "Luma 0.2.2"
git push origin v0.2.2
```

These commands illustrate the release process; use a new version for each release, and the tag must match the committed app version. Published releases are not overwritten. Current automated releases are development prereleases for macOS 26+ and Apple Silicon.

To test the complete build and packaging process without publishing, select **Actions → Release → Run workflow** on GitHub, or run `gh workflow run release.yml --ref main`. The DMG and checksum are available in that run’s artifacts for 14 days. This manual build never creates a release. GitHub’s built-in workflow token handles publication; no personal access token is required.

## Privacy and safety

Luma analyzes files locally. It has no telemetry, account system, root helper, or privileged background daemon. Application inventory and residue discovery load automatically on entry. Storage opens with saved metadata only and scans when requested; specialized checks also run on request. Lightweight monitoring runs while the app is open.

- No cleanup item is selected automatically.
- Personal files, generated data, and review candidates remain distinct.
- Leftovers are **potentially unclaimed data**, not proof that a file is unnecessary. They can contain documents or preferences worth keeping for a reinstall.
- Apple data, shared group containers, fuzzy folder-name matches, unsafe links, and protected locations are excluded from leftover cleanup.
- The Safety Engine rechecks descriptor-pinned paths and parent chains, identities, owners, volumes, ignore rules, and stale results before Trash.
- Empty Trash is a separate permanent operation restricted to the accessible current-user home Trash resolved by Foundation. It freezes top-level and descendant observations, preserves new/changed/unsupported items, never recursively removes a directory, records per-entry outcomes and disables complete Restore for affected trees. Interrupted removal is not retried automatically; journaling does not make permanent deletion reversible.
- Multi-item cleanup stops on failure and records completed moves. Restore requires an unchanged Trash item and original parent chain; older records without parent evidence use Finder Restore.

This is an early development build. Cleanup and Restore use a durable journal, with file identity checks and recovery review in Activity. Descriptor checks strengthen identity validation; the final native Trash pathname race remains documented. Read the [safety model](Documentation/Safety.md) before cleanup of important data.


Local Storage traversal and ordinary cleanup skip reported cloud/provider scopes, dataless content, network storage and unavailable metadata. A separate read-only adapter supplements Storage with available iCloud filesystem and provisional indexed metadata, including recognized synced Desktop/Documents roots. Cloud rows distinguish downloaded, online-only and unknown states, logical size and known local allocation, with generic icons and Finder management. They never enter local totals or Trash, including downloaded provider files. Discovery does not request downloads; unavailable or unindexed hierarchy remains partial. The owner reports manual iCloud integration acceptance in task 057. Coverage explains skipped locations and offers Finder handoffs; app icons use bounded, policy-checked local bundle resources with a symbol fallback. See [the safety model](Documentation/Safety.md#provider-aware-access-task-047) for detection limits and supported local behavior.

## Development

```sh
bash Scripts/build-app.sh debug
bash Scripts/test.sh
bash Scripts/validate-rules.sh
bash Scripts/check-window-lifecycle.sh
bash Scripts/check-native-ux.sh
bash Scripts/preview.sh
```

See the [cache support matrix](Documentation/Cache-Support.md) for supported builds, provenance, consequences and explicitly unavailable families. Generated findings require a fresh scan after cleanup or Restore.

The tests cover verified app layouts, adjacent-data exclusions, hard-link-aware group/selection totals, provider/dataless access, thread-policy restoration, provider-state changes before mutations, scan replacement, late events, stopping/timeouts, progressive inventory, scoped permission retry, protected paths, symlink escapes, stale scans, ownership, reinstalled apps, browser and package cache boundaries, permission exclusions, active tools, interrupted cleanup and restore, hard links, hashing, memory accounting, and process grouping. Fixtures are disposable and project-local. After building the app, the lifecycle smoke check requires a logged-in desktop session and verifies that closing the window preserves monitoring, reopening works, and explicit Quit exits.

The preview script renders Luma’s own view content in Light and Dark without cleaning files or requesting screen/audio recording permission. These in-process renders cannot reproduce every native window chrome or composited glass layer. Generated images and local diagnostics are excluded from the repository.

Shortcuts: `Command-K` searches, `Command-R` refreshes supported views, `Command-1` through `Command-6` open Overview/Storage/Apps/Residues/Maintenance/System, `Command-9` opens Activity, and `Shift-Command-D` changes the manual appearance override. Choose System in Settings to follow macOS again.

Overview is the first page on each new launch, including when an older saved preference names Storage. Reopening the running window retains its page. Overview links use the same core routes and do not start Storage discovery.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Luma owns its scanner logic, rule semantics, ownership checks, duplicate engine, and Safety Engine. Contributions should keep destructive decisions inspectable and test unsafe cases.

The commercial app supplied during development was a product reference only. No source code, binary resources, or artwork from CleanMyMac or Pearcleaner is included.

## License

[GNU GPL version 3 or later](LICENSE).

Debug native scan QA: build with `bash Scripts/build-app.sh debug`, then run `bash Scripts/check-scan-sessions.sh` in a logged-in desktop session. It checks light/dark native scan and inspection cancellation, read-only previews, scoped permission retry, provider exclusions and totals, navigation, Settings, window reopening and continued menu monitoring using 30 synthetic apps with 6,000 files. It never invokes cleanup. Timing measurements describe that fixture on the current machine, not a universal responsiveness guarantee.

Debug native cleanup QA: after a debug build, run `bash Scripts/check-cleanup-sessions.sh`. It checks safe Stop during an injected fixture move, durable partial Activity, direct Undo without a preview sheet, restoration, and continued monitoring/menu operation in both appearances. All files live under a generated fixture home; it never calls real macOS Trash. `LUMA_CLEANUP_QA_OUTPUT_DIR` retains synthetic reports and own-window captures in a temporary directory.

Debug native storage QA: after a debug build, run `bash Scripts/check-storage-browser.sh`. A generated fixture home verifies idle cold/warm opening, requested discovery, cached history, cross-folder selection, direct injected Trash/Undo, pending/failed scopes, old-volume/new-scope isolation, native Search, narrow windows and idle settling in Light/Dark/System. It never scans personal folders or invokes real Trash. `LUMA_STORAGE_QA_OUTPUT_DIR` retains temporary reports and captures, including centered empty/results layouts. `LUMA_STORAGE_QA_FILES=8000` exercises the larger fixture and records main-actor responsiveness.

Task 007 was closed at the user’s request with manual release checks deferred. The debug native UX smoke review visits the current core pages in Light, Dark and System appearance with standard and high-contrast window appearances, retains optional own-window captures, and samples layout latency while monitoring continues. Set `LUMA_UX_QA_OUTPUT_DIR` to retain its temporary report. This does not verify VoiceOver, keyboard traversal, system accessibility preference changes or GPU frame performance. Manual accessibility and release review remain required before claiming a fully reviewed 0.3.0 release.

Cleanup knowledge and named ownership mappings ship in a versioned YAML catalog. Invalid catalogs fail as a whole, and current filesystem/ownership/provider/activity checks remain in Swift. Contributors can validate catalog edits with `bash Scripts/validate-rules.sh`; see [CONTRIBUTING.md](CONTRIBUTING.md#contributing-cleanup-catalog-entries). No rule downloads or runtime catalog overrides are enabled.

Debug native Smart Check QA: after a debug build, run `bash Scripts/check-smart-check.sh`. Generated fixtures exercise progressive completion, a failed category followed by successful checks, exact scoped navigation, the ordinary confirmation sheet, invalidation, unavailable measurements and continued monitoring in both appearances. No cleanup or personal-folder scan is invoked. `LUMA_SMART_QA_OUTPUT_DIR` retains temporary reports/captures. A basic Tab event check does not establish full keyboard traversal or VoiceOver coverage.

Repeated Storage/Duplicates scans reuse validated display metadata and duplicate hashes on supported local APFS volumes. Current discovery, access/provider checks and coverage still run; cleanup always verifies current content. Settings → General → Saved analysis offers **Clear analysis cache**, preserving Activity and ignored paths. Other filesystems and unavailable/corrupt caches use fresh analysis. FSEvents supplies bounded invalidation hints. Storage does not run a filesystem-event refresh loop. Requested scans and targeted updates after Restore retain unrelated observations. Other specialized analyses remain explicit.

Debug native index QA: after a debug build, run `bash Scripts/check-analysis-index.sh`. Disposable light/dark fixtures cover warm metadata/hash reuse, native event invalidation, navigation continuity, cache clearing, preserved Activity/ignores and monitoring. It never invokes cleanup or scans personal folders. `LUMA_INDEX_QA_OUTPUT_DIR` retains temporary reports/captures. Run `LUMA_INDEX_BENCHMARK=1 bash Scripts/test.sh --filter AnalysisIndexTests.benchmark` for the fixed benchmark; conditions/results are recorded in task 014.

Residue groups default to exact bundle-identifier order, with mixed-state group checkboxes, filtering, collapse and an optional largest-first sort. Selection includes hidden groups and never expands to refresh arrivals. Bounded saved observations load during refresh; current identity and ownership are checked internally for every action. Unaffected findings and valid selections stay visible after cleanup. `bash Scripts/check-cleanup-feedback.sh` checks automatic cold/warm entry, direct actions, group selection, navigation, narrow windows and Undo in Light/Dark/System using generated data and an injected fixture mover, never real Trash. `LUMA_FEEDBACK_QA_OUTPUT_DIR` retains temporary captures/reports.

Storage volume analysis currently has native read-only APFS-image evidence. HFS+, network/provider-managed storage and volumes without stable identifiers/current capability evidence are unsupported or unverified. Unmounting/replacing a target clears live results; a new explicit scan validates volume/root identity. Available-for-important-usage is a system estimate, filesystem free space is a separate observation, and neither is a promise of cleanup recovery.

Debug native monitoring QA: after a debug build, run `bash Scripts/check-monitoring-depth.sh`. Injected providers verify single-interface rates, supported/missing battery fields, detail caching/coalescing/failure/source changes, desktop states and menu-only monitoring in Light/Dark/System. Actual Luma battery details are compared with the structured Apple Power report separately from fixtures. Battery details refresh on entering System or using Refresh, with five-minute reuse and their observation time displayed. It measures lightweight passive provider collection against the CPU/memory/disk core baseline and records actual hardware field availability. No active network test, mutation or personal-folder scan is invoked. `LUMA_MONITORING_QA_OUTPUT_DIR` retains temporary reports/captures.

Task 060 keeps supported vendor-folder apps consistent across inventory, Search and Restore. Two-component identifiers can uninstall bundle-only; unsafe optional roots stay intact with an explanation. Ordinary macOS Trash rights apply to verified bundles without an administrator helper. Asset-catalog icons retain a generic fallback, and actual root/mixed-owner native moves remain unverified because administrator fixture authority was unavailable. See [the task evidence](tasks/060-app-inventory-and-uninstall-corrections.md) for accepted native checks and limits.
