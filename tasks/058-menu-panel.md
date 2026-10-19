# 058 — Make the menu panel flat and immediately active

Status: Done
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

- [x] Flat top with no arrow/extrusion in Light, Dark and System appearance.
- [x] One icon click opens the final active appearance; a first click on any interior control works immediately without a focus-only click or tint change.
- [x] The footer has only two labeled primary actions, Open Luma and Maintenance. Both work with the main window closed; Settings and Quit remain accessible in one secondary menu. Restoring Overview does not add another footer button.
- [x] Toggle, outside-click, Escape, keyboard navigation and display-edge placement work while the main window is closed and while another app is active.
- [x] Navigate/menu commands reopen a closed main window at the requested core page; companion-only opening does not. Quit safely respects an active mutation.
- [x] Menu-only sampling stays lightweight and existing unavailable/stale values are labeled honestly, without a System redesign or new metrics.
- [x] Closing/reopening the panel preserves the existing monitor lifecycle and respects reduced transparency/contrast; no main-window flash or duplicate polling.

## Validation and starting points

Inspect the actual native panel in both appearances and System mode, including first open from an inactive app. Check multiple-screen positioning with injected screen bounds plus available real displays. Check Dock/reopen with only Settings or the companion visible (an unverified native edge case, not an established failure). Check Navigate with the main window closed, safe Quit during injected mutation, process sampling visibility and unavailable telemetry. Update menu/window native smoke assertions; no new core test framework for cosmetic geometry. Record unavailable desktop/display checks honestly.

Start in `StatusBarController.swift`, `MenuCompanion`, appearance handling and existing lifecycle/native-UX checkers. The baseline `.transient` NSPopover neither activated Luma nor made its content window key. Follow [README](README.md) for reference evidence.

## Follow-up review — 2026-10-19

Source review of `c03e185` confirms that `MenuCompanion.swift` builds five bottom navigation controls from `Destination.core`, and `StatusBarController.swift` still uses the arrow-bearing popover. The owner requests the earlier compact footer. At that review checkpoint the task remained In progress; the review itself established no native focus, tint or geometry pass. Battery collection/presentation corrections belong to [063](063-m2-battery-reporting.md).

## Implementation — 2026-10-19

- Replaced `NSPopover` with a borderless `NSPanel`, created with the public nonactivating style and explicit key eligibility. The companion takes key focus directly instead of relying on an asynchronous application-activation request. Showing it does not open the main window. Its outer surface is a native macOS 26 `NSGlassEffectView` in regular style; the owner explicitly requested Liquid Glass after the first working material. Placement is flush with the menu bar's lower edge, centered on the status item where screen bounds permit. Content scrolls on short screens.
- The footer contains exactly two labeled actions, Open Luma and Maintenance, independent of `Destination.core`. Settings and Quit share a secondary menu. Navigate commands, shortcuts and companion actions share `openMain`; reopening retains the running window's page unless a destination was requested. Dock reopening also brings main forward when Settings or the companion is already visible. Overview startup/routing remains owned by 061.
- Main-window visibility, miniaturization and occlusion now gate process-table collection. The existing monitor continues lightweight samples with main closed; the status controller's existing two-second preference refresh remains separate from telemetry. Missing CPU/memory/disk/swap measurements have explicit availability, unavailable CPU/memory samples no longer enter histories, network intervals keep their baseline/gap state, and a battery with unknown charge stays Battery/Unavailable. The header dates stale samples, and Storage uses available capacity rather than calling it free. Existing System graph badges/readouts use the same availability and date semantics, with measured-sample counts rather than claiming uninterrupted elapsed history; its layout and metric set stay intact.
- Escape, icon toggle, outside clicks, application deactivation and display changes dismiss the panel. Local/global event monitors and dismissal notifications exist only while open and are removed on dismissal or preference disable. Appearance changes apply to the actual panel; native glass owns material/accessibility behavior. Quit continues through 054's unchanged mutation-stop/drain boundary.

## Validation

- `bash Scripts/test.sh`: **321 reported tests across 32 suites passed**, including five opt-in skips. The final debug app builds. Existing core ownership, identity, provider and cleanup/recovery policies remain unchanged.
- `bash Scripts/check-monitoring-depth.sh` passes Light/Dark: measured single-interface rates, battery partial/unavailable fields, closed-main menu monitoring and distinct memory pressure. Actual core medians were 5.39–5.40 ms; extended medians 8.80–8.88 ms and p95 9.25–13.18 ms on this M2/macOS 27.0.1. These are local passive-collection observations, not a new metric or battery-source acceptance for 063.
- Initial focus checks failed with a visible, non-key panel after `NSApp.activate()` left the app inactive. Creating the panel with the public nonactivating style corrected the key boundary. Expanded preference QA now keeps the main window visible while disabling the menu (to avoid legitimate last-window termination), accounts for the existing two-second status refresh and removes old reports before launching. Failed attempts are excluded from accepted evidence.
- The required `bash Scripts/preview.sh` was run; its known generic-launcher limitation persists: no full-size main-window snapshot replaced the stale 38×38 capture, so its dimension assertion fails. Generic preview output is not accepted UI evidence. Full-size Light/Dark/System menu captures come from the dedicated native checker; whole-window/view snapshots cannot establish every behind-window glass compositing effect.

- `bash Scripts/check-menu-panel.sh` passes on the stable checker in Light/Dark/System: key opening, native Liquid Glass, a top flush with the menu bar, unchanged appearance on an interior click, both footer actions on their first click with main closed, retained page, Escape/outside/icon dismissal, observer removal, preference disable/reenable, requested-page navigation, and actual Settings-only Dock reopening. Injected negative-origin/short-screen/left/right-edge bounds pass; two real displays are present, with the real status-item screen exercised. Read-only collecting and stale/unknown-charge captures were inspected. No mutation or personal-folder scan is invoked. One earlier run edited its shell checker while running and ended with a shell parse error after assertions; it is excluded from accepted evidence, and the stable checker was rerun.
- Limits: full physical keyboard/VoiceOver traversal, toggling system Reduce Transparency/Increase Contrast, exhaustive real-display/Space transitions, pixel-level behind-window refraction/tint comparisons, and actual OS exit during a native Trash operation remain manual. AppKit's native glass owns accessibility material behavior; instrumented key/appearance checks and snapshots do not establish every composited animation. The existing safe termination boundary is preserved, without a real interrupted mutation. macOS 26-specific integration was not run on this macOS 27.0.1 M2 machine. Overview/new-launch routing remains task 061, and battery-source investigation remains 063.
- Final `bash Scripts/check-cleanup-sessions.sh` passes Light/Dark with an injected disposable mover: in-flight Stop, durable partial outcomes, direct Undo, preserved contents and monitoring/menu continuity. `bash Scripts/check-window-lifecycle.sh` passes closed-main monitoring, retained status item, reopening and explicit Quit. Strict deep signature verification, shell syntax and `git diff --check` pass. No release/version/distribution changes were made.
