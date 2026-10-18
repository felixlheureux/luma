# 032 — Review applications with old or unknown usage evidence

Status: Backlog  
Priority: P2  
Phase: F — Finish everyday cleanup coverage  
Depends on: [005](005-application-footprints.md), [013](013-smart-check.md)

## Why

An app can occupy substantial space without being useful to its owner anymore. Last-use evidence should help a user decide, while missing metadata must not become a claim that an app was never opened.

## Scope

- Add a usage-evidence provider for supported local metadata, with source, timestamp, confidence/limitations, and unavailable states. Verify current platform behavior before choosing a source.
- Offer configurable review thresholds, name/size/last-use sorting, and bundle versus inspected-footprint totals. Do not substitute modification or installation date for last use.
- Show current running state and available update context without launching a network check just to populate this view.
- Exclude protected apps and honor app-level ignores. Old or unknown use is informational; uninstall remains a separate explicit review through the existing executor.
- Add evidence-backed Smart Check recommendations without automatic selection or new ongoing usage surveillance.

## Acceptance criteria

- [ ] Missing, stale, disabled, or unreliable metadata appears as unknown rather than Never used.
- [ ] Thresholds and date sorting operate on the declared source and retain predictable unknown ordering.
- [ ] Running/protected/ignored apps are handled consistently with installed-app review and uninstall safety.
- [ ] Recommendations disclose the last-use evidence and do not classify old apps as junk.

## Validation

Use injected usage metadata for old/recent/unknown dates, reinstallations, multiple copies, clock changes, and running apps. Verify the review-to-uninstall path with disposable application fixtures.

## Starting points

[ApplicationsView.swift](../Sources/LumaApp/ApplicationsView.swift), [Models.swift](../Sources/LumaCore/Models.swift), task 005's resolver, and task 013's recommendation model. Spec: sections 37, 44, and 71 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare usage thresholds, unknown states, footprint context, and review actions at all three checkpoints. Record observations in [reference-checks.md](reference-checks.md).

