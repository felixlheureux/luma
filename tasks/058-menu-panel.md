# 058 — Make the menu panel flat and immediately active

Status: Ready  
Priority: P1  
Depends on: None

## Outcome

The first menu icon click opens a flat-top companion in its final appearance, already focused and interactive. Clicking inside does not recolor it.

## Scope

- Replace the arrow-bearing `NSPopover` boundary with a small arrowless panel/window using public AppKit APIs. Preserve the current companion content and metrics; no redesign or monitoring expansion.
- Anchor to the status icon and clamp to the visible screen on multiple displays and screen edges. No private arrow-hiding properties, view-tree hacks or compositing patches.
- Apply Light/Dark/System appearance before showing and make the appropriate panel/key responder active on the opening click. Do not bring up the main window to focus the companion. Avoid a visible inactive-tint frame.
- Preserve icon toggle, outside-click and Escape dismissal, keyboard access, menu preference changes and menu-only lifecycle. Manage event observers locally and remove them when closing; no second monitoring timer.

## Acceptance

- [ ] Flat top with no arrow/extrusion in Light, Dark and System appearance.
- [ ] One icon click opens the final active appearance; a first click on any interior control works immediately without a focus-only click or tint change.
- [ ] Toggle, outside-click, Escape, keyboard navigation and display-edge placement work while the main window is closed and while another app is active.
- [ ] Closing/reopening the panel preserves the existing monitor lifecycle and respects reduced transparency/contrast; no main-window flash or duplicate polling.

## Validation and starting points

Inspect the actual native panel in both appearances and System mode, including first open from an inactive app. Check multiple-screen positioning with injected screen bounds plus available real displays. Update menu/window native smoke assertions; no new core test framework for cosmetic geometry. Record unavailable desktop/display checks honestly.

Start in `StatusBarController.swift`, `MenuCompanion`, appearance handling and existing lifecycle/native-UX checkers. The current `.transient` NSPopover neither activates Luma nor makes its content window key. Follow [README](README.md) for reference evidence.
