# 060 — Correct app inventory, icons and uninstall eligibility

Status: Done

Priority: P1

Corrects: completed [054](054-direct-uninstall.md), including app observations shared by [055](055-residues.md)

## Outcome

Apps shows a stable list of genuine applications with consistent icons. Supported bundles uninstall directly; unrelated ownership rules or optional-data failures do not reject the bundle. Blocked actions explain the actual limitation.

Target native Apple Silicon (`arm64`), macOS 26+, with M2 as reference hardware. Keep 054's completed evidence intact; this is a corrective pass.

## Scope

- Separate verified bundle eligibility from related-data matching. A legitimate two-component bundle identifier must not fail the related-data matcher's three-component rule. Unsupported relationships mean bundle-only removal, retaining related data.
- Retain an optional cache/log/settings root whole when preparation cannot inspect/include it safely; show what stayed without blocking an independently eligible bundle. After plan capture, changed evidence or failed moves still stop/report partial outcomes. No silent replanning or mutation retry.
- Separate selected-installation helper validation from broad application-presence discovery. Validate the chosen bundle and its verified helpers, preserving exact embedded-owner relationships wherever required. Unrelated unreadable trees must not block bundle-only removal when selected-installation evidence is complete; incomplete required evidence remains blocking. Do not skip a subtree solely because its enclosing app has a different identifier. Preserve complete fail-closed ownership discovery for residues.
- Evaluate root-owned and mixed-owner bundles using supported ordinary native Trash rights. Define a narrow verified-bundle policy where the current user can perform the operation; otherwise show the actual permission/capability reason. Do not relax ownership globally for Library/personal data, change permissions, install a privileged helper or permanently delete.
- Use one bounded display inventory across refresh, residue observations, Search and Restore. Include supported genuine vendor-subfolder apps within existing Applications roots, excluding embedded helpers/package internals. Align bundle mutation scope with that inventory. Visiting Residues or refreshing must not unpredictably add/remove rows.
- Omit verified vendor companion uninstallers from ordinary rows using metadata/verified product associations. Keep them in ownership-presence checks. Do not use a blanket Uninstall-name filter, hide independent removal utilities, launch vendor executables or infer additional cleanup authority.
- Preserve/enrich icons across progressive inventory, residue rows and Undo/Restore; metadata-only merges must not replace known icons with nil. Respect macOS `CFBundleIconName`/`CFBundleIconFile` meanings and precedence: an asset name is not a loose `.icns` filename. Support bounded local resources and verified public asset APIs only within the no-download boundary. Unsupported assets retain a generic fallback and recorded limit; no private CoreUI/catalog parsing or unchecked Finder/Quick Look delegation.

Preserve central identity, owner/helper, provider, ignore, protected-path and recovery checks, including protected Apple/Luma bundles. Keep direct row actions and optional Details; no wizard, reset work, companion-management screen or general framework.

## Acceptance

- [x] Supported two-component IDs uninstall bundle-only when related matching is unavailable; protected/unverifiable/provider cases remain blocked accurately.
- [x] Unsafe optional roots stay intact without blocking the safe bundle. Captured-target changes, ignored descendants and partial outcomes remain protected without automatic retries.
- [x] Unrelated denied helpers do not block the chosen app when its required evidence is complete; denied/active/unknown chosen helpers do. Matching embedded owners beneath differently identified apps are not lost.
- [x] Direct-root/vendor-subfolder membership and action eligibility stay consistent across Residues, refresh and Restore. Companion filtering preserves independent utilities and ownership detection.
- [x] Icons survive metadata merges and Undo/Restore. Loose-resource/key-precedence and supported asset cases are covered; unsupported/provider resources fall back without downloads.
- [x] Root/mixed-owner behavior has a documented supported/unsupported decision and disposable-fixture evidence, without general privilege relaxation.

## Validation

Extend existing uninstall, inventory/icon and native application checkers. Generated fixtures cover two-/three-component IDs, same-ID copies, protected identifiers, optional-root denial/links/ignores, unrelated versus chosen denied helpers, a matching embedded owner under a differently identified app, vendor subfolders, companion associations, ICNS/PNG, both icon keys, asset-only support/fallback and Restore. Retain central safety regressions.

Inspect direct actions, reasons, logos, keyboard access and narrow layout in Light/Dark/System on native Apple Silicon. Ordinary workflow checks use disposable apps and injected movers. Where available, test normal native Trash rights on generated root/mixed-owner bundles; record unavailable authority instead of bypassing permissions or testing personal apps. Verify public icon APIs and no-materialization separately from screenshots. Source review is not native acceptance.

## Source evidence — c03e185

- Eligibility/optional-data blockers: [ApplicationActions.swift](../Sources/LumaApp/ApplicationActions.swift), [ApplicationRelationships.swift](../Sources/LumaCore/ApplicationRelationships.swift), [ApplicationUninstall.swift](../Sources/LumaCore/ApplicationUninstall.swift).
- Unrelated helper traversal: [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [CleanupPlan.swift](../Sources/LumaCore/CleanupPlan.swift).
- Divergent inventory, mutation scope and ownership restrictions: [Scanners.swift](../Sources/LumaCore/Scanners.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Filesystem.swift](../Sources/LumaCore/Filesystem.swift).
- Icon loss/key handling: [Scanners.swift](../Sources/LumaCore/Scanners.swift), [ApplicationIcon.swift](../Sources/LumaCore/ApplicationIcon.swift), [ApplicationIconView.swift](../Sources/LumaApp/ApplicationIconView.swift). Verify semantics against Apple's [Core Foundation keys reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

Follow [README](README.md) for reference comparisons/evidence. Creating this task claims no implementation or native validation.

## Implementation — 2026-10-19

- `ApplicationUninstall.supportsBundle` separates two-component bundle eligibility from strict related-data matching. Exact protected identifiers, providers and unverified bundles remain blocked. Optional roots are captured whole or retained whole before plan creation, with recorded reasons; execution never silently drops/retries a captured target.
- Direct plans discover helpers from the selected installation at whole-plan preflight and again before each move. Unknown/denied/linked selected helpers fail closed. Broad residue ownership discovery still includes embedded owners beneath differently identified apps and never supplies ordinary display rows.
- `ApplicationInventory` bounds display membership to direct apps and two vendor-folder levels, with 10,000 entries per root. Packages/helpers remain excluded. Exact paired product-name/identifier companion associations are filtered only from display. Refresh retains observations for unreadable inventory locations; denied sizing does not retain deleted rows. Apps/Search share the same records; vendor mutation and Restore scopes agree.
- Same-installation metadata merges preserve known icons; Restore reloads bounded local resources. PNG and ICNS are covered. `CFBundleIconName` takes precedence over the loose-file key and is never converted into an `.icns` path. Asset catalogs remain an explicit unsupported fallback until a public API's bounded/nondelegated read behavior is verified. No Finder, Quick Look or private catalog parsing was added.
- The exact-bundle policy supports current-user/root contents only when native ordinary deletion rights allow the operation and immutable/append flags are absent. All identities/owners remain fingerprinted through Trash, Restore and reconciliation. Library/personal-data ownership restrictions are unchanged. Current-user/immutable fixtures exercise this decision; actual root/mixed-owner native moves remain unverified because `sudo -n true` reports that a password is required. No administrator credential, permission change or personal application was used.


## Accepted validation

- Full Swift suite: 327 reported tests across 33 suites pass, including the existing opt-in skips. New fixtures cover two-component eligibility, vendor/package boundaries, narrow companion associations, ownership-only membership, unrelated/chosen denied helpers, matching embedded owners, ignored/linked/denied optional roots, captured changes, ordinary native rights/immutable flags, PNG/ICNS/key precedence and icon merges/Restore.
- Native applications: Light/Dark/System pass optional footprint/reset regressions and direct vendor-subfolder two-component Uninstall/Undo, known-icon merges, scoped partial inventory retention, deletion despite unrelated size failures, blocked reasons, navigation during mutation, selected state, narrow windows and stale-inventory Restore. Accepted injected one-bundle moves take 0.567–0.577 s for a 455-byte synthetic bundle plus synthetic cache/preferences/support data on Apple M2/16 GiB/macOS 27.0.1. These are fixture observations, not real Trash performance. Native screenshots of the original UI and colored fixture icon were inspected.
- Native residues: Light/Dark/System pass automatic observations, exact groups, retained selections/results, navigation, direct actions and Undo with an injected fixture mover.
- Actual root/mixed-owner native Trash remains unverified because noninteractive administrator authority is unavailable; the ordinary-rights policy and current-user/immutable fixture evidence are recorded in Safety.md. Asset catalogs remain a tested generic fallback. Full manual keyboard traversal/VoiceOver and macOS 26-specific integration are not claimed.

- Native Stop/Undo regressions pass Light/Dark with durable partial sessions, direct Undo, restored fixtures and monitoring/menu continuity. Strict deep app-signature verification, shell syntax and diff/link checks pass. `Scripts/preview.sh` still fails its known stale 38×38 `overview.png` dimension assertion; it is not passing visual evidence. Full-size native application captures supply the inspected Light/Dark evidence. No real Trash or personal-data cleanup ran.
- Final reference comparison repeated ApplicationsModule progress, related-data discovery and failed-removal resources from the read-only CleanMyMac 5.7.2 image, then ejected it. Reference runtime and native-rights equivalence remain unverified. Task 061 is next; this task adds no release/version change.
