# 059 — Add small, explicit Maintenance actions

Status: Planned  
Priority: P1  
Depends on: [054](054-direct-uninstall.md), [055](055-residues.md); existing verified cache catalog and System telemetry

Execution order: finish the in-progress [058](058-menu-panel.md) and owner-requested corrections 060–063 before starting this new view. Follow [the queue](README.md); the earlier task number does not take priority over core fixes.

## Outcome

One Maintenance view offers cache cleanup, Empty Trash and useful memory help. Choices, at most one approval per consequential action, compact progress and outcomes stay in that view.

## Scope

- Target native Apple Silicon/M2 on macOS 26+ only. Every available maintenance action must apply to that platform. Do not implement Intel-only RAM tasks, x86 compatibility or unsupported legacy actions, including as disabled UI tiles.

- Open Maintenance directly with compact action rows/cards. Refresh cache findings, supported Trash usage and memory telemetry independently in place; an available action never waits for a whole-machine Performance/Smart Check scan. Show each action's scope, consequence, availability and any permission requirement before its one approval.
- Move/reuse the current generated-cache selection here rather than adding another cleaner. Show supported cache units, current size/coverage and consequences, with empty initial selection. One approval trashes selected units through 054's direct action seam and the existing journal. Keep active app/tool checks and personal/session data exclusions. Keep observed versus actionable counts/totals consistent after ignoring an item: an ignored cache cannot remain advertised as actionable in a category summary/badge. Distinguish all ignored, no matches, empty and incomplete discovery. No broad rule/catalog expansion.
- Show the supported current-user local Trash scope and observed usage. Empty Trash has one explicit confirmation that removal is permanent. v1 supports only the accessible current-user local Trash root resolved using public Foundation APIs; external-volume and provider Trash are not silently included. An unreadable root offers Open Trash and a clear unavailable state.
- Implement Empty Trash as a separate bounded operation, not a permanent-delete fallback in CleanupJournal. Capture the reviewed top-level targets and recheck root/volume/owner/object/descendant identities without following links. Freeze the approved descendant snapshot as well as top-level targets. Delete only those unchanged entries; never recursively remove a directory wholesale or remove the Trash root itself. Remove an approved directory only when empty, so new arrivals or changed subtrees remain for a later action. Document the remaining native pathname race rather than promising atomic deletion. Serialize against cleanup/restore. Persist per-item outcomes and invalidate Restore/Undo eligibility for items actually removed. No shell commands, Finder scripting, root helper or user-supplied paths.
- Report confirmed emptied, skipped, failed and cancelled results honestly in place. Cancellation stops only at safe item boundaries; interrupted deletion is not automatically repeated. Mark a partially deleted tree as no longer fully restorable, even if deleting its root failed; never claim the whole Trash was emptied when items remain or scopes were unavailable. Do not claim file-level journaling makes permanent deletion reversible.
- Reuse current memory pressure/usage and existing normal per-app Quit controls, inline. Under low pressure show that no action is needed. Measure observed state after an explicit supported action; do not claim guaranteed freed RAM. Keep consumer identity and row position stable while hovered, focused or selected so a live update cannot redirect a Quit click. Bind Quit to the displayed sampled bundle/path and process-instance identity, revalidate before requesting normal termination, and refuse a disappeared/reused PID. Report requested, awaiting save/exit, exited or refused/unavailable inline; a sent request is not confirmed exit. Luma can release its own caches, described only as Luma-owned memory. No supported beneficial system-wide RAM reclaim API is established: do not invent a Clear RAM button, run `purge`, induce allocation pressure, delete swap or add an app-quit wizard.
- Consolidate the existing Clean/Optimizer primary destinations into Maintenance as needed; preserve System's current display and sampling. No DNS flush, Spotlight/Mail repair, new diagnostics, scheduling, bundled Run All routine or automatic cleanup.

## Acceptance

- [ ] All implemented actions apply to native Apple Silicon/M2 on macOS 26+; no Intel-only functionality or Intel acceptance gate is introduced.
- [ ] One screen opens directly with supported cache choices, Empty Trash and memory state/help. Independent refresh never gates all actions on a full scan; scope, availability, approval and outcomes remain in place.
- [ ] Cache cleanup and permanent Trash emptying each require exactly one clear Luma approval; cancellation leaves unapproved work untouched.
- [ ] Empty Trash is restricted to the displayed local user scope, preserves new/changed items, handles denied/partial/interrupted states and updates recovery eligibility correctly.
- [ ] Ordinary app/residue/cache Trash never falls back to permanent deletion. Memory help never advertises unproven system RAM reclamation or automatically quits apps.
- [ ] Ignored/filtered cache states have consistent actionable totals and empty-state copy; enabled actions never silently no-op. Quit revalidates the sampled app instance and reports its actual outcome without PID retargeting.
- [ ] Progress occupies stable space and remains truthful; existing System/menu monitoring continues while maintenance runs.

## Validation and starting points

Use generated cache and Trash roots and injected movers/removers/telemetry. Never empty personal Trash or quit personal apps for validation. Cover new arrivals, changed descendants, links, stale/foreign ownership, partial deletion, permission loss, cancellation, crash/restart reconciliation, operation serialization and affected/unaffected Restore eligibility. Update safety documentation for the separate permanent operation when it is implemented. Also cover ignored-last-result summaries, PID reuse/app exit before Quit, termination refusal/save prompts and failed settings handoffs. Verify one approval and stable feedback natively in Light/Dark/System.

Start in `CleanStorageViews.swift`, `GeneratedDataGroupsView`, `OptimizerView`, `SystemMonitor.swift`, `MemoryAccounting.swift`, `CleanupActivity.swift`, `CleanupJournal.swift` and 054's action presentation. Use a narrow maintenance operation owner, not a general command runner. Follow [README](README.md) for reference evidence.

## Primary platform evidence

Reviewed 2026-10-19: [Apple's Trash directory](https://developer.apple.com/documentation/foundation/url/trashdirectory), [explicit removal API](https://developer.apple.com/documentation/foundation/filemanager/removeitem(at:)), [permanent Trash behavior](https://support.apple.com/guide/mac-help/delete-files-and-folders-on-mac-mchlp1093/mac), [memory pressure/cached files](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac), and [app-owned purgeable memory](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/CachingandPurgeableMemory.html). These document primitives and semantics; they do not establish global Finder-equivalent Trash scope or a general RAM-reclaim service.

## CleanMyMac comparison — 2026-10-19

Current CleanMyMac uses Performance for maintenance and [My Tools](https://macpaw.com/support/cleanmymac/knowledgebase/my-tools) for direct tool access; older CleanMyMac X used a separate Maintenance module. My Tools is the relevant inspiration for avoiding a scan-first gate. This is a comparison and scope decision, not a new backlog.

| Reference capability | Luma core decision |
| --- | --- |
| User caches / system junk | Reuse verified user-cache catalog with one approval; no system-wide cleaner |
| Trash bins, including multiple locations | One approved supported local-user Trash scope; label excluded bins |
| Maintenance Free Up RAM | Excluded: Intel-only reference task; pressure and explicit normal Quit are supported on M2 |
| Menu Free Up / Optimize | Separate documented action; its algorithm and Apple Silicon benefit are not established by the guide |
| Periodic scripts | Documented for Ventura 13 and earlier; omitted for Luma's macOS 26+ target |
| DNS cache reset / Spotlight reindex | Targeted troubleshooting; outside this core |
| Mail database / permission repair | Outside this core; no broad database or permission mutation |
| Purgeable-space action / snapshot thinning | Outside this core; no speculative reclaim or deletion of recovery points |

Sources: current [maintenance guide](https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks), [edition/task matrix](https://macpaw.com/support/cleanmymac/knowledgebase/missing-features), [separate RAM Menu guide](https://macpaw.com/support/cleanmymac/knowledgebase/check-and-free-ram), and [Apple local-snapshot semantics](https://support.apple.com/en-us/102154). The maintenance guide limits the Performance tasks to MacPaw/Setapp editions; the edition page separately lists My Tools availability. Do not infer identical actions/algorithms across editions. Vendor optimization claims are not performance measurements. Evidence is documentation/screenshots, not a live reference cleanup or benchmark.
