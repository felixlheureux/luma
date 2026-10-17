# Safety model and current limits

Scanners produce immutable candidates; they cannot delete files. Each candidate contains its path, logical size, classification, scanner rule, ownership evidence, consequence, scan time, and a filesystem identity and metadata-tree digest.

The UI starts with no selections. A review sheet lists the exact paths and removal consequences, and requires explicit acknowledgement. A central Safety Engine preflights the complete selection, then revalidates each item immediately before calling Apple’s `FileManager.trashItem(at:resultingItemURL:)`. There is no permanent-delete fallback.

## Validation

- Strict path-component boundaries; prefix collisions do not pass.
- Protected system locations and whole user folders cannot be removed.
- Generated data must match one of six exact project-owned rules.
- Application relationships must use exact bundle identifiers in approved locations.
- Potential leftovers must have exact reverse-DNS identifiers in approved user Library locations. Installed apps and embedded helpers are indexed, and Launch Services checks owners outside those folders. Ownership is checked again before Trash; reinstalling an app invalidates its old leftover selections. Containers require matching owner metadata. Named support folders require an explicit project-owned mapping to a bundle identifier.
- Apple system applications and Luma itself are protected.
- Manual personal-file actions require an explicitly chosen folder inside the user’s home directory.
- Symlinks and aliases in a candidate’s path are rejected.
- A directory containing a symbolic link is excluded, except internal framework links within a valid application bundle. Those links are fingerprinted and never traversed; external targets are rejected.
- File identity, device, ownership, modification time, size, and descendant metadata are rechecked. Results over 30 minutes old are rejected.
- Ignore rules override suggestions, including descendants of an ignored folder.
- A known running owning app blocks cleanup of its data. System-critical processes are not offered a Quit action.
- Duplicate selection must retain at least one file in every verified group.
- Cancellation discards the current scanner’s unfinished results.

## Meaning of totals

Sizes are logical bytes, not guaranteed reclaimed physical space. Hard-linked files are counted once within a tree and duplicate scan; APFS clones, compression, snapshots, and files shared between separate trees may affect actual savings. Available storage is macOS’s capacity for important usage and can include purgeable space. Moving files to Trash does not itself reclaim all their space.

Unreadable paths, links, and directories over the 250,000-entry per-item inspection limit are skipped with visible coverage notices. Duplicate scans are limited to 100,000 entries and exclude packages, hidden files, ubiquitous/cloud items, and different devices. External-volume cleanup is currently blocked. Some system-installed application bundles cannot be uninstalled because they are not owned by the current user.

## Early-build limitations

Path revalidation reduces ordinary stale-scan mistakes; it is not yet a complete defense against a hostile process racing the final pathname-based Trash call. Metadata fingerprints are not content hashes for ordinary cleanup. Other processes can restart after the running-app check, and package-manager activity is not currently detected. Quit owners and stop builds before cleaning.

Multi-item cleanup is not a filesystem transaction. An error stops further moves; earlier successes remain in Activity and Trash. History is atomically saved after each successful move, but a crash between the move and persistence can leave an unrecorded item in Trash. The next milestone introduces a pre-mutation journal and crash reconciliation.

Restore currently checks the Trash boundary, original parent path, and destination availability, then relies on FileManager’s non-overwriting move. It does not yet verify the trashed object against a stored identity; inspect Trash in Finder if its contents have changed. The app never empties Trash automatically.

These limits are release-hardening work. Treat 0.1 as an inspectable development build, not a production-hardened maintenance utility.

## Platform references

- [Apple: FileManager Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [Apple: applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
