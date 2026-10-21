# Implementation roadmap

The owner reset scope on 2026-10-19 after reviewing the app. [Product-Spec.md](Product-Spec.md) is the current product boundary; [tasks/README.md](../tasks/README.md) is the only executable queue. The previous broad expansion plan and unstarted tasks were deleted.

## Current implementation

Main at `c03e185` implements 054–057: automatic app inventory and direct row uninstall, compact Undo and safe mutation draining, automatic residue observations, requested Storage discovery with saved browsing/direct Trash, and read-only iCloud metadata with owner-reported manual acceptance. Storage remains idle on opening; the owner's explicit Scan and optional picker decisions stand. Earlier app footprints/reset, verified cache rules, exact duplicates, analysis cache, central cleanup journal/recovery, and System/menu monitoring remain foundations.

The follow-up review found uninstall/inventory/icon gaps, missing Overview, crowded residue/footer layouts, absent click-away focus, Storage selection/map inconsistencies and incomplete battery reporting. Task 060 corrects app eligibility, inventory and local-resource icon handling. Task 061 restores Overview and simplifies layout/focus. Task 062 corrects Storage selection, map membership and bounded rescan behavior; task 063 corrects battery reporting; they do not reopen completed implementation records or restart the deleted expansion backlog. Task 058 now implements the focused Liquid Glass companion and two-action footer. Task 063 now verifies M2 battery details against the owner’s OS readings. Task 059 implements independently refreshed cache/local-Trash actions and memory help.

Task records 001–006, 008–017, 047, 048 and 050 retain implementation evidence. Task 007 remains closed with manual release checks deferred. The owner requested a 0.2.1 development release and Homebrew update after this core implementation. Release evidence is separate from exhaustive manual platform/UI acceptance.

## Core implementation

| Task | Result |
| --- | --- |
| [054](../tasks/054-direct-uninstall.md) | Implemented: direct app uninstall, compact stable feedback and Undo |
| [055](../tasks/055-residues.md) | Implemented: automatic saved residue observations, exact selectable groups and in-place Trash/Undo |
| [056](../tasks/056-storage-discovery.md) | Implemented: requested local discovery, saved Largest files/Explore browsing and direct selected-file Trash/Undo |
| [057](../tasks/057-icloud-discovery.md) | Implemented: read-only iCloud metadata browsing; owner reports manual integration acceptance |
| [058](../tasks/058-menu-panel.md) | Implemented: focused native Liquid Glass menu, flush below the menu bar, with Open Luma and Maintenance footer actions |
| [060](../tasks/060-app-inventory-and-uninstall-corrections.md) | Implemented: bounded vendor inventory, supported bundle-only uninstall, optional-data retention, narrow companion filtering and local icon preservation; root-native/asset limits recorded |
| [061](../tasks/061-overview-layout-and-input-focus.md) | Implemented: Overview first, residue hierarchy/spacing, click-away focus and compact Storage footer |
| [062](../tasks/062-storage-selection-map-and-continuation.md) | Implemented: cross-folder Selected, shared map/list membership, local row reveal and truthful larger fresh scans |
| [063](../tasks/063-m2-battery-reporting.md) | Implemented: verified M2 condition/cycles/capacity, honest charging/estimate and partial states |
| [059](../tasks/059-maintenance.md) | Implemented: one approval per cache/local-Trash action, bounded permanent removal and verified normal Quit/memory help |

The System view stays at its current scope; 063 corrects its existing battery report. Reuse existing execution safeguards while changing the UX. Do not expand monitoring, privacy, photo/Mail tools, ecosystem coverage, scheduling, or distribution work. Only Apple Silicon (`arm64`), macOS 26+, with M2 as reference hardware, is supported.

The owner subsequently approved follow-ups 064–066 in the executable queue. Task 064 now implements exact containing-folder inspection, explicit bounded verification, safe folder selection and credential/configuration protection, including preservation of concurrent unrelated Storage updates. Task 065 implements bounded hidden home-directory observations, curated ownership/CLI guards and post-uninstall remaining-data navigation. Task 066 implements read-only Homebrew inventory and exact cask provenance checks, blocking native Trash-only uninstall for managed casks. There is no automatic expansion outside that approved queue. Complete and demonstrate the applicable core acceptance before proposing further features. Future release work uses the existing distribution process when requested; this plan adds no release or paid-credential gate.
