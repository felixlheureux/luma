# 025 — Make the expanded product localizable and accessible

Status: Backlog  
Priority: P2  
Phase: Cross-cutting — Product completeness  
Depends on: [007](007-native-ux-and-release.md), [008](008-community-rules.md), [024](024-search-favorites.md)

## Why

Accessibility is required in every feature, starting with task 007. This task extends that baseline across the growing product and removes hard-coded language/formatting assumptions before community translations expand.

## Scope

- Adopt a localization resource approach supported by the actual Swift Package and command-line build, with stable keys and separate localizable rule explanations. Keep matching logic and identifiers independent of display language.
- Externalize user-facing strings, pluralization, dates, units, error context, and accessibility descriptions. Preserve System appearance and locale-sensitive presentation.
- Test longer text, larger supported text sizes, right-to-left layout, keyboard-only navigation, VoiceOver, Increase Contrast, Reduce Transparency, and Reduce Motion.
- Give charts, treemaps, status colors, and icon-only actions equivalent textual meaning. Maintain full-row targets and predictable focus when progressive results arrive.
- Add translator/contributor guidance. Use pseudo-localization for coverage; add a real additional locale only with reviewed translations rather than claiming machine-generated text is verified.

## Acceptance criteria

- [ ] All supported user workflows and rule consequences can be localized without changing identifiers or safety logic.
- [ ] Plurals, units, long labels, and layout direction behave correctly in the chosen resource/build system.
- [ ] Essential actions and result meaning are available without pointer precision, color perception, animation, or the graphical map.
- [ ] The expanded product has a recorded accessibility review with specific remaining limitations, if any.

## Validation

Run resource/key consistency checks, pseudo-localized native previews, and a manual assistive-technology matrix. Keep visual snapshots focused on meaningful states rather than testing every reversible cosmetic adjustment. Existing per-task accessibility acceptance remains mandatory before this task lands.

## Starting points

[Design.swift](../Sources/LumaApp/Design.swift), [RootView.swift](../Sources/LumaApp/RootView.swift), task 008's rule schema, task 024's registry, and [Package.swift](../Package.swift). Spec: sections 95, 98–99, and 106.6 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare information density, long-label handling, alternate appearance, and nonvisual navigation where testable. Record observations rather than assuming the reference's accessibility quality in [reference-checks.md](reference-checks.md).

