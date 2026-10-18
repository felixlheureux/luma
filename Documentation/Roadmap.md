# Implementation roadmap

The supplied complete product specification remains canonical. This roadmap records delivery status without narrowing the mature product.

The next implementation sequence and acceptance criteria are in [tasks/README.md](../tasks/README.md). That queue selects the 0.3.0 milestone from this broader roadmap and records the required reference-DMG review checkpoints.

## 0.1 — Native foundation

Implemented: all eight primary navigation areas, system-following appearance with Light/Dark overrides, live menu-bar companion, native overview and monitoring, generated-data scanning, folder storage map, verified exact duplicates, application inventory and exact-related-file review, potential leftover detection, central path validation, explicit confirmation, Trash, local activity history, restore, ignore paths, search, and safety regression tests. A navigation area does not imply its entire mature specification is complete.

Leftover detection checks exact identifiers in caches, application support, preferences, saved state, logs, and metadata-verified containers, plus explicit named support-folder rules for Spotify, Slack, Discord, Obsidian, and VS Code. It excludes installed apps, embedded helpers, Apple data, shared groups, and fuzzy names; ownership is checked again before Trash. Results always require review.

Monitoring separates reusable file cache from used RAM and uses memory units. Resource consumers are grouped under their outer application bundle, with expandable helpers and physical-footprint measurement when available. Live updates are isolated from the sidebar's layout; resizing no longer recomputes large blurred background layers.

The first cache batch includes 18 audited rules: existing developer and app caches, Firefox/Zen local profile caches, Brave/Edge profile cache leaves, npm download and npx caches and logs, Yarn Classic's global cache, supported pnpm registry metadata, and CoreSimulator caches and logs. Browser sessions, website storage, project dependencies, pnpm shared stores, device contents, and runtimes remain outside these rules. Scans report progress and distinguish readable, empty, absent, permission-blocked, and skipped locations. An absent result does not mean all reclaimable data has been found.

## 0.2 — Expanded scanning and recovery

Implemented: expanded cache rules, live scan progress, category totals, per-location coverage and permission guidance, active developer-tool checks, simulator shutdown checks, a durable pre-move journal, interrupted Trash/Restore reconciliation, identity-verified non-overwriting Restore, and manual recovery review. All native and exported logos use the same vector geometry.

Remaining release hardening:

- Expand audited rules for additional cache versions, known generated logs, and developer ecosystems.
- Add rule serialization and validation behind a project-owned loader; evaluate Yams as specified.
- Add finer file-level selection and broader activity guards for additional ecosystems.
- Continue provider-aware access and broader resilience validation after the descriptor identity boundary delivered by task 002.
- Add broader security tests, accessibility review with VoiceOver, localization, signed builds, and notarization.

## 0.3 — Storage and application review milestone in progress

- Implemented task 001: immutable core cleanup plans, selection-wide validation, live full-content duplicate keeper checks, unique logical totals, plan-linked journal outcomes, and a single cleanup executor. All 83 fixture tests and native light/dark review checks pass. Task 002 adds the descriptor identity boundary; residual final-move races remain documented.
- Implemented task 002: descriptor-relative identity and parent-chain checks, byte-exact fingerprints, supported-type/alias exclusions, and non-overwriting descriptor-relative Restore. All 96 tests pass, including real native Trash/Restore and a disposable case-sensitive APFS corpus. Older history remains readable; entries without parent evidence require Finder Restore.
- Implemented task 047: shared ancestor/leaf provider capabilities, synchronous no-materialization I/O scopes, guarded hashing/metadata/cleanup/Restore, skipped coverage and Finder handoffs. Reported provider files remain excluded when downloaded; detection and real-provider integration limits are documented in Safety.md. All 119 tests and native light/dark scan checks pass.
- Implemented task 048: durable grouped cleanup sessions, independent mutation progress/Stop, reviewed eligible-only session Undo, deterministic non-overwriting restoration and per-item outcomes across restart. All 143 fixture tests and native light/dark cleanup checks pass; screenshot/accessibility limits are recorded in the task.
- Implemented task 003: isolated scan sessions, metadata-first application inventory, read-only streaming previews, queued replacement, stopping/stall/timeout states, per-feature completed snapshots and scoped permission retry. Native light/dark checks cover navigation, Settings, window reopening, monitoring and cancelled app inspection.
- Implemented task 050: four verified VS Code 1.142.0 cache/log units, installed-product and helper/process guards, app/category grouping, hard-link-aware logical totals, and post-mutation snapshot invalidation. The support matrix explicitly leaves unverified Electron, sandbox and additional Xcode targets unavailable; broader coverage remains task 031 and later ecosystem tasks. Task 008 migrates the existing coverage without expanding it.
- Implemented task 004: bounded transient hierarchy, cached folder navigation and breadcrumbs, synchronized map/list details, honest remainder/partial-size accounting, current-folder filters, and fresh explicit manual review through the existing plan/journal. Native fixture checks cover three-level navigation, empty/partial/selected states and stale review rejection in both appearances.
- Implemented task 005: shared exact/named/container ownership resolver across footprints, leftovers and mutation validation; categorized unique inspected totals, partial/absent read states, scoped search/sorting and explicit bundle/data selection.
- Implemented task 006: explicit reset intent excludes bundles, separates caches/logs, preferences, saved state and other app data, checks installed ownership and live owner/helper activity at preflight and every move, and reuses reviewed Trash/Activity/Stop/Restore/Undo. Unknown process evidence blocks reset; normal quit requests never force termination.
- Native appearance, accessibility, performance, lifecycle, and packaged-release review.

Tasks 001–006, 047, 048 and 050 are implemented. Task 007 is closed by user request with release checks deferred; 0.3.0 has not been released. Task 008 delivers validated bundled rule files and contributor validation; task 009 publishes the personal Luma Homebrew tap.

## After the current queue

The [extended implementation queue](../tasks/after-current-queue.md) defines tasks 010–030 with dependencies and acceptance criteria. Its phases are intentionally not assigned promised release numbers:

- Developer-project generated data, focused Downloads review, local device-backup review, and a progressive Smart Check.
- Measured local indexing through GRDB when justified, bounded FSEvents invalidation, better duplicate comparison, read-only volume analysis, and Trash review.
- Sustained resource insights, startup/background explanations, and opt-in history/schedules/alerts; passive network monitoring and supported battery details are implemented.
- Source-backed installed-app update discovery, explicit browser privacy workflows, local similar-photo comparison, and read-only Mail storage review.
- Search/favorites, localization and accessibility, community tooling, and individually audited troubleshooting tools.

Sparkle updates for Luma remain a separate conditional task, deferred while Apple distribution credentials are unavailable. Free development releases and other product work continue independently. Broader connected-device/disk-health coverage and additional destructive workflows require their own supported design and validation before being added to the executable backlog.

## Remaining coverage and product-wide validation

[Tasks 031–046](../tasks/mature-product-queue.md) define granular cache review, unused-app evidence, purgeable storage/snapshots, supported disk/thermal/device information, more developer ecosystems, container storage, recent-item privacy, and consistent ignore policies. They also define explicit feasibility assessments for external-volume mutations, narrow Mail cache removal, Photos-library integration, and bundle-resource integrity. Their existence does not enable those capabilities; unsupported assessments may conclude with a documented no-go.

Product-wide scaling/resilience checks, redacted local diagnostics, and a supported-scope release audit complete that queue. The [spec coverage map](../tasks/spec-coverage.md) tracks current foundations and planned work against the canonical requirements and must be updated from implementation evidence.

Binary thinning and localization removal remain conditional on preserving application integrity. No privileged helper is a foundational dependency. Cloud cleaning and antivirus remain out of scope.

The [compiled reference audit](../tasks/compiled-reference-audit.md) now reconciles all 48 original task scopes with executable evidence and Luma-specific requirements. It adds [049](../tasks/049-ai-tool-storage.md) for separately reviewed AI-tool caches and local-model storage; this remains planned work.

## Promoted monitoring and optimization work

Task 017 delivers passive network rates/interface/session usage and supported battery details. Sustained resource evidence (018) is next. Task 051 adds explicit app review/normal quit and observed memory-relief outcomes, including a no-action-needed state. It assesses any direct reclaim capability separately; it does not add RAM purging, artificial allocation pressure or automatic termination. Login/background review (019) follows shared ownership work without waiting for network/battery details. Task 052 adds deliberate network quality tests with throughput, latency, loaded responsiveness and native diagnostics handoffs. The remaining work is planned independently of the 0.3.0 release gates.

Task 053 adds planned live disk activity and supported app attribution, with logical/physical metric scope kept explicit; it does not diagnose drive failure or a bottleneck from traffic alone.

## Code organization and maintenance

Task 028 phase A is now an early engineering foundation with no release/catalog prerequisite. [Architecture.md](Architecture.md) records the current responsibility risks, target feature/core organization, explicit composition and concurrency boundaries, fixture seams and artifact hygiene. Formatter/CI setup and actual source reorganization remain planned; they should land incrementally with focused features and separate mechanical commits. Phase B community rule validation follows task 008.

Task 007 was closed at the user’s request, with manual release checks deferred: custom surfaces now honor Reduce Transparency and Increase Contrast; result expansion and storage scrolling honor Reduce Motion. Search, scan coverage and item consequence controls have explicit accessible names and larger icon hit targets. A debug nine-page appearance/layout smoke review and mounted installer payload verification support the release gate. Full keyboard/VoiceOver and actual system accommodation review, large-list interaction traces and public 0.3.0 checksum verification remain outstanding. The version remains 0.2.0 until the release review is complete.

Task 008 migrates all 22 generated rules and five named ownership mappings into a versioned bundled YAML catalog without adding supported paths. Pinned Yams stays behind RuleLoader; validation is atomic and the runtime SafetyEngine remains authoritative. The validator runs locally and in CI, and installer checks verify the bundled catalog and third-party notices. See CONTRIBUTING.md for the schema, supported boundaries, fixture contribution example and validation commands.

Task 009 publishes the clean `luma` Homebrew cask in [the personal tap](https://github.com/felixlheureux/homebrew-luma), pinning the real published 0.2.0 arm64/macOS 26.0 installer. Public-route installation, style/online audit, actual 0.1.2→0.2.0 upgrade and removal checks pass, with retained user data and quarantine. The current ad-hoc development build is rejected by Gatekeeper; successful first launch is not established. Release-to-cask proposals verify published assets before producing a reviewed update.

Task 010 adds Projects for explicitly chosen Node/Rust/Swift folders and workspaces, with bounded version-1 build/dependency rules, kept source/configuration/unknown data, no automatic selection and existing review/Trash/Activity recovery. Project directory and manifest identity/hash, current ignore/provider/ownership/tree evidence and idle tools are checked before mutation. Linked/shared stores, vendored data, Swift checkouts and custom targets remain excluded. See [Developer-Projects.md](Developer-Projects.md) for supported paths and limits. Task 011 adds the focused Downloads workflow described below.

Task 011 adds Downloads for explicitly chosen local folders: disjoint type totals, intersecting size/modification-age filters, actual files versus unimplemented browser/app-history records, bounded text/raster previews and unverified source metadata. Exact duplicate downloads share the existing full-SHA256 verifier and core independent-keeper policy; files remain personal data and incomplete-name/linked/shared/provider content stays excluded. Ordinary authorized review/Trash/Activity/Restore handles every move. See [Downloads.md](Downloads.md) for preview and discovery limits. Task 012 adds the capability-gated backup inspection described below.

Task 012 delivers Backups as an explicit read-only inspection of the standard MobileSync location, with device name/date/encryption observations, logical size and distinct incomplete/corrupt/empty/unreadable/changed states. Only bounded summary plists are read; payloads and manifest databases remain opaque. No supported format/activity combination for direct in-app removal was established, so the task's inspection-only branch applies to every backup. Core backup-path protection, no selection/cleanup authority and Finder guidance make that limitation explicit. See [Device-Backups.md](Device-Backups.md). Task 013 adds progressive Smart Check: independently completed generated-data, inventory and leftover checks, optional explicitly chosen project/Downloads folders, scoped/time-stamped navigation, distinct incomplete states and captured storage/memory/thermal measurements. There is no combined savings total or automatic selection/action. Task 014 adds a separate GRDB-backed local APFS metadata/hash index with full discovery/access revalidation, conservative FSEvents invalidation, cache clearing and fresh-analysis fallback. Warm duplicate scans improve on the recorded fixture; storage traversal remains fresh. Task 015 adds shared folder/Downloads copy comparison, complete-group filters and stable ordering, bounded local previews and date/path keeper proposals. Applying a proposal checks current full content; the ordinary plan/journal retains independent keeper checks. Task 016 adds supported local-volume selection, separate capacity/free/system-available observations, inspection-only external/system targets and volume/root-bound snapshots with unmount/replacement invalidation. Native read-only APFS-image and existing storage/cache checks pass; broader filesystem and physical-drive coverage remain limited. Task 017 adds passive single-interface network rates/session totals and supported battery details in System and the companion, with unavailable fields preserved. Continue with task 018 (process insights).
