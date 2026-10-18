# Build and distribution details

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

The current development version remains 0.2.0 while task 007 is in progress. Passing automated checks and creating a local installer do not establish the pending manual keyboard/VoiceOver, system accommodation, composited-appearance or reference-interaction review. Update the version/build and installer heading together only after those gates are reviewed; then verify the tag-triggered public download against its published checksum.
