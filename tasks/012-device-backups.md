# 012 — Inspect and review local iPhone and iPad backups

Status: Done — inspection-only capability; direct removal unsupported
Priority: P2  
Phase: A — More useful space recovery  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md)

## Why

Local device backups can account for substantial space, but they may be the only copy of important data. They need their own review context rather than a generic cache label.

## Scope

- Discover supported local backup locations using bounded, documented metadata checks. Show device name when available, backup date, logical size, completeness/read status, and multiple backups without exposing unnecessary identifiers.
- Treat backups as user data requiring review. Age, encryption, and an absent device are information, not proof that a backup is expendable.
- Build backup-specific validation for any removal path, including active backup/restore activity and unsupported metadata states. Unknown activity or identity blocks mutation.
- Keep a whole backup as the review unit; never offer arbitrary internal chunks as cleanup. Preserve the current global Library protection and use a narrowly verified policy rather than a broad authorization exception.
- Add reviewed Trash and Activity recovery only for backup formats/activity checks proven supportable. Unsupported backups remain inspection-only with a useful Finder handoff.

## Acceptance criteria

- [x] Supported metadata fixtures show accurate device/date/size information; corrupt or partial backups are distinguished from empty ones.
- [x] No backup is selected automatically or classified as an ordinary generated cache.
- [x] Active or unknown backup activity, changed metadata, links, and unrecognized formats prevent removal.
- **Conditional capability not supported:** Supported fixture moves and Restore must preserve the complete backup structure and refuse occupied destinations. No format/activity pair passed the removal capability gate, so no in-app move/Restore path is exposed or claimed as validated. The scope explicitly calls for inspection-only behavior in this case.

## Validation

Use synthetic backup structures and injected activity providers, including encrypted/partial metadata, multiple devices, denied reads, and interrupted operations. Do not inspect backup contents beyond required metadata or exercise removal against real backups.

## Starting points

[Filesystem.swift](../Sources/LumaCore/Filesystem.swift), [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift), [CleanupJournal.swift](../Sources/LumaCore/CleanupJournal.swift), and task 004's inspection UI. Spec: sections 19, 80–83, and 91 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: inspect backup grouping, metadata, consequences, and unsupported states in the reference where accessible. Record the limits and decisions in [reference-checks.md](reference-checks.md).


## Capability assessment — 2026-10-18

Apple documents the standard MobileSync location and Finder's Manage Backups flow. Upstream backup readers/writers establish the observed summary keys, versions, encryption and snapshot marker, but do not provide a supported macOS-wide idleness guarantee for Luma. A current upstream writer initializes a finished snapshot marker before requesting the backup transfer. Process-name absence, metadata stability and a finished marker cannot independently authorize removal.

The task's explicit unsupported-format/activity branch therefore applies to **all direct in-app removal**. Supported scope is read-only metadata/size inspection and Finder management guidance. There is no supported format/activity pair for Trash/Restore and no fixture-only deletion bypass. This is a documented capability outcome, not a claim that unperformed removal/Restore checks passed. The conditional move/Restore acceptance criterion is inapplicable until a separate removal capability is independently established.

## Implementation and evidence

- Added Backups and an explicit standard-location inspection action, separate from Clean/automatic Overview. Each backup folder stays one personal-data record. Recorded device name/date/encryption, logical size and separate reported-finished/incomplete/corrupt/empty/unreadable/changed/ignored states remain visible without serial/IMEI/UDID/raw-directory identifiers in normal presentation. Same-name devices are not merged or declared to have a latest usable backup.
- Only Info.plist, Manifest.plist and Status.plist are read in bounded recognized layouts. Their identities and content hashes are rechecked after metadata-only tree sizing. Manifest.db and payloads are never opened for content. Missing/denied/provider/linked/ignored/cross-owner/volume/limit states remain explicit, with unknown sizes. Root discovery is capped at 100 entries; sizing has a shared 200,000-entry/64-level budget and summary plists a 1 MiB limit.
- Finished/encrypted/old/absent-device information grants no cleanup authority. Activity observations have only tools-detected/unknown states, with no idle override. No CleanupItem, selection, Trash or Restore path exists for this inspector. SafetyEngine explicitly rejects the standard backup subtree and backup namespace, retaining global Library protection. Finder actions are deliberate and outside Luma's Activity/Undo.
- Fourteen synthetic fixture tests cover multiple devices and encryption; accurate name/date/size; absent/empty/partial/corrupt/unrecognized metadata; missing manifest databases; metadata bounds/types; exact summary-only read observation; denied capabilities; provider/links/hardlinks; ignores; metadata changes during sizing; identifier minimization; active/unknown injected activity; bounds/cancellation/ScanEngine integration; and forged whole-backup/internal-file rules. Failed plans produce no moved records or pending intents and leave complete fixture structures intact. No real backup contents are inspected or removed.
- Native light/dark QA injects a synthetic MobileSync home through the existing scan-runner seam. It verifies five records spanning finished/plain/encrypted/incomplete/corrupt/empty metadata, recorded names/dates, personal-data classification, no cleanup candidates/selection/review, unknown activity, unchanged fixture identity and monitoring continuity. No actual backup, Finder/device action or mutation is used. Saved Activity/history and ignore/appearance/menu preferences retain their pre-check hashes.
- Reference checkpoints use only read-only CleanMyMac 5.7.2 resources from protoypeopensourcemac.dmg: backup grouping/older-backup wording and latest-backup warnings before implementation, during the working flow and at completion. Such resources do not establish reference runtime grouping, format validation or activity/restore safety. Luma does not adopt a promise that old backups are disposable. No reference executable, helper, cleanup or proprietary resources/code are used.

Final validation: **220 Swift tests in 20 suites** pass, including all 14 new synthetic-backup tests. Native light/dark backup checks and **72 navigation/layout samples across twelve pages** pass with unchanged synthetic trees, no real-backup access/actions, menu/monitor continuity and no selection/mutation. Debug/release apps build and strict local signature verification passes. Own light/dark captures were inspected; record details below the first card require scrolling, and these checks do not establish a full keyboard/VoiceOver session or exercise Finder/device management. Existing user data/preferences remain unchanged. The reference image is ejected; temporary fixtures/reports/captures/hashes are not committed.
