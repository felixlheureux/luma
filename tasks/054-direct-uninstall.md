# 054 — Uninstall directly from the app list

Status: Ready  
Priority: P0  
Depends on: Existing CleanupPlan, CleanupJournal, SafetyEngine and ApplicationRelationships

## Outcome

Click Uninstall on a supported app row and it moves to Trash. No footprint panel, folder checklist, second review sheet or acknowledgement. App details remain optional.

## Scope

- Add a clearly named row action. Display its removal scope in the row/disclosure before activation: bundle plus verified exclusively owned generated caches/logs, preferences and saved state. Exclude user documents, unknown/shared support data and containers; do not infer ownership from a similar folder name. Preserve optional inspection of retained data. Do not add app-reset work.
- If another installation with the same bundle identifier remains, uninstall only the chosen bundle and retain identifier-shared related data. Unknown installation multiplicity is not proof of exclusive ownership. Show retained shared data in the row/details without adding a prompt or requiring the user to inspect folders.
- Load inventory automatically and publish app rows before expensive bundle sizing. Keep a previous inventory visible during refresh. No Scan click is required to uninstall; refresh stale evidence internally.
- Introduce only the small shared action/state seam needed for direct execution. Capture the exact action targets in an immutable plan and call the existing journal. Keep protected-app, running-owner/helper, installed ownership, provider, ignore, identity, duplicate and recovery checks. Failure to build or validate the plan is an inline reason, not a new review wizard.
- Enforce ignores in the central normal-Trash validation in both directions: the target cannot be inside an ignored path or contain an ignored descendant. Reject the whole selected parent with an inline explanation; do not silently move the ignored child or split the authorized subtree. Apply current ignores at planning, preflight and final move checks, including ignores added after a scan or plan.
- Scope action availability and selection by feature/snapshot, following the shared UI acceptance in README. An unrelated automatic read scan cannot lock the whole app. Capture intent before awaiting; cancelled/replaced/navigated-away work, including retained duplicate keeper preparation, cannot mutate another feature's selection or resurrect a sheet. Coordinate affected reads internally and serialize filesystem mutations; no new general job framework.
- Put preparing/moving/outcome feedback in stable row/toolbar space. Remove the mandatory AppFootprintView → delayed dismissal → ReviewSheet chain for this action and the RootView progress insertion that shifts the page. Never show preflight 100% followed by move 0%; use an indeterminate status when no meaningful combined percentage exists.
- Measure cold/warm before-and-after plan preparation, ownership discovery, process collection, tree validation, native move and outcome persistence on fixed many-file app and residue fixtures. Remove demonstrated redundant reads or unused subprocess collection without skipping fresh final checks. Do not solve latency with artificial delays, retries, relaxed evidence or larger timeouts.
- Preserve the durable operation outcome through invalidation: show moved/remaining counts and correct success, stopped, partial, failed or recovery-needed state. Undo progress says restored and advances after confirmed restores; failure/cancellation cannot become a generic finished/success state.
- Remove only confirmed moved apps from the list. Keep blocked/failed rows with one useful reason and an explicit retry after correction. Keep durable Activity and compact Undo access; no automatic force quit. Refresh only affected observations, preserving unrelated results/selection even after a failed attempt. Confirmed Restore/Undo of an app refreshes its Installed row without a manual rescan.
- Make compact recovery concrete: an Undo action checks eligibility internally and restores eligible targets from that captured operation; conflicts and per-item Restore stay inline in Activity, without a mandatory preview modal. Keep identity/non-overwrite checks, report partial eligibility honestly and never retry unknown moves. Already restored or permanently unavailable sessions show their terminal state rather than an actionable Review undo. Recovery loading/journal errors disable affected controls with a reason; genuine unresolved-mutation review remains available.
- On normal Quit or last-window termination during a mutation, request Stop, finish the current native mutation and persist its outcome, then terminate. Do not create avoidable recovery work or add a shutdown wizard; idle Quit stays immediate. 058 wires window/menu lifecycle to this shared boundary.

## Acceptance

- [ ] On a fresh launch, a supported app can be uninstalled directly from its row without opening another panel, selecting paths, clicking Scan or confirming again.
- [ ] The exact default related-data contract is fixture-tested, including shared same-ID installations and unknown multiplicity; the selected bundle can be removed while retained shared data stays untouched. Optional Details is never required.
- [ ] A selected folder cannot carry an ignored descendant into Trash, including an ignore added between preflight and the final move. The UI explains the blocked parent without a second review step.
- [ ] Running/protected/unsupported apps show a concise actionable inline state and never trigger force quit or a deletion fallback.
- [ ] Cleanup leaves the current page, scroll and unrelated results/selection stable. Late keeper/preparation callbacks cannot change another view; unrelated background indexing does not block the core action.
- [ ] Success, Stop, failure and partial recovery stay accurately visible through invalidation. Undo/Restore has truthful progress/availability, does not require a mandatory extra preview, and returns a recovered app to Installed.
- [ ] Normal Quit/last-window termination during a mutation drains the current durable item and stops further work before exit; idle Quit is immediate.
- [ ] Fixed-fixture before/after timings and work counts demonstrate reduced avoidable preparation/execution overhead. Eliminate demonstrated redundant traversal, ownership discovery and subprocess collection, or give concrete evidence why the remaining work is necessary. Instrumentation or hiding progress alone does not satisfy this task. UI feedback starts promptly and never presents a restartable validation progress bar.

## Validation and starting points

Use generated apps/data and an injected mover. Cover scope capture, stale/reinstalled ownership, same-ID copies in `/Applications` and `~/Applications`, unknown multiplicity, active helpers, changed paths, partial failure and recovery. Test ignored descendants in selected app/cache/residue/manual folders before planning and between preflight/final move. Include navigation during delayed keeper validation, unrelated scans/failed mutations, app Restore inventory refresh, all-restored sessions, journal-unavailable controls and Quit during a move/restore. Update the ordinary-uninstall assertions in `Scripts/check-application-footprint.sh` and relevant native review/cleanup checks: the old mandatory sheet is no longer expected; core rejection tests remain. Check Light/Dark/System and keyboard action labels. Run relevant tests and the macOS native flow once on the final behavior; record limits if macOS is unavailable.

Start in `ApplicationsView.swift`, `AppFootprintView.swift`, `AppModel.swift`, `ResultsView.swift`, `RootView.swift`, `CleanupSessionViews.swift`, `CleanupPlan.swift` and `CleanupJournal.swift`. Profile `CleanupExecutionContext.current` and repeated relationship/tree collection before changing them. Follow the reference comparison/evidence rules in [README](README.md).
