# Implementation roadmap

The owner reset scope on 2026-10-19 after reviewing the app. [Product-Spec.md](Product-Spec.md) is the current product boundary; [tasks/README.md](../tasks/README.md) is the only executable queue. The previous broad expansion plan and unstarted tasks were deleted.

## Current implementation

Main at `78acaf5` includes app inventory/footprints/reset, potential leftovers, verified cache rules, chosen-folder/project/Downloads review, storage hierarchy and volume inspection, exact duplicates, a local analysis cache, central cleanup plans/journal/recovery, and System/menu monitoring. These foundations are implemented. Task 054 adds automatic app inventory, direct row uninstall, compact Undo and safe mutation draining. Tasks 055–056 add automatic residues and requested Storage scans with direct in-view Trash/Undo. Task 057 adds read-only iCloud metadata with owner-reported manual acceptance. The focused menu and the small Maintenance action set remain in the queue.

Task records 001–006, 008–017, 047, 048 and 050 retain implementation evidence. Task 007 remains closed with manual release checks deferred. The published personal Homebrew tap pins the 0.2.0 development release; this reset does not claim a new released version.

## Core implementation

| Task | Result |
| --- | --- |
| [054](../tasks/054-direct-uninstall.md) | Implemented: direct app uninstall, compact stable feedback and Undo |
| [055](../tasks/055-residues.md) | Implemented: automatic saved residue observations, exact selectable groups and in-place Trash/Undo |
| [056](../tasks/056-storage-discovery.md) | Implemented: requested local discovery, saved Largest files/Explore browsing and direct selected-file Trash/Undo |
| [057](../tasks/057-icloud-discovery.md) | Implemented: read-only iCloud metadata browsing; owner reports manual integration acceptance |
| [058](../tasks/058-menu-panel.md) | Flat menu panel, focused and correctly colored from first open |
| [059](../tasks/059-maintenance.md) | Small approved cache/Trash actions and honest memory help |

The System view stays at its current scope. Reuse existing execution safeguards while changing the UX. Do not expand monitoring, privacy, photo/Mail tools, ecosystem coverage, scheduling, or distribution work.

There is no automatic next phase. Complete and demonstrate the core acceptance in the queue, then let the owner choose what comes next. Future release work uses the existing distribution process when requested; this plan adds no release or paid-credential gate.
