# Safety model and current limits

Scanners produce immutable candidates; they cannot delete files. Each candidate contains its path, logical size, classification, scanner rule, ownership evidence, consequence, scan time, and a filesystem identity and metadata-tree digest.

The UI starts with no selections. A review sheet lists the exact paths and removal consequences, and requires explicit acknowledgement. A central Safety Engine preflights the complete selection, then revalidates each item immediately before recording an intent in the cleanup journal and calling Apple’s `FileManager.trashItem(at:resultingItemURL:)`. There is no permanent-delete fallback.

## Validation

- Strict path-component boundaries; prefix collisions do not pass.
- Protected system locations and whole user folders cannot be removed.
- Generated data must match one of 18 project-owned rules. Profile-based rules accept only supported local profile names and exact cache leaves. Rule ownership and classification cannot be overridden by a candidate.
- Application relationships must use exact bundle identifiers in approved locations.
- Potential leftovers must have exact reverse-DNS identifiers in approved user Library locations. Installed apps and embedded helpers are indexed, and Launch Services checks owners outside those folders. Ownership is checked again before Trash; reinstalling an app invalidates its old leftover selections. Containers require matching owner metadata. Named support folders require an explicit project-owned mapping to a bundle identifier.
- Apple system applications and Luma itself are protected.
- Manual personal-file actions require an explicitly chosen folder inside the user’s home directory.
- Symlinks and aliases in a candidate’s path are rejected.
- A directory containing a symbolic link is excluded, except internal framework links within a valid application bundle. Those links are fingerprinted and never traversed; external targets are rejected.
- File identity, device, ownership, modification time, size, and descendant metadata are rechecked. Results over 30 minutes old are rejected.
- Ignore rules override suggestions, including descendants of an ignored folder.
- A known running owning app blocks cleanup of its data. Package caches and developer data also check for active package managers and builds. Simulator cleanup requires a successful check that no devices are booted; an unknown state blocks cleanup. System-critical processes are not offered a Quit action.
- Duplicate selection must retain at least one file in every verified group.
- Cancellation discards the current scanner’s unfinished results.

## Meaning of totals

Sizes are logical bytes, not guaranteed reclaimed physical space. Hard-linked files are counted once within a tree and duplicate scan; APFS clones, compression, snapshots, and files shared between separate trees may affect actual savings. Available storage is macOS’s capacity for important usage and can include purgeable space. Moving files to Trash does not itself reclaim all their space.

Unreadable paths, links, and directories over the 250,000-entry per-item inspection limit are skipped with visible coverage notices. Duplicate scans are limited to 100,000 entries and exclude packages, hidden files, ubiquitous/cloud items, and different devices. External-volume cleanup is currently blocked. Some system-installed application bundles cannot be uninstalled because they are not owned by the current user.

## Early-build limitations

Path revalidation reduces ordinary stale-scan mistakes; it is not yet a complete defense against a hostile process racing the final pathname-based Trash call. Metadata fingerprints are not content hashes for ordinary cleanup. Other processes can restart after an activity check. Process detection covers known executable and script names; custom wrappers can evade it. Quit owners and stop builds before cleaning.

Multi-item cleanup is not a filesystem transaction. An error stops further moves; earlier successes remain in Activity and Trash. Every Trash or Restore operation persists an intent before filesystem mutation. The journal uses an exclusive operation lock, a private temporary file, file synchronization, and an atomic rename; completed history and removal of the intent are committed together. A later launch reconciles interrupted operations using device, inode, metadata, and location-independent tree fingerprints. It does not retry cleanup automatically. Unknown or ambiguous moves stay visible in Activity and pause further cleanup until reviewed.

macOS can allow moving an item to Trash while restricting direct Trash access. The journal preserves the location returned by macOS and the item's pre-move identity. Interrupted moves with unknown destinations require readable Trash metadata for reconciliation. Acknowledging an unresolved entry dismisses that intent without touching files.

Restore checks the saved identity against the current Trash item, rejects links, verifies the original parent and volume, and uses FileManager's non-overwriting move. Changed or replaced items are left for Finder review. Legacy history remains readable, but entries without an identity must be restored in Finder. The app never empties Trash automatically.

The journal's file synchronization and atomic replacement protect against process interruption. Recovery after an operating-system or storage failure still depends on filesystem guarantees. Pathname validation is not a complete defense against a malicious process racing the final move. Ordinary cleanup fingerprints contain metadata, not file-content hashes.

These limits are release-hardening work. Treat 0.1 as an inspectable development build, not a production-hardened maintenance utility.

## Platform references

- [Apple: FileManager Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [Apple: applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
