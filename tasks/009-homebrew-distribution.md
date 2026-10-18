# 009 — Prepare a personal Homebrew tap

Status: Prepared; public tap publication awaits explicit approval
Priority: P2  
Milestone: Distribution follow-up  
Depends on: [007](007-native-ux-and-release.md) for the intended release artifact

## Why

The user wants Homebrew distribution and currently has no paid Apple Developer membership. Plan a personal tap around published development releases, with an honest installation test and no paid-account prerequisite for preparing the package.

## Scope

- Prepare a cask in a personal `homebrew-...` repository using an available, unambiguous name. Do not assume the short token `luma` is unclaimed; verify naming when implementing.
- Pin a real GitHub release URL, version, and SHA-256 from its published asset. Declare the actual Apple Silicon and minimum macOS requirements rather than advertising unbuilt architectures.
- Use a plain app artifact. Preserve Homebrew/macOS security checks and the user's existing preferences, journal, and ignore list. Uninstall should remove the app; optional data removal must be deliberate and narrowly scoped.
- Validate cask style, audit, download, installation, launch, upgrade, and uninstall on a suitable disposable setup. Record the actual behavior of the downloaded build. Do not promise that a tap changes Gatekeeper's launch decision.
- Document the fully qualified installation path and any trust step required by the tested Homebrew version, linking to official documentation. Keep technical distribution details in the existing developer documentation and normal public wording as development builds.
- Prepare a release-to-cask update flow that changes version/checksum only after the GitHub release and assets verify successfully. Start with a reviewable update rather than a cross-repository write token if it is unnecessary.
- Treat official `homebrew/cask` submission as a separate future eligibility review. A personal tap does not imply official acceptance. In-app Sparkle updates and Apple credentials remain separate future work.

## Acceptance criteria

- [x] Cask metadata matches an actual published DMG, its checksum, architecture, and deployment target.
- [ ] The documented install command works on the tested setup, and launch/security behavior is recorded accurately.
- [ ] Upgrade and uninstall preserve user data and Activity history by default; the app's menu process is handled cleanly during replacement/removal.
- [x] A release with missing or mismatched assets cannot update the tap.
- [x] Installation does not strip quarantine, change system security settings, or require enrollment as a preparation step.
- [ ] Public installation instructions are added only after the tap exists and the documented flow has been tested.

## Validation and references

Use the current Homebrew style/audit checks and a disposable installation target. Recheck official behavior at implementation time. The current planning review was on 2026-10-17: [tap creation and maintenance](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [tap trust](https://docs.brew.sh/Tap-Trust), and [official cask eligibility](https://docs.brew.sh/Acceptable-Casks). Official macOS casks must pass Homebrew's Gatekeeper checks under that policy; a personal tap is a separate distribution route.

## Starting points

[release.yml](../.github/workflows/release.yml), [package-dmg.sh](../Scripts/package-dmg.sh), [build-app.sh](../Scripts/build-app.sh), [Distribution.md](../Documentation/Distribution.md), and [README.md](../README.md).

Spec: section 100 in the [product specification](../Documentation/Product-Spec.md), adjusted to the user's current decision to continue free development distribution.

Reference checkpoints: inspect the Downloads reference image's installer contents as a packaging comparison, then inspect the actual published Luma DMG and installed app. Record these separately in [reference-checks.md](reference-checks.md).


## 2026-10-18 implementation and evidence

- The user requested a clean package name, without an account-name prefix. Homebrew 7.0.9 search returned no exact `luma` package, and the official `Casks/l/luma.rb` API returned 404. The prepared token is **luma**, app **Luma.app**, proposed repository **felixlheureux/homebrew-luma**. This checks the current official index, not every independent/private tap.
- The cask is prepared under `Distribution/Homebrew`, with a complete local Git tap at `/private/tmp/luma-homebrew-009`. It uses the actual published `v0.2.0` asset URL, SHA-256 `b5f4df979a02fb9fe0fe051608b4541145687e42659df8692bceb5765662f028`, Apple Silicon only, macOS Tahoe/26.0 minimum. The downloaded manifest and GitHub digest agree. Read-only image inspection verifies bundle identity/version, icon, local signature and both plist/Mach-O deployment targets. It intentionally uses the older published release, not an unreleased locally rebuilt file bearing the same version.
- `Scripts/prepare_homebrew.py` verifies one exact published non-draft tag, asset names/URLs/states/sizes, GitHub digests, downloaded SHA256SUMS, app identity/version/icon, arm64, macOS 26.0 and signature. It checks release/asset identity again after inspection, excluding mutable download counters. Only then does it atomically replace a proposed cask. It never executes the app, uploads assets or writes another repository. Missing, duplicated, corrupted, changed or incompatible assets leave the existing cask unchanged.
- Seven new Python tests cover positive preparation, missing/duplicate/unpublished assets, byte/manifest/digest corruption, payload rejection, asset changes, safe tag/render inputs and architecture/deployment mismatches. All 11 Python tests (including four release tests) pass. The existing 175 Swift tests in 17 suites pass. Workflow YAML syntax passes.
- Both main CI/release workflows run the new gate tests. A manual Homebrew-proposal workflow validates an existing published tag; the release workflow prepares a proposal only after publication succeeds. Both upload a reviewable cask artifact, with no cross-repository write token. Maintainers review the cask and exact prerelease allowlist before a tap update.
- Homebrew style passes. Full `brew audit --cask --online` passes for the local personal tap with the exact `github_prerelease_allowlist` entry `luma: 0.2.0`. The initial audit correctly identified the GitHub prerelease; declaring that reviewed channel resolved it. No signing/security audit exception, quarantine removal or system security change was used. Official homebrew/cask eligibility is a separate future review.
- Local install/upgrade: the verified published 0.1.2 cask installed into a temporary app directory and upgraded through Homebrew to verified 0.2.0. The installed plist versions match both phases. A separate 0.2.0 reinstall/removal exercises the app-only artifact. Existing Activity/history, ignore list and saved appearance/menu settings are checked by hashes without exposing their contents or changing them.
- Launch/security: the installed app retains `com.apple.quarantine`. On Apple Silicon/macOS 27.0.1, `spctl --assess --type execute` rejects it (exit 3). A normal Launch Services request returns 0 but produces no native lifecycle report, so successful first launch is **not** claimed. Quarantine and saved Luma data remain unchanged. No Gatekeeper approval or bypass was automated.
- The cask requests normal Quit by exact bundle ID and has no force signal, zap, deletion/trash hook, script or privileged helper. Because the published app’s launch was not established, a disposable menu-only app with the matching bundle ID tests Homebrew’s Quit directive independently; it never reads Luma user data. The retention/process evidence and its limits are separate from a successful real-release launch claim.
- A new public repository creation/push was attempted only after local style/audit validation, but automatic approval review rejected that action because explicit authorization for the exact public repository was required. No repository was created or publicly pushed. Source/tooling work continues in the existing Luma repository. Public installation instructions are withheld until approval, repository creation and the public-route test.

Remaining publication work: obtain explicit approval to create/publish `felixlheureux/homebrew-luma`; publish the prepared tap; test the fully qualified install route from that GitHub repository; then add its public install instructions and record the final tap commit/CI. Successful first launch without a user security decision remains unsupported for the current ad-hoc development release. Task 007’s closure did not publish 0.3.0.
