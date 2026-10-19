# 056 — Discover large files across the Mac in one Storage view

Status: Ready  
Priority: P0  
Depends on: Existing scan sessions, StorageIndex, StorageVolumes and AnalysisIndex

## Outcome

Open Storage and immediately start understanding what takes space across the Mac. The default flow never asks for a folder and never requires a Scan click.

## Scope

- Automatically discover accessible internal data-volume/user roots, Applications and common large-file locations. Normalize APFS system/data and firmlink aliases, overlapping roots and file identities so the same content is not scanned/counted twice. Protected system-managed areas can be read-only capacity categories; inaccessible areas must show coverage, not zero usage. Do not recursively inspect other users' private data or app/package internals merely to complete a chart. External volumes and a custom location are optional secondary controls.
- Start bounded discovery on entry, publish stable browsable batches, and rank large files/folders as results arrive. Reuse the hierarchy/map/list with breadcrumbs, size sorting, search, and simple type/age/location filters. Make the size visualization readable at narrow widths and synchronized with the list; no new dashboard framework or parallel analyzer.
- Save a bounded browsable observation index with source/root identity, timestamps, size semantics and coverage. Warm entry/relaunch displays it without awaiting traversal. Refresh dirty subtrees; event gaps, volume/root changes and corrupt index state trigger conservative rediscovery. Extend existing AnalysisIndex only where useful; it currently caches hashes/metadata, not a startup inventory. No full-tree rescan on every navigation change. At entry/time/index bounds, retain prioritized results and show remaining coverage with bounded continuation; never fall back to asking for a smaller folder.
- Use one standard permission explanation and System Settings handoff when Full Disk Access is needed. Continue on readable roots while permission is missing. Do not re-open a folder picker as a permission workaround. A user grant is required; do not claim code can enable it.
- Consolidate Projects, Downloads and folder scanning into Storage locations/filters; remove their redundant primary destinations and scan prompts. Keep the current System view. Primary cleanup destinations are Apps, Residues, Storage and (059) Maintenance; Activity/Settings are secondary. Specialized duplicate inspection can stay optional without becoming a prerequisite for finding large files.
- Keep content classification conservative. Personal files, source, dependencies and old downloads are not junk. Local Trash selection authorizes only selected current items in the existing supported home scope, without a second review screen. Automatic discovery is inspection authority, not permission to mutate the whole volume. Preserve known duplicate keep-one rules, ignores and plan/journal checks; broad system/external cleanup is excluded.
- Prepare typed read-only observations for 057's cloud metadata adapter; keep existing provider mutation exclusions in place.

## Acceptance

- [ ] Fresh launch → Storage shows progressive largest-file/folder results without folder selection or a Scan action; permission-limited coverage stays usable.
- [ ] Warm entry/relaunch shows saved hierarchy/results before new filesystem work; changing filters/breadcrumbs does not restart whole-Mac analysis.
- [ ] The default UI answers where space went, with a synchronized map/list, useful sorting and no redundant Projects/Downloads/folder scanner destinations.
- [ ] Root aliases, hard links, volume replacement, event loss and unknown sizes do not inflate totals or authorize deletion. Logical sizes, observed local allocation and capacity are labeled distinctly. Allocated bytes are not additive unique physical usage or guaranteed reclaimable space on APFS (clones/shared extents/snapshots/compression); use honest estimates/unknown categories, not a new extent-analysis subsystem.
- [ ] Local selection/Trash, where supported, stays in Storage and revalidates exact current evidence; read-only/system/provider observations cannot enter cleanup.

## Validation and starting points

Use generated multi-root hierarchies with overlapping aliases, large folders, partial permissions, index restart/corruption and volume changes. Check incremental first results, cancellation, UI navigation during discovery and System monitoring. Update `Scripts/check-storage-browser.sh`, storage-volume and scan QA to exercise the default flow instead of requiring a picker/review sheet. Keep existing cleanup rejection assertions. Record cold first-results, warm-open and discovery work counts with fixture/hardware details; do not substitute longer timeouts.

Start in `StorageView.swift`, `StorageVolumeModel.swift`, `AppModel.chooseFolder`, navigation destinations, `StorageIndex.swift`, `StorageVolumes.swift`, `AnalysisIndex.swift` and scan event publication. Follow [README](README.md) for native/reference evidence.
