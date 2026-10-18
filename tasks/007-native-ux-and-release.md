# 007 — Review native UX and ship 0.3.0

Status: Closed at user request (release verification deferred)
Priority: P1  
Milestone: 0.3.0  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [005](005-application-footprints.md), [006](006-application-reset.md), [047](047-provider-aware-filesystem.md), [048](048-cleanup-session-undo.md), [050](050-expanded-cache-discovery.md)

## Why

The next features need to feel like one native app. Previous feedback makes the regression targets concrete: sidebar smoothness, full-row Settings clicks, content alignment, dark-mode contrast, accurate monitoring, and a consistent menu icon.

## Scope

- Include task 050's new cache families, expandable details, coverage and active-owner states in the fixture/native release matrix.
- Review Overview, Clean, Storage, Applications, reset, Duplicates, Activity, Settings, and the menu companion in light, dark, and System appearance.
- Check keyboard-only operation and VoiceOver through scan, cancellation, selection, review, failure, recovery, and Restore. Verify Increase Contrast, Reduce Transparency, and Reduce Motion behavior.
- Preserve the deeper purple controls with white labels, shared logo geometry, established top-bar spacing, consistent empty-state alignment, and complete row/button hit targets.
- Profile sidebar transitions, large result lists, storage navigation, and monitoring during a fixture scan. Fix measured layout or main-thread stalls and document before/after evidence rather than adding decorative animations.
- Verify that CPU/memory labels retain their actual meaning, pressure is separate from usage, and helper processes remain grouped under their owning app.
- Update feature coverage and remaining limits in the README, roadmap, and safety document. Update app/installer versions together only when preparing the release.
- Run existing CI/release checks, package the final installer, inspect its payload, and verify the public DMG checksum after the tag-triggered release succeeds.

## Acceptance criteria

- [ ] All new workflows are usable with keyboard and VoiceOver, with accessible alternatives to the treemap.
- [ ] No known regression remains in the previously corrected appearance, layout, click targets, menu icon, or menu lifetime behavior.
- [ ] Loading, empty, partial, error, cancellation, completed, and recovery states have concrete review evidence.
- [ ] Provider-managed/unknown targets remain outside ordinary mutation, and cleanup Stop/session Undo handle partial operations accurately after restart.
- [ ] Large-list and scan interaction traces are recorded; reported stalls are resolved or specifically documented before deciding release scope.
- [ ] All preceding milestone tasks meet their acceptance criteria and current relevant checks pass. The baseline is 60 Swift tests plus 4 release-validation tests; update the count from actual results.
- [ ] The published 0.3.0 DMG contains the final app/version/icon, and its downloaded checksum matches the published checksum file.

## Validation

Run `bash Scripts/test.sh`, Python release-validation tests, appropriate workflow validation, the release build/signature check, and `bash Scripts/check-window-lifecycle.sh`. Use native captures/manual inspection for glass and accessibility states; the existing fallback snapshots cannot prove all composited layers look correct. Inspect the packaged app as well as the development bundle. Use disposable fixtures for every mutation.

## Starting points

[Design.swift](../Sources/LumaApp/Design.swift), [RootView.swift](../Sources/LumaApp/RootView.swift), [Brand.swift](../Sources/LumaApp/Brand.swift), [MenuCompanion.swift](../Sources/LumaApp/MenuCompanion.swift), [StatusBarController.swift](../Sources/LumaApp/StatusBarController.swift), [Scripts](../Scripts), and [release.yml](../.github/workflows/release.yml).

Spec: sections 70, 90, 94–100, and 106.6 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: repeat the relevant reference-DMG comparisons across the whole milestone, including details and recovery states. Inspect the final Luma DMG separately. Complete [reference-checks.md](reference-checks.md) before marking this task done.


## 2026-10-18 implementation and review evidence

Implemented the automated review/release-preparation slice against baseline `95ddb78`:

- Custom surfaces use opaque fills for Reduce Transparency or increased contrast and stronger outlines for increased contrast. Ambient decorative gradients disappear with Reduce Transparency. Native materials keep their platform behavior.
- Item detail expansion and storage detail scrolling honor Reduce Motion. Search, scan coverage and item-consequence buttons have explicit accessible names; icon detail controls have 28-point hit targets. Section/page headings expose heading traits and System graphs identify CPU versus memory history.
- `bash Scripts/check-native-ux.sh` visits nine pages across Light/Dark/System and standard/high-contrast window appearances. All 54 layout samples pass with continued monitoring/menu and no selected files or mutations. The longest final sample is 0.084 seconds, **including** a requested 20 ms yield. This is a lightweight layout smoke measurement, not a frame trace or a large-result benchmark. Initial checker teardown trapped after writing its report; keeping the original scene content fixed the checker, and the final rerun exits normally.
- 168 Swift tests in 16 suites and four Python release-validation tests pass. Shell syntax and CI/release YAML syntax checks pass. Full actionlint validation was unavailable locally.
- Native light/dark scan, cleanup Stop/session Undo, storage and application footprint/reset regressions pass. Scan inventory: 6,000 files in 0.950/0.961 seconds; maximum sampled main-actor delay 0.072/0.085 seconds. Storage: 1,030 nodes in 1.639/1.620 seconds. Lifecycle verifies window closing/reopening, menu visibility, monitoring and explicit Quit.
- Packaging uses fresh temporary staging. `Scripts/verify-dmg.sh`, also invoked by Release CI, mounts the installer read-only and checks app metadata, executable, shared icon, licenses, installer text, Applications shortcut and signature against the current build/source before ejecting it.

Deferred release gates (task closed by user request; version stays **0.2.0**):

- Perform a complete keyboard-only and VoiceOver session through scan/cancel, selection, confirmation, failure, partial cleanup, restart recovery and Restore/Undo. The fixture reset focus check is narrower than this gate.
- Review Settings and the menu companion, all sheets and below-fold content in System/Light/Dark, with actual Increase Contrast, Reduce Transparency and Reduce Motion settings. The checker records the current system flags (both reduction flags were false); high-contrast window appearances do not prove system-preference behavior. Own-window fallback captures omit native/layer-backed button fills and toolbar content, so full glass composition/contrast remains unverified.
- Record large-list, sidebar, storage and scan interaction traces with a suitable profiler and assess any stalls. Current sampled timings and cached-navigation fixtures are useful evidence but do not close that requirement.
- Complete the interactive reference comparison. Available reference evidence remains metadata/localization only; no visual or end-to-end reference workflow is claimed.
- After those reviews pass, update app version/build and installer heading together, publish the tag-triggered 0.3.0 prerelease, download its public DMG/checksum, and verify them. A locally verified 0.2.0 development installer does not satisfy the published 0.3.0 criterion.

Final local packaging evidence: the release configuration builds and its strict signature passes. The generated 0.2.0 arm64 DMG passes image integrity, read-only mounted payload/signature verification and SHA-256 round-trip checking. Its reference image and installer mount are ejected. Generated installer/checksum files remain untracked under `dist/`.

## User-directed closeout — 2026-10-18

Closed at the user’s explicit request to move to the next task. The implemented accessibility and release tooling is committed as `ea11b37`; the automated checks above passed. Unchecked acceptance criteria remain unverified, not passed. The deferred gates above remain prerequisites for claiming a fully reviewed 0.3.0 release. No 0.3.0 tag or public release was created by this closeout. Task 008 may proceed because its actual dependencies (001 and 005) are complete.
