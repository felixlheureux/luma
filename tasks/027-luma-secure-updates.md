# 027 — Add signed in-app updates when credentials are available

Status: Deferred — Apple distribution credentials are not currently available  
Priority: P3  
Phase: Conditional distribution work  
Depends on: [007](007-native-ux-and-release.md), [009](009-homebrew-distribution.md)

## Why

Luma should eventually offer a secure Check for Updates flow. The user has explicitly chosen to continue without paid Apple enrollment for now, so this task must not block free development, GitHub releases, Homebrew preparation, or unrelated features.

## Scope

- Revisit this task when the required credentials become available through a future user decision. Do not repeatedly request enrollment or credentials during other tasks.
- Integrate Sparkle 2 behind a project-owned update service, following the canonical spec rather than building a custom updater. Recheck maintenance, license, packaging, and platform requirements at implementation time.
- Add opt-in signing/notarization to CI with secure credential handling and no secrets in source, artifacts, or logs. Preserve the default credential-free development build.
- Publish cryptographically verified update metadata and artifacts, with explicit stable/development channel policy and release version consistency.
- Handle interrupted downloads, verification failures, installation/relaunch errors, app state, and menu-process lifecycle. Never install a failed or unauthenticated update or silently downgrade channels.

## Acceptance criteria

- [ ] Credential-free development and existing release paths continue to work independently.
- [ ] Tampered artifacts, invalid signatures, incompatible builds, and channel mistakes cannot be installed through the updater.
- [ ] A supported upgrade preserves preferences, ignore rules, journal history, and unresolved recovery state.
- [ ] Update failures leave a launchable app with an accurate recovery path, and all feed/artifact signatures are verified end to end.

## Validation

Use a local test feed and disposable app copies for valid/invalid signatures, interrupted downloads, channels, version ordering, and restart. When credentials exist, verify the actual downloaded distribution and update path on a suitable clean setup. No credentials are needed to finish the earlier queue.

## Starting points

[Distribution.md](../Documentation/Distribution.md), [build-app.sh](../Scripts/build-app.sh), [release.yml](../.github/workflows/release.yml), [LumaApp.swift](../Sources/LumaApp/LumaApp.swift), and [Package.swift](../Package.swift). Spec: sections 100 and 106.2 in the [product specification](../Documentation/Product-Spec.md), subject to the user's current distribution constraint.

Reference checkpoints: compare update preferences, channel presentation, app/menu restart, and failed-update recovery where observable without changing the reference installation. Record in [reference-checks.md](reference-checks.md).

