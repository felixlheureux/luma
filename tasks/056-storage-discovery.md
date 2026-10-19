# 056 — Discover large files across the Mac in one Storage view

Status: Ready  
Priority: P0  
Depends on: Existing scan sessions, StorageIndex, StorageVolumes and AnalysisIndex

## Outcome

Open Storage and immediately start understanding what takes space across the Mac. The default flow never asks for a folder and never requires a Scan click.

## Scope

- Automatically discover accessible internal data-volume/user roots, Applications and common large-file locations. Normalize APFS system/data and firmlink aliases, overlapping roots and file identities so the same content is not scanned/counted twice. Protected system-managed areas can be read-only capacity categories; inaccessible areas must show coverage, not zero usage. Do not recursively inspect other users' private data or app/package internals merely to complete a chart. External volumes and a custom location are optional secondary controls.
- Start bounded discovery on entry and publish stable browsable batches. Offer two modes in the same Storage view/index: Largest files ranks files across all discovered roots with containing location, date and size; Explore browses one folder's hierarchy. Share search, kind/size/date/location filters and sorting; switching modes never starts a second scan engine.
- Use current CleanMyMac Space Lens as the concrete exploration reference: a proportional bubble map beside a largest-first same-folder list at ordinary window widths. Link hover/keyboard focus across both and show concise name, size, containing path and available modified date. Bubble area represents the same displayed byte metric as the list; small or unknown entries remain accessible through an explicit Other items row/disclosure. Synthetic remainder graphics are not filesystem targets. Keep Luma's original visual style, not copied assets.
- Folder bubble click, row double-click/Return or a chevron opens that folder. Single row focus and removal checkboxes are distinct from navigation. Supply back/forward/up and clickable breadcrumbs without rescanning. Preserve current folder and scroll during updates; do not reorder an active row beneath the pointer. At narrow widths use a list-first/stacked layout with all actions still accessible.
- Preserve explicit selection across folders and both modes. A fixed footer shows selected count, unique logical bytes and Move to Trash; an inline Selected filter exposes selections hidden by navigation/search without a basket/review screen. Selecting a parent replaces selected descendants; an already covered child cannot create an overlapping executable item. Refresh arrivals do not inherit selection. Keep confirmed outcomes and remaining selection in place; no mandatory second removal page.
- Save a bounded browsable observation index with source/root identity, timestamps, size semantics and coverage. Warm entry/relaunch displays it without awaiting traversal. Refresh dirty subtrees; event gaps, volume/root changes and corrupt index state trigger conservative rediscovery. Extend existing AnalysisIndex only where useful; it currently caches hashes/metadata, not a startup inventory. No full-tree rescan on every navigation change. At entry/time/index bounds, retain prioritized results and show remaining coverage with bounded continuation; never fall back to asking for a smaller folder.
- Use one standard permission explanation and System Settings handoff when Full Disk Access is needed. Continue on readable roots while permission is missing. Do not re-open a folder picker as a permission workaround. A user grant is required; do not claim code can enable it.
- Consolidate Projects, Downloads and folder scanning into Storage locations/filters; remove their redundant primary destinations and scan prompts. Keep the current System view. Primary cleanup destinations are Apps, Residues, Storage and (059) Maintenance; Activity/Settings are secondary. Specialized duplicate inspection can stay optional without becoming a prerequisite for finding large files.
- Keep content classification conservative. Personal files, source, dependencies and old downloads are not junk. Local Trash selection authorizes only selected current items in the existing supported home scope, without a second review screen. Automatic discovery is inspection authority, not permission to mutate the whole volume. Preserve known duplicate keep-one rules, ignores and plan/journal checks; broad system/external cleanup is excluded.
- Prepare typed read-only observations for 057's cloud metadata adapter; keep existing provider mutation exclusions in place.

## Acceptance

- [ ] Fresh launch → Storage shows progressive largest-file/folder results without folder selection or a Scan action; permission-limited coverage stays usable.
- [ ] Warm entry/relaunch shows saved hierarchy/results before new filesystem work; changing filters/breadcrumbs does not restart whole-Mac analysis.
- [ ] Explore has a side-by-side proportional bubble map and largest-first list, linked hover/focus, usable Other items, breadcrumbs and back/forward/up. Map clicks navigate; narrow widths remain usable.
- [ ] Largest files searches/ranks across discovered roots on the same index; selection survives folders/modes/filters, with an accurate fixed footer and direct in-view Trash. No duplicate scan engine or review basket.
- [ ] Projects/Downloads/folder scanning no longer appear as redundant primary destinations.
- [ ] Root aliases, hard links, volume replacement, event loss and unknown sizes do not inflate totals or authorize deletion. Logical sizes, observed local allocation and capacity are labeled distinctly. Allocated bytes are not additive unique physical usage or guaranteed reclaimable space on APFS (clones/shared extents/snapshots/compression); use honest estimates/unknown categories, not a new extent-analysis subsystem.
- [ ] Local selection/Trash, where supported, stays in Storage and revalidates exact current evidence; read-only/system/provider observations cannot enter cleanup.

## Validation and starting points

Use generated multi-root hierarchies with overlapping aliases, large folders, partial permissions, index restart/corruption and volume changes. Check incremental first results, cancellation, global versus current-folder search, synchronized map/list focus, history/breadcrumb navigation, remainder access, cross-folder selection and parent/child normalization, narrow layouts and System monitoring. Update `Scripts/check-storage-browser.sh`, storage-volume and scan QA to exercise the default flow instead of requiring a picker/review sheet. Keep existing cleanup rejection assertions. Record cold first-results, warm-open and discovery work counts with fixture/hardware details; do not substitute longer timeouts.

Start in `StorageView.swift`, `StorageVolumeModel.swift`, `AppModel.chooseFolder`, navigation destinations, `StorageIndex.swift`, `StorageVolumes.swift`, `AnalysisIndex.swift` and scan event publication. Follow [README](README.md) for native/reference evidence.

## CleanMyMac comparison — 2026-10-19

Use the current [Space Lens results guide](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results) and its official screenshots for the map/list/navigation reference; [Large & Old Files](https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old) informs the global file list. [Space Lens defaults to the main drive](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens), so a folder picker is a secondary scope control. Luma discovery remains automatic. Its [separate removal review](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-cleanup) is not a Luma requirement: selected local items move to Trash in the current browser.

Evidence is current official documentation and screenshots, not a live DMG run or validated knowledge of proprietary internals. Do not claim preview/provider safety from screenshots. Keep 057's no-download policy and Luma's local Trash semantics.
