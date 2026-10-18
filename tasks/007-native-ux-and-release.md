# 007 — Review native UX and ship 0.3.0

Status: Planned; baseline review can start now  
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

