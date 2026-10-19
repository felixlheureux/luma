# Luma product specification

**Current scope: core reset, 2026-10-19.** This replaces the former full-product expansion specification. [tasks/README.md](../tasks/README.md) is the sole execution order. This document defines intended behavior; [Safety.md](Safety.md) records the existing engine and limits. New behavior is not implemented merely because it is specified here.

Luma is a native, local-first macOS utility for removing apps, dealing with residues, understanding storage, viewing system resources, and performing a few explicit maintenance actions. The core must be pleasant to use before it grows.

## Supported platform

Apple Silicon (`arm64`) only, macOS 26+. The owner's M2 is the reference machine. Do not add Intel (`x86_64`) support, Intel-only features, universal binaries, Rosetta compatibility work or Intel test/release gates. Every shipped maintenance action must be useful and supported on Apple Silicon. Omit inapplicable reference features entirely from the interface.

## Applications

The app list loads automatically and offers Uninstall on each supported row. One click starts moving the app to Trash from that list; opening a footprint inspector or selecting folders is never required. The standard action removes the bundle and verified exclusive generated caches/logs, preferences and saved state. Personal documents, unknown/shared support data and containers are excluded. If another installed copy has the same identifier, keep its shared related data and remove only the chosen bundle; unknown multiplicity does not establish exclusivity. The row exposes the scope before the action; optional details can explain retained data.

Use exact ownership evidence and existing protection/running-app checks. Blocked operations give one actionable inline reason. Do not force-quit apps, require a manual rescan, or create an uninstall wizard. Confirmed moves update the row and offer compact Activity/Undo access. App reset is not a primary core action.

## Residues

Opening Residues starts a bounded refresh automatically. Show saved observations immediately on return and publish usable results progressively; an initial discovery may take time but does not require a Scan click. Explain freshness, incomplete coverage and permissions without blanking the list.

Residues are grouped by their exact full bundle identifier (for example `com.vendor.app`), with item count, unique size and a selectable group header. The header supports none/some/all selection and includes collapsed/offscreen eligible children; individual items remain selectable. Similar vendor prefixes do not merge owners, and refresh arrivals are not selected automatically.

Users select residues or whole groups and click Move to Trash in the same view. The selection is the authorization; no second panel, confirmation checkbox, or repeated review step follows. Inline details show paths and consequences beforehand. Unclaimed app data is not automatically junk; ownership must still be verified at execution. Preserve scroll, filters and unaffected results after cleanup.

## Storage

Provide one useful Storage destination for large files and folders across accessible internal Mac storage. Opening Storage must not start a filesystem scan. Show saved observations immediately when available, with their timestamp, and wait for an explicit Scan accessible Mac or Scan again action. Default to largest items and publish partial results during a requested scan. Keep the existing optional folder picker under Locations. Do not restart scans in response to background filesystem activity; targeted observation updates after an authorized mutation may still run.

Discover roots and volumes automatically. Use standard macOS permission guidance, including a single Settings handoff for Full Disk Access where needed; do not make a recurring folder chooser the main flow. Show inaccessible/excluded locations as coverage, not zero bytes or an empty healthy system. Avoid scanning APFS firmlink aliases twice or traversing system/package internals just to fill a chart. System-managed space can be a read-only capacity category. External volumes are optional. Discovery limits retain useful prioritized results and visible remaining coverage; they must not send the user back to a smaller-folder picker. Allocated-byte observations are not guaranteed unique physical usage or reclaimed space on APFS.

Use a Space Lens-style proportional bubble map beside a size-ranked folder list, with linked hover/focus, breadcrumbs and back/forward/up navigation. A Largest files mode ranks files across the same discovered roots/index. Keep selection across folders/modes, with a fixed selected-count/size footer, an inline Selected filter and direct Move to Trash. Use a responsive list-first layout at narrow widths. Projects, Downloads and chosen-folder workflows are consolidated into Storage locations/filters. Remove their redundant top-level entry points and repeated scan prompts. Keep specialized deletion rules behind the list; never label source, dependencies or old downloads disposable merely because of their location or age.

Storage's local personal-file selection authorizes only selected items in the supported home scope, with current evidence and the existing Trash engine. Automatically discovering a root grants inspection, not broad mutation authority. Explicitly selected supported home-local files obtain narrow action authority without the old folder picker; eligibility is per item, so a read-only broad root does not disable every home-file action. Preserve duplicate keep-one rules wherever known duplicate candidates are actionable.

## iCloud discovery

Include iCloud Drive and synced Desktop/Documents in Storage through a distinct read-only metadata capability. Show downloaded, online-only, unavailable and unknown states. Keep logical file size separate from locally allocated bytes; unknown allocated size is not zero, and online-only logical bytes are not reclaimable local storage.

Do not download content to scan, size, preview, hash or draw icons. Do not treat app-specific ubiquity queries or an extension's File Provider domain list as an inventory of all user cloud files. Resolve actual available roots and report tested coverage. iCloud rows provide Reveal in Finder; direct cloud deletion, eviction and cloud cleaning remain outside this core. This separates useful cloud browsing from the existing local cleanup authority.

## System and menu panel

Keep the current System view, its metrics and lightweight sampling. Do not start the deleted process/network/device expansion tracks.

The menu companion has a flat top without an arrow/extrusion. The first icon click opens an interactive, correctly focused panel using the final Light/Dark/System appearance. Clicking inside must not change its inactive tint. Retain icon toggle, outside-click/Escape dismissal, keyboard access, screen-edge positioning and menu-only lifecycle. Focusing the panel must not open the main window.

## Maintenance

One view opens directly to cache cleanup, Empty Trash and honest memory help, with independently refreshed status and no full-machine scan gate. Reuse existing catalog coverage and memory telemetry. Keep choices, approval, progress and outcomes in this view; no guided multi-panel routine or automatic optimization.

- **Caches:** show supported units with consequences, initially unselected. One approval cleans the chosen units through the normal Trash journal. Personal/session data and active app/tool data remain protected.
- **Trash:** one explicit irreversible-action approval empties only the displayed, supported current-user local Trash scope. Use a separate bounded permanent-deletion operation, never a fallback in normal cleanup. Preserve later arrivals, report partial failures, and remove Restore eligibility for permanently removed items. Unsupported or unreadable scopes offer Open Trash.
- **Memory:** show pressure and reuse existing explicit normal app Quit actions when useful. Clearing Luma-owned caches may be described only as Luma's own memory. No supported beneficial system-wide RAM reclaim API has been established; do not ship a misleading Clear RAM button, artificial allocation pressure, swap deletion, or a root-helper purge. A healthy Mac can correctly need no action.

DNS flushing, search reindexing and broad troubleshooting are excluded.

## Interaction and engineering boundaries

Normal app/residue Trash actions require no Luma confirmation beyond the direct action. Inspection, immutable planning, freshness checks, ownership, full duplicate verification, durable outcomes and non-overwriting recovery run internally. Optional details are not prerequisites.

Primary navigation consists of Storage, Apps, Residues, Maintenance and System, with Activity/Settings secondary. Open the last valid core page or Storage on first launch; a scan-first Overview and settings-wrapper Privacy page are not primary destinations. Use that same route set in menus, search and the companion. App/file Search uses the existing observations/index and does not create another subsystem.

Current ignores protect selected subtrees in both directions: an ignored child blocks moving its entire parent through normal cleanup. A newly added ignore updates ancestor eligibility and is enforced again at the final move. Automatic refresh settles after Luma-owned persistence writes and isolates volume invalidation to its affected scope.

Read-only background discovery cannot lock unrelated core actions or clear their selections. Capture each action's feature, scope, exact targets and generation before awaiting; late callbacks cannot select another feature's items or reopen a dismissed panel. Navigation does not cancel an already authorized mutation; its captured operation and explicit Stop control retain ownership. Bind displayed results to their published scope and preserve useful unaffected observations. Known duplicate keeper evidence applies when the same members are selected through Storage. Hard-linked names retain per-path logical size while totals use declared unique accounting.

Keep operation outcomes distinct through invalidation; confirmed app recovery updates Installed. Undo checks eligibility internally and offers inline outcomes/per-item recovery without a mandatory preview modal. Ordinary Quit drains the current durable mutation and stops before exit. Action controls show availability/reasons, including journal failure and stale process identity; an enabled action must not silently return. Existing metric failures remain unavailable rather than measured zero. These are core correctness fixes, not a System feature expansion.

Keep progress in stable space in the initiating view. Fast actions finish directly; longer work uses truthful compact status. A validation percentage must not reach 100% and restart for moving. No artificial delays, repeated verification screens, invented retries or timeout increases as a performance fix.

Keep scanners read-only. Separate display observations from executable current evidence. Use existing services and narrow changes; a broad architecture rewrite or new framework is not a core prerequisite. Maintain keyboard access, appearance, reduced-motion/transparency support, synthetic-data safety tests and meaningful native flow checks.

The core consists only of tasks 054–059. Further features require a new owner decision after those flows are demonstrated. Existing implemented secondary tools can remain reachable through optional details where useful, but must not crowd the primary flows or become dependencies.
