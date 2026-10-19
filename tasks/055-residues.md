# 055 — Show residues automatically and trash them in place

Status: Planned  
Priority: P0  
Depends on: [054](054-direct-uninstall.md)

## Outcome

Open Residues, see what is available, select items and click Move to Trash in that view. No manual scan prerequisite, second panel or acknowledgement ladder.

## Scope

- Start one bounded ownership/residue refresh automatically on first entry, sharing application inventory with Apps. Persist bounded timestamped display observations so reopening/relaunching shows prior findings immediately while refreshing. The existing Storage/Duplicates hash cache does not supply this behavior.
- Publish completed per-item observations in coalesced batches without waiting for all Library roots. Distinguish loading, empty, refreshing, partial coverage and permission denial. Keep useful previous results visible; no repeated scans when switching tabs and no false clean state while discovery is incomplete.
- Separate read-only saved/partial observations from executable evidence. Selection captures exact items; obtain fresh ownership/identity evidence internally through 054's direct action path. Do not require the user to run Scan again. A reinstalled owner invalidates that item and gives one inline explanation.
- Group residues by the exact full owning bundle identifier, for example `com.vendor.app`, using the existing `LeftoverGroup`/ownership resolver. Show that identifier as the group title, plus item count and unique logical total. Similar identifiers such as `com.vendor.app2` remain separate; a shared `com.vendor` prefix is not ownership evidence. Unresolved owners are explicitly separate and never gain cleanup eligibility from grouping.
- Each group header has an accessible three-state checkbox (none, some, all). Selecting it selects all currently known eligible children of that exact group, including collapsed/offscreen rows; deselecting clears them. Child checkboxes update the group state. Filtering finds groups without silently changing the selected set; the action summary includes selected hidden groups. Refresh arrivals do not inherit an earlier group selection. No automatic initial selection.
- Provide inline paths, ownership explanation and removal consequences. Initial selection is empty. Row/group selection and Move to Trash live together; only the selected items are authorized. No ReviewSheet, extra checkbox or navigation transition follows.
- Preserve filters, scroll, unaffected findings and valid remaining selection after a subset succeeds. Show stable compact pending/outcome feedback, durable partial results and optional Activity/Undo. Failure never broadens selection or silently retries.
- Bound refresh work and invalidation after app install/uninstall, cleanup and restore. Refresh changed supported roots instead of repeating unrelated full application sizing. Do not create a general background daemon or scheduler.

## Acceptance

- [ ] First entry automatically discovers residues; later opens and relaunches show saved findings before background work completes.
- [ ] Exact bundle-identifier groups have count/size and selectable headers; mixed child selection, collapse, scrolling, filtering and refresh preserve a predictable selected set without prefix-based owner merges.
- [ ] Selected local residues or whole groups move to Trash with one action from the list and no second view or confirmation.
- [ ] Stale observations, installed/embedded owners, shared/Apple data, links, provider paths and unreadable roots remain correctly protected; incomplete coverage is visible.
- [ ] Reopening, refreshing and partial cleanup do not blank, jump or reset the list; display observations never bypass current core checks.

## Validation and starting points

Use synthetic home/app roots, injected ownership observations and a controllable scan clock. Check cold/warm entry, cancellation/replacement, late events, reinstall races, subset failure and relaunch. Cover group select/deselect, mixed state, similar identifier prefixes, collapsed/offscreen children, filtered selected groups, unknown owners and new children arriving after selection. Replace sheet-centric residue QA with direct-flow checks and retain ownership/journal regression tests. Record first-results, warm-open and selection-to-outcome timings with fixture size.

Start in `ApplicationsView.swift` (`LeftoversView`), `ResultsView.swift`, `AppModel.swift`, `LeftoverScanner.swift`, `ApplicationRelationships.swift`, `ScanController` and 054's direct-action state. Follow [README](README.md) for native/reference evidence.
