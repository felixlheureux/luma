# 054 — Uninstall directly from the app list

Status: Done
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

- [x] On a fresh launch, a supported app can be uninstalled directly from its row without opening another panel, selecting paths, clicking Scan or confirming again.
- [x] The exact default related-data contract is fixture-tested, including shared same-ID installations and unknown multiplicity; the selected bundle can be removed while retained shared data stays untouched. Optional Details is never required.
- [x] A selected folder cannot carry an ignored descendant into Trash, including an ignore added between preflight and the final move. The UI explains the blocked parent without a second review step.
- [x] Running/protected/unsupported apps show a concise actionable inline state and never trigger force quit or a deletion fallback.
- [x] Cleanup leaves the current page, scroll and unrelated results/selection stable. Late keeper/preparation callbacks cannot change another view; unrelated background indexing does not block the core action.
- [x] Success, Stop, failure and partial recovery stay accurately visible through invalidation. Undo/Restore has truthful progress/availability, does not require a mandatory extra preview, and returns a recovered app to Installed.
- [x] Normal Quit/last-window termination during a mutation drains the current durable item and stops further work before exit; idle Quit is immediate.
- [x] Fixed-fixture before/after timings and work counts demonstrate reduced avoidable preparation/execution overhead. Eliminate demonstrated redundant traversal, ownership discovery and subprocess collection, or give concrete evidence why the remaining work is necessary. Instrumentation or hiding progress alone does not satisfy this task. UI feedback starts promptly and never presents a restartable validation progress bar.

## Validation and starting points

Use generated apps/data and an injected mover. Cover scope capture, stale/reinstalled ownership, same-ID copies in `/Applications` and `~/Applications`, unknown multiplicity, active helpers, changed paths, partial failure and recovery. Test ignored descendants in selected app/cache/residue/manual folders before planning and between preflight/final move. Include navigation during delayed keeper validation, unrelated scans/failed mutations, app Restore inventory refresh, all-restored sessions, journal-unavailable controls and Quit during a move/restore. Update the ordinary-uninstall assertions in `Scripts/check-application-footprint.sh` and relevant native review/cleanup checks: the old mandatory sheet is no longer expected; core rejection tests remain. Check Light/Dark/System and keyboard action labels. Run relevant tests and the macOS native flow once on the final behavior; record limits if macOS is unavailable.

Start in `ApplicationsView.swift`, `AppFootprintView.swift`, `AppModel.swift`, `ResultsView.swift`, `RootView.swift`, `CleanupSessionViews.swift`, `CleanupPlan.swift` and `CleanupJournal.swift`. Profile `CleanupExecutionContext.current` and repeated relationship/tree collection before changing them. Follow the reference comparison/evidence rules in [README](README.md).

## Implementation and evidence — 2026-10-19

- Added automatic progressive inventory and direct row Uninstall. Scope is visible before activation; Details remains optional. Only exact generated/settings relationships enter the default plan. Support data, containers and documents stay. A second same-ID installation or incomplete ownership evidence retains all related data. Launch Services errors are distinguished from a successful no-match result.
- Captured uninstall intent uses the existing journal, fresh process/helper/ownership checks and unchanged provider, pinned-identity, volume and recovery gates. Related data precedes the bundle so every related-data check can still verify its installation. Central plan, preflight and final-move checks reject ignored parents and ignored descendants, including new ignores after preflight.
- Application reads yield to app mutation/recovery; unrelated scans remain independent. Selections are keyed by feature, root and evidence snapshot. Late keeper/review callbacks cannot select another page or reopen its panels. Confirmed app Restore/Undo refreshes the row, including its verified size; a cancelled inventory cannot later hide it.
- Persistent footer feedback, inline blocked reasons and compact Undo replace the ordinary uninstall/recovery sheet chain. The mutation owner carries Stop through navigation. Activity preserves terminal outcomes, eligibility/conflicts and individual Restore. Undo progress counts confirmed restores. Normal termination requests Stop and replies only after the mutation owner drains.
- Normal initial window size remains **1200 × 850**. Narrow sizing is optional; the native checker now restores the prior frame immediately after its narrow capture and again on exit. Earlier QA left the window narrow; the correction restores normal geometry and records the regression rather than changing the default.

### Fixed-fixture measurements

Apple M2, arm64, macOS 27.0.1, debug build. Run `LUMA_UNINSTALL_BENCHMARK=1 bash Scripts/test.sh --filter ApplicationUninstallTests.fixedFixtureTimings`. The first pass is labeled cold, the second warm; OS caches were not flushed. Each preparation fixture has 513 app files, 513 cache files and 513 retained-support files, plus small log/settings/state fixtures. Execution uses the same app/cache size and five selected roots. All fixtures are disposable.

The baseline reconstructs the earlier full-footprint preparation and repeated owner-preflight path under the current safety engine; it is not an execution of a historical app binary. Both executions use identical selected roots and fresh final checks. Context sampling is measured separately from execution with a fixed process context.

| Stage | Cold baseline → direct | Warm baseline → direct |
| --- | --- | --- |
| Preparation | 339 → 243 ms | 311 → 237 ms |
| Process/context collection | 140 → 33 ms | 221 → 38 ms |
| Preflight, including ownership discovery | 6,078 → 1,344 ms | 6,120 → 1,354 ms |
| Execution | 12,280 → 7,640 ms | 12,316 → 7,714 ms |
| Tree inspection during execution | 331 → 329 ms | 339 → 335 ms |
| Injected native filesystem moves | 0.89 → 0.85 ms | 0.85 → 0.90 ms |
| Durable journal writes | 105 → 104 ms | 105 → 109 ms |

Preflight owner/helper walks fall from **five to one**; each final move still discovers owners afresh. Uninstall omits an unused tools subprocess; other plans collect only the tools/process evidence they consume. Direct preparation avoids recursively inspecting retained support/container data. Plan traversal still computes unique hard-link contributions; preflight, final checks and post-move verification remain necessary to reject stale identities and preserve durable recovery. These injected-mover measurements do not measure Finder/native Trash overhead or promise real-app timings.

### Validation

Core regression suite: 292 tests in 29 suites pass, including exclusive/shared/unknown ownership, a new installation after planning, running/missing process evidence, partial failure/reconciliation, round-trip Undo, and ignored descendants through app/manual/generated/residue planning and execution. Existing identity/provider/duplicate/journal tests remain intact. The debug app builds; native preview script ran in both appearances.

Native generated-fixture checks cover automatic progressive inventory, direct execution without sheets, navigation during a paused move, row retention until confirmed bundle movement, unrelated selection, inline failure and journal-unavailable reasons, direct Undo and restored-row continuity during a stale inventory, narrow layout and original-frame restoration, late keeper callbacks, and the shared termination-drain callback. Optional footprint/reset regression checks retain their explicit-selection safety coverage. No real user data or native Trash is used.

Limits: full manual keyboard/VoiceOver traversal, real-app Trash latency, actual OS exit during a native move, and interactive reference-app behavior remain unverified. Existing core cancellation-inside-Trash/Restore tests and native Stop/drain checks cover the durable boundary without inducing a real interrupted mutation. Reference checkpoints are recorded in [reference-checks.md](reference-checks.md).

Final native results: application/optional-footprint/reset checks pass in Light, Dark and System; direct fixture operation takes 2.998 / 2.955 / 2.947 seconds, including an intentional paused move. Cleanup Stop/Undo and retained-residue feedback pass in Light/Dark. Scan lifecycle passes in Light/Dark (6,000-file inventories 1.169 / 1.174 seconds); duplicate comparison/keeper/final-review regressions pass in both appearances. Default-size restored captures are 2400×1700 pixels at 2×, confirming 1200×850 points. The final complete Swift suite passes all 292 tests.

The final additional System-appearance check passes all 23 native assertions, including preservation of an unrelated queued scan and original window-frame restoration. The debug bundle passes strict deep signature verification.
