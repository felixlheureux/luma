<p align="center"><img src="Resources/Luma.svg" width="88" height="88" alt="Luma icon"></p>
<h1 align="center">Luma</h1>
<p align="center">A clearer view of your Mac.</p>
<p align="center">Native SwiftUI · Liquid Glass · Local-first · GPL-3.0-or-later</p>

Luma is an open-source macOS maintenance app for understanding storage, reviewing app leftovers, finding exact duplicates, and monitoring application resources.

Every proposed cleanup has a path, an explanation, an ownership rule, and a consequence. You choose what changes. Reviewed selections move to the macOS Trash, with a local activity record.

**Status:** working development build for macOS 26 and later. The workflows below are implemented; the complete product specification remains in progress.

## What you can do

- **Review generated data.** Inspect Chrome, Safari, Firefox, Zen, Brave, and Edge caches; npm, Yarn Classic, and pnpm metadata caches; developer build files; simulator caches and logs; and verified VS Code 1.142.0 cache/log units. Cookies, sessions, project dependencies, shared stores, and device contents stay separate.
- **Find app leftovers.** Review data whose exact bundle identifier has no installed owner. Luma checks application folders, embedded helpers, and macOS Launch Services. Exact identifiers and explicit rules cover supported named support folders. Ownership is checked again before Trash.
- **Understand app footprints.** Inventory apps, then inspect exact identifiers, explicit named ownership mappings and metadata-verified containers. Bundle, generated data, settings/state and potential user data have separate totals. Unreadable paths retain unknown sizes; bundle uninstall and related-data selections are separate and explicit.
- **Explore storage.** Choose a folder, drill into its hierarchy with breadcrumbs, compare a synchronized map and list, show hidden entries, sort by size/name, and filter the current folder by size, age, or installer type. Personal files are never classified as junk.
- **Verify duplicates.** Compare sizes, partial hashes, and full SHA-256 content. Hard-linked copies count once, and at least one copy must remain per group.
- **Read meaningful system metrics.** See CPU, memory pressure, app/wired/compressed memory, reusable file cache, swap, thermals, battery charge, and resource consumers grouped by app.
- **Follow and cancel scans.** Application rows appear before bundle sizing finishes. Every scan and app inspection has tracked progress and cancellation; replacement scans queue until the old worker stops. Previews stay read-only, completed snapshots retain their timestamps, and permission retries keep the chosen scope.
- **Stop cleanup and review Undo.** Cleanup has its own progress and Stop control. Activity groups reviewed sessions, separates moved and remaining items, and previews eligible Undo items alongside changed, missing and occupied paths. Interrupted moves are reconciled before recovery; Restore verifies identities and preserves occupied destinations.
- **Keep useful information nearby.** Open the compact menu-bar companion for live metrics and shortcuts. Expand an app’s resource row to inspect its helper processes.

For troubleshooting, open an application's footprint and choose **Review reset**. Nothing starts selected. Review caches/logs, preferences, saved state and other app data separately; the bundle stays installed. Request a normal quit and check again if the app or its helpers are running. Other app data may include documents or sign-in state. Cleanup uses the same confirmed Trash, Activity, Stop and non-overwriting Restore/Undo flow. Inspect again afterward to refresh results.

The interface follows **System appearance by default**, with optional Light and Dark overrides. Purple controls retain their deeper fill and white labels. Menu-bar visibility is enabled by default and can be changed in Settings. Closing the main window keeps the menu monitor running; choose Quit Luma to stop it. RAM usage and macOS memory pressure are shown separately: high usage alone does not mean high pressure.

## What is still in progress

| Area | Current scope | Remaining work |
| --- | --- | --- |
| Clean | 22 bounded rules; verified VS Code cache/log units, app/category grouping, unique logical totals, browser/package caches, simulator diagnostics and scan coverage | More cache versions and ecosystems, finer selection, device backups |
| Applications | Inventory, categorized footprints, shared ownership evidence, reviewed uninstall/reset, potential leftovers | Update discovery |
| Storage | Cached hierarchical browser, breadcrumbs, map/list details, current-folder filters and explicit manual review | Volumes, developer projects, and persistent incremental indexing |
| Duplicates | Exact content verification | Similar-photo analysis and comparison |
| Optimizer | Grouped resource consumers and normal quit requests | Measured recommendations and audited maintenance |
| Privacy | macOS permission shortcuts; separation from cache cleanup | Browser privacy workflows and a permissions overview |
| System | CPU, memory, swap, thermals, uptime, battery charge | Network, battery health, disk diagnostics, and connected devices |

See the [roadmap](Documentation/Roadmap.md), [complete specification](Documentation/Product-Spec.md), and [safety model](Documentation/Safety.md) for scope and current limits.

## Build and run

Requires macOS 26+, Swift 6.2+, and a macOS 26+ SDK from Xcode or compatible Command Line Tools.

```sh
git clone https://github.com/felixlheureux/luma.git
cd luma
bash Scripts/build-app.sh
open dist/Luma.app
```

Open `Package.swift` in Xcode for development. There are no third-party runtime dependencies.

Builds target the local architecture, and the DMG filename includes its version and architecture. Automated releases currently target Apple Silicon. See [build and distribution details](Documentation/Distribution.md) for signing options. There is no official Homebrew cask yet.

Create a local installer after building:

```sh
bash Scripts/package-dmg.sh
```

## Automated releases

Pushing a version tag such as `v0.2.1` runs the Release workflow. It validates the tag against `CFBundleShortVersionString` in `Resources/Info.plist` and the installer README, runs the tests, builds an Apple Silicon app, verifies its signature, and packages a DMG. After those checks pass, it creates a GitHub prerelease with the DMG, `SHA256SUMS`, and generated change notes. Regular branch commits run CI without publishing releases.

For a new version, update the version and build number in `Resources/Info.plist`, update the version heading in `Resources/Installer-ReadMe.txt`, and commit and push those changes before tagging that commit:

```sh
git tag -a v0.2.1 -m "Luma 0.2.1"
git push origin v0.2.1
```

These commands are an example for the next version; the tag must match the committed app version. Published releases are not overwritten. Current automated releases are development prereleases for macOS 26+ and Apple Silicon.

To test the complete build and packaging process without publishing, select **Actions → Release → Run workflow** on GitHub, or run `gh workflow run release.yml --ref main`. The DMG and checksum are available in that run’s artifacts for 14 days. This manual build never creates a release. GitHub’s built-in workflow token handles publication; no personal access token is required.

## Privacy and safety

Luma analyzes files locally. It has no telemetry, account system, root helper, or privileged background daemon. Scans run on request; lightweight monitoring runs while the app is open.

- No cleanup item is selected automatically.
- Personal files, generated data, and review candidates remain distinct.
- Leftovers are **potentially unclaimed data**, not proof that a file is unnecessary. They can contain documents or preferences worth keeping for a reinstall.
- Apple data, shared group containers, fuzzy folder-name matches, unsafe links, and protected locations are excluded from leftover cleanup.
- The Safety Engine rechecks descriptor-pinned paths and parent chains, identities, owners, volumes, ignore rules, and stale results before Trash.
- Multi-item cleanup stops on failure and records completed moves. Restore requires an unchanged Trash item and original parent chain; older records without parent evidence use Finder Restore.

This is an early development build. Cleanup and Restore use a durable journal, with file identity checks and recovery review in Activity. Descriptor checks strengthen identity validation; the final native Trash pathname race remains documented. Read the [safety model](Documentation/Safety.md) before cleanup of important data.


Provider-aware access skips reported cloud/provider scopes, dataless content, network storage and unavailable metadata before ordinary inspection or cleanup. Downloaded provider files remain excluded. Coverage explains skipped locations and offers Finder handoffs; app views use generic icons to avoid implicit file previews. See [the safety model](Documentation/Safety.md#provider-aware-access-task-047) for detection limits and supported local behavior.

## Development

```sh
bash Scripts/build-app.sh debug
bash Scripts/test.sh
bash Scripts/check-window-lifecycle.sh
bash Scripts/preview.sh
```

See the [cache support matrix](Documentation/Cache-Support.md) for supported builds, provenance, consequences and explicitly unavailable families. Generated findings require a fresh scan after cleanup or Restore.

The tests cover verified app layouts, adjacent-data exclusions, hard-link-aware group/selection totals, provider/dataless access, thread-policy restoration, provider-state changes before mutations, scan replacement, late events, stopping/timeouts, progressive inventory, scoped permission retry, protected paths, symlink escapes, stale scans, ownership, reinstalled apps, browser and package cache boundaries, permission exclusions, active tools, interrupted cleanup and restore, hard links, hashing, memory accounting, and process grouping. Fixtures are disposable and project-local. After building the app, the lifecycle smoke check requires a logged-in desktop session and verifies that closing the window preserves monitoring, reopening works, and explicit Quit exits.

The preview script captures light and dark app windows without cleaning files. Its fallback cannot reproduce every native composited glass layer when window capture is unavailable. Generated screenshots and local diagnostics are excluded from the repository.

Shortcuts: `Command-K` searches, `Command-R` rescans, `Command-1` through `Command-9` navigate, and `Shift-Command-D` changes the manual appearance override. Choose System in Settings to follow macOS again.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Luma owns its scanner logic, rule semantics, ownership checks, duplicate engine, and Safety Engine. Contributions should keep destructive decisions inspectable and test unsafe cases.

The commercial app supplied during development was a product reference only. No source code, binary resources, or artwork from CleanMyMac or Pearcleaner is included.

## License

[GNU GPL version 3 or later](LICENSE).

Debug native scan QA: build with `bash Scripts/build-app.sh debug`, then run `bash Scripts/check-scan-sessions.sh` in a logged-in desktop session. It checks light/dark native scan and inspection cancellation, read-only previews, scoped permission retry, provider exclusions and totals, navigation, Settings, window reopening and continued menu monitoring using 30 synthetic apps with 6,000 files. It never invokes cleanup. Timing measurements describe that fixture on the current machine, not a universal responsiveness guarantee.

Debug native cleanup QA: after a debug build, run `bash Scripts/check-cleanup-sessions.sh`. It checks safe Stop during an injected fixture move, durable partial Activity, the actual Undo sheet, restoration, and continued monitoring/menu operation in both appearances. All files live under a generated fixture home; it never calls real macOS Trash. `LUMA_CLEANUP_QA_OUTPUT_DIR` retains synthetic reports and own-window captures in a temporary directory.

Debug native storage QA: after a debug build, run `bash Scripts/check-storage-browser.sh`. It checks cached three-level navigation, selection clearing, map remainder totals, partial/provider/empty states, actual review-sheet presentation and stale-selection rejection in both appearances using 1,030 generated nodes. It never executes cleanup. `LUMA_STORAGE_QA_OUTPUT_DIR` retains synthetic reports and own-window captures in a temporary directory.
