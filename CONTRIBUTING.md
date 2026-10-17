# Contributing to Luma

Use the complete spec in `Documentation/Product-Spec.md` and the status in `Documentation/Roadmap.md`. Build with Swift 6.2+ and a macOS 26+ SDK.

Run `bash Scripts/test.sh` before submitting changes. Add regression fixtures for new filesystem behavior. Never test cleanup against real user data. Use `bash Scripts/preview.sh` to inspect the native interface in both appearances.

Generated-data rules belong in `Sources/LumaCore/Rules.swift`; explicit named leftover mappings belong in `Sources/LumaCore/LeftoverScanner.swift` until the planned external rule loader is implemented. Each rule must have an exact bounded path, stable identifier, category, explanation, removal consequences, and owning app identifier when known. Do not use unrestricted globs or infer that old personal files are junk.

No scanner may mutate the filesystem. All cleanup passes through the central Safety Engine and CleanupJournal, which records each operation before moving anything to Trash. Restore must use the journal's verified recovery path. New paths must include rejection tests for protected folders, symlink escapes, stale identities, and ignore rules. Never add a permanent-delete fallback to make a failing operation succeed.

Keep third-party dependencies small and behind project-owned interfaces. Follow the approved dependency philosophy in the canonical spec. Native Apple APIs are preferred. Formatting should stay consistent with existing Swift; SwiftFormat integration is planned before broad community contributions.

Use original assets and compatible source licenses. The project is licensed GPL-3.0-or-later.
