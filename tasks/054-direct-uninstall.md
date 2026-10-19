# 054 — Uninstall directly from the app list

Status: Ready  
Priority: P0  
Depends on: Existing CleanupPlan, CleanupJournal, SafetyEngine and ApplicationRelationships

## Outcome

Click Uninstall on a supported app row and it moves to Trash. No footprint panel, folder checklist, second review sheet or acknowledgement. App details remain optional.

## Scope

- Add a clearly named row action. Display its removal scope in the row/disclosure before activation: bundle plus verified exclusively owned generated caches/logs, preferences and saved state. Exclude user documents, unknown/shared support data and containers; do not infer ownership from a similar folder name. Preserve optional inspection of retained data. Do not add app-reset work.
- Load inventory automatically and publish app rows before expensive bundle sizing. Keep a previous inventory visible during refresh. No Scan click is required to uninstall; refresh stale evidence internally.
- Introduce only the small shared action/state seam needed for direct execution. Capture the exact action targets in an immutable plan and call the existing journal. Keep protected-app, running-owner/helper, installed ownership, provider, ignore, identity, duplicate and recovery checks. Failure to build or validate the plan is an inline reason, not a new review wizard.
- Put preparing/moving/outcome feedback in stable row/toolbar space. Remove the mandatory AppFootprintView → delayed dismissal → ReviewSheet chain for this action and the RootView progress insertion that shifts the page. Never show preflight 100% followed by move 0%; use an indeterminate status when no meaningful combined percentage exists.
- Measure cold/warm before-and-after plan preparation, ownership discovery, process collection, tree validation, native move and outcome persistence on fixed many-file app and residue fixtures. Remove demonstrated redundant reads or unused subprocess collection without skipping fresh final checks. Do not solve latency with artificial delays, retries, relaxed evidence or larger timeouts.
- Remove only confirmed moved apps from the list. Keep blocked/failed rows with one useful reason and an explicit retry after correction. Keep durable Activity and compact Undo access; no automatic force quit. Refresh affected residues and storage observations without blanking unrelated results.

## Acceptance

- [ ] On a fresh launch, a supported app can be uninstalled directly from its row without opening another panel, selecting paths, clicking Scan or confirming again.
- [ ] The exact default related-data contract above is fixture-tested, including exclusions and partial outcomes; optional Details is never required.
- [ ] Running/protected/unsupported apps show a concise actionable inline state and never trigger force quit or a deletion fallback.
- [ ] Cleanup leaves the current page, scroll and surrounding rows stable; successful Trash remains recoverable through the journal.
- [ ] Fixed-fixture before/after timings and work counts demonstrate reduced avoidable preparation/execution overhead. Eliminate demonstrated redundant traversal, ownership discovery and subprocess collection, or give concrete evidence why the remaining work is necessary. Instrumentation or hiding progress alone does not satisfy this task. UI feedback starts promptly and never presents a restartable validation progress bar.

## Validation and starting points

Use generated apps/data and an injected mover. Cover scope capture, stale/reinstalled ownership, active helpers, changed paths, partial failure and recovery. Update the ordinary-uninstall assertions in `Scripts/check-application-footprint.sh` and relevant native review/cleanup checks: the old mandatory sheet is no longer expected; core rejection tests remain. Check Light/Dark/System and keyboard action labels. Run relevant tests and the macOS native flow once on the final behavior; record limits if macOS is unavailable.

Start in `ApplicationsView.swift`, `AppFootprintView.swift`, `AppModel.swift`, `ResultsView.swift`, `RootView.swift`, `CleanupSessionViews.swift`, `CleanupPlan.swift` and `CleanupJournal.swift`. Profile `CleanupExecutionContext.current` and repeated relationship/tree collection before changing them. Follow the reference comparison/evidence rules in [README](README.md).
