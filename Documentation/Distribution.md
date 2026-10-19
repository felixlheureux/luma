# Build and distribution details

The only supported target is native Apple Silicon (`arm64`) on macOS 26+, with M2 as reference hardware. Do not add Intel/x86_64 artifacts, universal builds, Rosetta compatibility or Intel test/release gates. Generic toolchain behavior does not imply project support for another architecture.

Development builds and CI releases require no paid Apple membership. The default build script uses ad-hoc signing (`codesign --sign -`). These builds are not notarized, and Gatekeeper can restrict downloaded apps. Luma does not alter quarantine attributes or system security settings.

The Release workflow builds for Apple Silicon on macOS 26, verifies the local signature, packages and checks the DMG, and publishes a development prerelease when a matching version tag is pushed. A manual workflow run produces artifacts without publication. `SHA256SUMS` identifies the exact downloadable installer.

If a Developer ID Application certificate is available in the build machine's keychain later, the build script can use it with hardened runtime and a timestamp:

```sh
LUMA_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash Scripts/build-app.sh release
```

Developer ID distribution and notarization require Apple enrollment and credentials. They are optional future setup; no certificate or Apple account is needed for current development releases. CI does not currently import credentials or submit builds to Apple's notary service. Enable and test that flow when the required account becomes available.

## Updating icons

All native marks and exported assets derive from `Sources/LumaApp/Brand.swift`. Regenerate the app icon and README SVG with:

```sh
bash Scripts/make-icon.sh
```

Do not independently rotate an SF Symbol for the menu bar: the icon's filled segment has its own vector edge, shared with the Dock icon and in-app mark.

## Cleanup rule references

- [Chromium: user data and cache directories](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
- [Mozilla: local profile cache directories](https://github.com/mozilla-firefox/firefox/blob/main/toolkit/xre/nsXREDirProvider.cpp)
- [npm: cache design and `_cacache`](https://docs.npmjs.com/cli/cache/)
- [Yarn Classic: global package cache](https://classic.yarnpkg.com/lang/en/docs/cli/cache/)
- [pnpm: store pruning and referenced packages](https://pnpm.io/cli/store)

The scanner uses supported default locations only. Custom browser profile paths and package-manager cache overrides are not followed automatically. Modern Yarn project caches, pnpm stores and global virtual stores, simulator devices, and installed runtimes are excluded. Simulator rules cover only user-owned cache and log locations and require idle tools before cleanup.

## Installer payload verification

After a release build and packaging, run `bash Scripts/verify-dmg.sh dist/Luma-0.2.0-arm64.dmg` using the actual version/architecture filename. This mounts the image read-only, checks its app metadata against source, compares the executable with the built app and the icon/license/readme with their source files, verifies the Applications shortcut and mounted signature, then ejects it. The Release workflow runs the same check before checksumming/uploading. Packaging uses a fresh temporary staging folder so files from earlier installers cannot survive into a new payload.

The current development version remains 0.2.0 after task 007’s user-directed closure with manual release checks deferred. Passing automated checks and creating a local installer do not establish the pending manual keyboard/VoiceOver, system accommodation, composited-appearance or reference-interaction review. Update the version/build and installer heading together only after those gates are reviewed; then verify the tag-triggered public download against its published checksum.

The app now includes `Luma_LumaCore.bundle/CleanupRules.yaml` (under the bundle's platform resource layout) and `Third-Party-Notices.txt`. The build copies both before signing. Installer verification compares the catalog and notices with source as well as the executable/icon/version. Do not distribute a bare executable without its package resource bundle; a missing or invalid catalog blocks scans and cleanup with an explicit error.

## Personal Homebrew tap (task 009)

The package token is `luma`; the app stays Luma. The public [Luma tap](https://github.com/felixlheureux/homebrew-luma) installs with:

```sh
brew install --cask felixlheureux/luma/luma
```

This exact command was verified from the public GitHub repository with Homebrew 7.0.9 on Apple Silicon/macOS 27.0.1, using a disposable app directory and fresh trust configuration. Homebrew automatically trusted this cask only. Source files are in `Distribution/Homebrew`, with a cask, a tap CI template and an exact prerelease-channel declaration.

The cask pins the published 0.2.0 arm64 DMG, not a local development rebuild with the same filename/version. That published build predates current main-branch safety/UI/catalog work. Its declared and Mach-O minimum is macOS 26.0. Local Homebrew 7.0.9 style and online audit pass with the exact 0.2.0 prerelease declaration. This is a personal development channel; no signing/security exceptions are configured and official homebrew/cask submission remains separate.

A disposable app-directory test installs published 0.1.2 and upgrades to published 0.2.0. Activity/history, ignore list and appearance/menu preferences remain unchanged. The cask has a plain app artifact and `uninstall quit: "app.luma.mac"`, with no zap/data-removal script. A synthetic matching-ID menu process tests normal Quit separately because the real build’s first launch was not established. On the tested Apple Silicon Mac running macOS 27.0.1, quarantine is preserved and Gatekeeper assessment rejects this ad-hoc build. Launch Services accepting an open request does not establish successful launch. The tap does not change that decision or promise a notarized app.

After a release is published, prepare a reviewed update from the repository root:

```sh
python3 Scripts/prepare_homebrew.py --tag v0.2.0 --output /path/to/homebrew-luma/Casks/luma.rb
python3 -m unittest discover -s Scripts -p test_homebrew.py
```

Replace the example tag with the exact newly published release. The helper downloads its real DMG/checksum, verifies GitHub digests and size, mounts the image read-only, checks app identity/version/icon/signature and both architecture/deployment declarations, ejects it, and confirms the release assets did not change. Failure leaves the previous cask intact. It does not publish a release or update a remote tap. The supported minimum is currently 26.0; changed architectures/deployment requirements stop generation for explicit review.

For a prerelease, review/update the tap’s exact version in `audit_exceptions/github_prerelease_allowlist.json`; remove that declaration when adopting a stable release. This declares the channel rather than bypassing signing checks. Run full Homebrew style/online audit and disposable install/upgrade/removal tests before committing/pushing the tap. The main Release workflow uploads a cask proposal only after publishing succeeds; the **Prepare Homebrew proposal** manual workflow can also verify any already-published tag. These create review artifacts without a cross-repository write token.

Current Homebrew 6+ trust behavior supports trust scoped to one fully qualified cask; whole-tap trust is unnecessary. See [tap trust](https://docs.brew.sh/Tap-Trust), [tap maintenance](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), and [official cask eligibility](https://docs.brew.sh/Acceptable-Casks). The public-route install, style, full online audit and uninstall pass; saved Luma data and quarantine remain intact.
