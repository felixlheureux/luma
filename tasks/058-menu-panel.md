# 058 — Make the menu panel flat and immediately active

Status: Planned
Priority: P1  
Depends on: [054](054-direct-uninstall.md) for the shared safe-termination boundary; panel geometry can be developed independently

## Outcome

The first menu icon click opens a flat-top companion in its final appearance, already focused and interactive. Clicking inside does not recolor it.

## Scope

- Replace the arrow-bearing `NSPopover` boundary with a small arrowless panel/window using public AppKit APIs. Preserve the current companion content and metrics; no redesign or monitoring expansion.
- Anchor to the status icon and clamp to the visible screen on multiple displays and screen edges. No private arrow-hiding properties, view-tree hacks or compositing patches.
- Apply Light/Dark/System appearance before showing and make the appropriate panel/key responder active on the opening click. Do not bring up the main window to focus the companion. Avoid a visible inactive-tint frame.
- Use one core navigation/window-opening action for the companion, Navigate menu and shortcuts. A command issued while the main window is closed must reopen and focus that window at the requested core page; opening only the companion must not reopen it. Wire ordinary Quit/last-window termination to 054's safe mutation-stop boundary.
- Retain lightweight menu metrics while the main window is closed, without collecting a hidden process table solely because the last destination was System/Optimizer. Process detail sampling follows actual visible consumers. Do not add a second monitor or new metrics.
- Render existing missing/initial/stale readings as collecting/unavailable/dated values, not measured zero or an unconditional Live badge. Use available rather than free for capacity available for important usage. A present battery with unknown charge remains an unavailable battery state, not the no-battery Thermals fallback. Keep System's layout and scope.
- Preserve icon toggle, outside-click and Escape dismissal, keyboard access, menu preference changes and menu-only lifecycle. Manage event observers locally and remove them when closing; no second monitoring timer.

## Acceptance

- [ ] Flat top with no arrow/extrusion in Light, Dark and System appearance.
- [ ] One icon click opens the final active appearance; a first click on any interior control works immediately without a focus-only click or tint change.
- [ ] Toggle, outside-click, Escape, keyboard navigation and display-edge placement work while the main window is closed and while another app is active.
- [ ] Navigate/menu commands reopen a closed main window at the requested core page; companion-only opening does not. Quit safely respects an active mutation.
- [ ] Menu-only sampling stays lightweight and existing unavailable/stale values are labeled honestly, without a System redesign or new metrics.
- [ ] Closing/reopening the panel preserves the existing monitor lifecycle and respects reduced transparency/contrast; no main-window flash or duplicate polling.

## Validation and starting points

Inspect the actual native panel in both appearances and System mode, including first open from an inactive app. Check multiple-screen positioning with injected screen bounds plus available real displays. Check Navigate with the main window closed, safe Quit during injected mutation, process sampling visibility and unavailable telemetry. Update menu/window native smoke assertions; no new core test framework for cosmetic geometry. Record unavailable desktop/display checks honestly.

Start in `StatusBarController.swift`, `MenuCompanion`, appearance handling and existing lifecycle/native-UX checkers. The current `.transient` NSPopover neither activates Luma nor makes its content window key. Follow [README](README.md) for reference evidence.
