# 024 — Unify search, tool navigation, and favorites

Status: Backlog  
Priority: P2  
Phase: Cross-cutting — Faster navigation as features grow  
Depends on: [003](003-scan-sessions.md), [013](013-smart-check.md)

## Why

As Luma gains specialized reviews and monitors, users should be able to find a tool or return to a useful view without memorizing its navigation location.

## Scope

- Define a project-owned tool registry containing names, aliases, destinations, capability requirements, and supported shortcuts. Reuse it for Command-K, contextual recommendations, and favorites.
- Search tools first, then available local analysis results with clear type/scope/time labels. Avoid an implicit full-disk search or new background index of personal content.
- Add user-managed favorites and recent tool destinations with stable identifiers, accessible reordering, and graceful handling of unavailable features.
- Keep destructive actions behind their normal review flow. A command-palette result can open Reset or cleanup review, but cannot directly perform a destructive action.
- Preserve useful power-user inspection details such as rules, confidence, paths, identities, and coverage without making the everyday search surface an implementation console.

## Acceptance criteria

- [ ] The same registered tool opens the same destination from search, favorites, and a recommendation.
- [ ] Search is keyboard/VoiceOver accessible and handles aliases, no results, unavailable capabilities, and stale analysis clearly.
- [ ] Favorites survive app restart and schema changes without depending on localized titles.
- [ ] No search result bypasses cleanup authorization, confirmation, or journal validation.

## Validation

Test registry integrity, destination resolution, favorite migration, result ordering, and unavailable tools. Manually check keyboard focus, shortcuts, accessible names, and both appearances with the expanded feature set.

## Starting points

[RootView.swift](../Sources/LumaApp/RootView.swift), [AppModel.swift](../Sources/LumaApp/AppModel.swift), [OverviewView.swift](../Sources/LumaApp/OverviewView.swift), and task 013's recommendation destinations. Spec: sections 73–74, 97–99, and 108.17 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare tool search, favorites, result context, and navigation continuity. Log the three checkpoints in [reference-checks.md](reference-checks.md).

