# 009 — Prepare a personal Homebrew tap

Status: Backlog; preparation can start before 0.3.0  
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

- [ ] Cask metadata matches an actual published DMG, its checksum, architecture, and deployment target.
- [ ] The documented install command works on the tested setup, and launch/security behavior is recorded accurately.
- [ ] Upgrade and uninstall preserve user data and Activity history by default; the app's menu process is handled cleanly during replacement/removal.
- [ ] A release with missing or mismatched assets cannot update the tap.
- [ ] Installation does not strip quarantine, change system security settings, or require enrollment as a preparation step.
- [ ] Public installation instructions are added only after the tap exists and the documented flow has been tested.

## Validation and references

Use the current Homebrew style/audit checks and a disposable installation target. Recheck official behavior at implementation time. The current planning review was on 2026-10-17: [tap creation and maintenance](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [tap trust](https://docs.brew.sh/Tap-Trust), and [official cask eligibility](https://docs.brew.sh/Acceptable-Casks). Official macOS casks must pass Homebrew's Gatekeeper checks under that policy; a personal tap is a separate distribution route.

## Starting points

[release.yml](../.github/workflows/release.yml), [package-dmg.sh](../Scripts/package-dmg.sh), [build-app.sh](../Scripts/build-app.sh), [Distribution.md](../Documentation/Distribution.md), and [README.md](../README.md).

Spec: section 100 in the [product specification](../Documentation/Product-Spec.md), adjusted to the user's current decision to continue free development distribution.

Reference checkpoints: inspect the Downloads reference image's installer contents as a packaging comparison, then inspect the actual published Luma DMG and installed app. Record these separately in [reference-checks.md](reference-checks.md).

