# 060 — Correct app inventory, icons and uninstall eligibility

Status: Planned

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

- [ ] Supported two-component IDs uninstall bundle-only when related matching is unavailable; protected/unverifiable/provider cases remain blocked accurately.
- [ ] Unsafe optional roots stay intact without blocking the safe bundle. Captured-target changes, ignored descendants and partial outcomes remain protected without automatic retries.
- [ ] Unrelated denied helpers do not block the chosen app when its required evidence is complete; denied/active/unknown chosen helpers do. Matching embedded owners beneath differently identified apps are not lost.
- [ ] Direct-root/vendor-subfolder membership and action eligibility stay consistent across Residues, refresh and Restore. Companion filtering preserves independent utilities and ownership detection.
- [ ] Icons survive metadata merges and Undo/Restore. Loose-resource/key-precedence and supported asset cases are covered; unsupported/provider resources fall back without downloads.
- [ ] Root/mixed-owner behavior has a documented supported/unsupported decision and disposable-fixture evidence, without general privilege relaxation.

## Validation

Extend existing uninstall, inventory/icon and native application checkers. Generated fixtures cover two-/three-component IDs, same-ID copies, protected identifiers, optional-root denial/links/ignores, unrelated versus chosen denied helpers, a matching embedded owner under a differently identified app, vendor subfolders, companion associations, ICNS/PNG, both icon keys, asset-only support/fallback and Restore. Retain central safety regressions.

Inspect direct actions, reasons, logos, keyboard access and narrow layout in Light/Dark/System on native Apple Silicon. Ordinary workflow checks use disposable apps and injected movers. Where available, test normal native Trash rights on generated root/mixed-owner bundles; record unavailable authority instead of bypassing permissions or testing personal apps. Verify public icon APIs and no-materialization separately from screenshots. Source review is not native acceptance.

## Source evidence — c03e185

- Eligibility/optional-data blockers: [ApplicationActions.swift](../Sources/LumaApp/ApplicationActions.swift), [ApplicationRelationships.swift](../Sources/LumaCore/ApplicationRelationships.swift), [ApplicationUninstall.swift](../Sources/LumaCore/ApplicationUninstall.swift).
- Unrelated helper traversal: [LeftoverScanner.swift](../Sources/LumaCore/LeftoverScanner.swift), [CleanupPlan.swift](../Sources/LumaCore/CleanupPlan.swift).
- Divergent inventory, mutation scope and ownership restrictions: [Scanners.swift](../Sources/LumaCore/Scanners.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [Filesystem.swift](../Sources/LumaCore/Filesystem.swift).
- Icon loss/key handling: [Scanners.swift](../Sources/LumaCore/Scanners.swift), [ApplicationIcon.swift](../Sources/LumaCore/ApplicationIcon.swift), [ApplicationIconView.swift](../Sources/LumaApp/ApplicationIconView.swift). Verify semantics against Apple's [Core Foundation keys reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

Follow [README](README.md) for reference comparisons/evidence. Creating this task claims no implementation or native validation.
