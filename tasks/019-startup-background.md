# 019 — Explain login and background items

Status: Planned  
Priority: P1  
Phase: C — More useful live monitoring  
Depends on: [003](003-scan-sessions.md), [005](005-application-footprints.md)

## Why

Users need to understand which components run at login or in the background, which app owns them, and what macOS allows them to change.

## Scope

- Inventory supported user-level login/background mechanisms using documented APIs and bounded readable metadata. Identify parent apps, executable paths, mechanism, known state, and evidence.
- Reuse ownership resolution and live process grouping where they provide reliable links. Unknown ownership stays unknown, with Reveal and inspection actions.
- Report measured recent resource activity when available; do not invent startup-impact scores or describe unknown components as suspicious.
- Offer native controls only when the platform permits the specific action. Otherwise open the relevant System Settings destination with a concise explanation.
- Do not rewrite macOS private management databases, disable protected services, or require a foundational privileged helper. Inspection is not permission to remove launch configuration files.

## Acceptance criteria

- [ ] Fixture mechanisms and app/helper relationships are identified without broad executable-name guesses.
- [ ] Unknown, restricted, disabled, and running states are distinguishable.
- [ ] Every enabled control is backed by a supported action and verifies the resulting state; restricted items provide an appropriate handoff.
- [ ] Inventory works with limited permissions and remains useful when some mechanisms cannot be enumerated.

## Validation

Verify current platform capabilities from primary documentation before defining controls. Use synthetic user-level metadata and disposable registered fixture apps for actions, plus negative tests for protected components and ambiguous owners.

## Starting points

Task 005's ownership resolver, [ProcessGrouping.swift](../Sources/LumaCore/ProcessGrouping.swift), [MonitorViews.swift](../Sources/LumaApp/MonitorViews.swift), and [PrivacyHistorySettings.swift](../Sources/LumaApp/PrivacyHistorySettings.swift). Spec: sections 28–29, 91–93, and 108.14 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare startup/background grouping, ownership explanations, measured impact, and settings handoffs. Record the three required checks in [reference-checks.md](reference-checks.md).

