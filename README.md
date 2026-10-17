<p align="center"><img src="Resources/Luma.svg" width="88" height="88" alt="Luma icon"></p>
<h1 align="center">Luma</h1>
<p align="center">A clearer view of your Mac.</p>
<p align="center">Native SwiftUI · Liquid Glass · Local-first · GPL-3.0-or-later</p>

Luma is an open-source macOS maintenance app for understanding storage, reviewing app leftovers, finding exact duplicates, and monitoring application resources.

Every proposed cleanup has a path, an explanation, an ownership rule, and a consequence. You choose what changes. Reviewed selections move to the macOS Trash, with a local activity record.

**Status:** working development build for macOS 26 and later. The workflows below are implemented; the complete product specification remains in progress.

## What you can do

- **Review generated data.** Inspect Chrome, Safari, Firefox, Zen, Brave, and Edge caches; npm, Yarn Classic, and pnpm metadata caches; developer build files; and simulator caches and logs. Cookies, sessions, project dependencies, shared stores, and device contents stay separate.
- **Find app leftovers.** Review data whose exact bundle identifier has no installed owner. Luma checks application folders, embedded helpers, and macOS Launch Services. Exact identifiers and explicit rules cover supported named support folders. Ownership is checked again before Trash.
- **Understand app footprints.** Inventory apps and inspect exact matches for caches, preferences, saved state, and application support. Uninstall selections are explicit.
- **Explore storage.** Choose a folder, see a proportional map, and filter files by size, age, or installer type. Personal files are never classified as junk.
- **Verify duplicates.** Compare sizes, partial hashes, and full SHA-256 content. Hard-linked copies count once, and at least one copy must remain per group.
- **Read meaningful system metrics.** See CPU, memory pressure, app/wired/compressed memory, reusable file cache, swap, thermals, battery charge, and resource consumers grouped by app.
- **See your scan coverage.** Follow progress as locations are inspected, review results by category, and distinguish empty or absent locations from permission failures and safety exclusions.
- **Recover interrupted operations.** Cleanup and Restore record their intent before moving files. Activity reconciles interrupted moves, verifies identities before Restore, and preserves occupied destinations.
- **Keep useful information nearby.** Open the compact menu-bar companion for live metrics and shortcuts. Expand an app’s resource row to inspect its helper processes.

The interface follows **System appearance by default**, with optional Light and Dark overrides. Purple controls retain their deeper fill and white labels. Menu-bar visibility is enabled by default and can be changed in Settings. Closing the main window keeps the menu monitor running; choose Quit Luma to stop it. RAM usage and macOS memory pressure are shown separately: high usage alone does not mean high pressure.

## What is still in progress

| Area | Current scope | Remaining work |
| --- | --- | --- |
| Clean | 18 audited rules; browser profile caches, package caches, simulator diagnostics, live progress, and scan coverage | More cache versions and ecosystems, finer selection, device backups |
| Applications | Inventory, exact footprints, reviewed uninstall, potential leftovers | App reset, broader ownership evidence, and update discovery |
| Storage | Chosen-folder map and file filters | Nested browsing, volumes, developer projects, and incremental indexing |
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
- The Safety Engine rechecks paths, identities, owners, volumes, ignore rules, and stale results before Trash.
- Multi-item cleanup stops on failure and records completed moves. Restore works while the item remains in Trash and its original location is available.

This is an early development build. Cleanup and Restore use a durable journal, with file identity checks and recovery review in Activity. Further filesystem race hardening remains on the roadmap. Read the [safety model](Documentation/Safety.md) before cleanup of important data.

## Development

```sh
bash Scripts/build-app.sh debug
bash Scripts/test.sh
bash Scripts/check-window-lifecycle.sh
bash Scripts/preview.sh
```

The tests cover protected paths, symlink escapes, stale scans, ownership, reinstalled apps, browser and package cache boundaries, permission exclusions, active tools, interrupted cleanup and restore, hard links, hashing, memory accounting, and process grouping. Fixtures are disposable and project-local. After building the app, the lifecycle smoke check requires a logged-in desktop session and verifies that closing the window preserves monitoring, reopening works, and explicit Quit exits.

The preview script captures light and dark app windows without cleaning files. Its fallback cannot reproduce every native composited glass layer when window capture is unavailable. Generated screenshots and local diagnostics are excluded from the repository.

Shortcuts: `Command-K` searches, `Command-R` rescans, `Command-1` through `Command-9` navigate, and `Shift-Command-D` changes the manual appearance override. Choose System in the toolbar to follow macOS again.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Luma owns its scanner logic, rule semantics, ownership checks, duplicate engine, and Safety Engine. Contributions should keep destructive decisions inspectable and test unsafe cases.

The commercial app supplied during development was a product reference only. No source code, binary resources, or artwork from CleanMyMac or Pearcleaner is included.

## License

[GNU GPL version 3 or later](LICENSE).
