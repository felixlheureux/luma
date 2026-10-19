# 058 — Make the menu panel flat and immediately active

Status: In progress
Priority: P1  
Depends on: [054](054-direct-uninstall.md) for the shared safe-termination boundary; panel geometry can be developed independently

## Outcome

The first menu icon click opens a flat-top companion in its final appearance, already focused and interactive. Clicking inside does not recolor it. Its footer returns to two clear actions: Open Luma and Maintenance.

## Scope

- Replace the arrow-bearing `NSPopover` boundary with a small arrowless panel/window using public AppKit APIs. Preserve useful companion metrics; no monitoring expansion.
- Replace the five icon-only destination buttons with exactly two labeled primary actions: Open Luma and Maintenance. Open Luma opens/focuses the main window (Overview on a new launch, current page when reopening the running window); Maintenance opens that page directly. Do not generate the footer from the primary-destination array when Overview returns in [061](061-overview-layout-and-input-focus.md). Put Settings and Quit in one compact secondary menu and retain safe termination. Avoid repeated instructional paragraphs in the compact panel.
- Anchor to the status icon and clamp to the visible screen on multiple displays and screen edges. No private arrow-hiding properties, view-tree hacks or compositing patches.
- Apply Light/Dark/System appearance before showing and make the appropriate panel/key responder active on the opening click. Do not bring up the main window to focus the companion. Avoid a visible inactive-tint frame.
- Use one core navigation/window-opening action for the companion, Navigate menu and shortcuts. A command issued while the main window is closed must reopen and focus that window at the requested core page; opening only the companion must not reopen it. Wire ordinary Quit/last-window termination to 054's safe mutation-stop boundary.
- Retain lightweight menu metrics while the main window is closed, without collecting a hidden process table solely because the last destination was System/Optimizer. Process detail sampling follows actual visible consumers. Do not add a second monitor or new metrics.
- Render existing missing/initial/stale readings as collecting/unavailable/dated values, not measured zero or an unconditional Live badge. Use available rather than free for capacity available for important usage. A present battery with unknown charge remains an unavailable battery state, not the no-battery Thermals fallback. Keep System's layout and scope.
- Preserve icon toggle, outside-click and Escape dismissal, keyboard access, menu preference changes and menu-only lifecycle. Manage event observers locally and remove them when closing; no second monitoring timer.

## Acceptance

- [ ] Flat top with no arrow/extrusion in Light, Dark and System appearance.
- [ ] One icon click opens the final active appearance; a first click on any interior control works immediately without a focus-only click or tint change.
- [ ] The footer has only two labeled primary actions, Open Luma and Maintenance. Both work with the main window closed; Settings and Quit remain accessible in one secondary menu. Restoring Overview does not add another footer button.
- [ ] Toggle, outside-click, Escape, keyboard navigation and display-edge placement work while the main window is closed and while another app is active.
- [ ] Navigate/menu commands reopen a closed main window at the requested core page; companion-only opening does not. Quit safely respects an active mutation.
- [ ] Menu-only sampling stays lightweight and existing unavailable/stale values are labeled honestly, without a System redesign or new metrics.
- [ ] Closing/reopening the panel preserves the existing monitor lifecycle and respects reduced transparency/contrast; no main-window flash or duplicate polling.

## Validation and starting points

Inspect the actual native panel in both appearances and System mode, including first open from an inactive app. Check multiple-screen positioning with injected screen bounds plus available real displays. Check Dock/reopen with only Settings or the companion visible (an unverified native edge case, not an established failure). Check Navigate with the main window closed, safe Quit during injected mutation, process sampling visibility and unavailable telemetry. Update menu/window native smoke assertions; no new core test framework for cosmetic geometry. Record unavailable desktop/display checks honestly.

Start in `StatusBarController.swift`, `MenuCompanion`, appearance handling and existing lifecycle/native-UX checkers. The current `.transient` NSPopover neither activates Luma nor makes its content window key. Follow [README](README.md) for reference evidence.

## Follow-up review — 2026-10-19

Source review of `c03e185` confirms that `MenuCompanion.swift` builds five bottom navigation controls from `Destination.core`, and `StatusBarController.swift` still uses the arrow-bearing popover. The owner requests the earlier compact footer. This task remains In progress; no native focus, tint or geometry pass is established by this review. Battery collection/presentation corrections belong to [063](063-m2-battery-reporting.md).
