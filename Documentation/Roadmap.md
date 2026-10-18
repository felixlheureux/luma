# Implementation roadmap

The supplied complete product specification remains canonical. This roadmap records delivery status without narrowing the mature product.

The next implementation sequence and acceptance criteria are in [tasks/README.md](../tasks/README.md). That queue selects the 0.3.0 milestone from this broader roadmap and records the required reference-DMG review checkpoints.

## 0.1 — Native foundation

Implemented: all eight primary navigation areas, system-following appearance with Light/Dark overrides, live menu-bar companion, native overview and monitoring, generated-data scanning, folder storage map, verified exact duplicates, application inventory and exact-related-file review, potential leftover detection, central path validation, explicit confirmation, Trash, local activity history, restore, ignore paths, search, and safety regression tests. A navigation area does not imply its entire mature specification is complete.

Leftover detection checks exact identifiers in caches, application support, preferences, saved state, logs, and metadata-verified containers, plus explicit named support-folder rules for Spotify, Slack, Discord, Obsidian, and VS Code. It excludes installed apps, embedded helpers, Apple data, shared groups, and fuzzy names; ownership is checked again before Trash. Results always require review.

Monitoring separates reusable file cache from used RAM and uses memory units. Resource consumers are grouped under their outer application bundle, with expandable helpers and physical-footprint measurement when available. Live updates are isolated from the sidebar's layout; resizing no longer recomputes large blurred background layers.

Cleanup now includes 18 audited rules: existing developer and app caches, Firefox/Zen local profile caches, Brave/Edge profile cache leaves, npm download and npx caches and logs, Yarn Classic's global cache, supported pnpm registry metadata, and CoreSimulator caches and logs. Browser sessions, website storage, project dependencies, pnpm shared stores, device contents, and runtimes remain outside these rules. Scans report progress and distinguish readable, empty, absent, permission-blocked, and skipped locations. An absent result does not mean all reclaimable data has been found.

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
- Central provider/dataless access policy so broader analysis does not assume cloud-managed files behave like ordinary local files.
- Visible cleanup sessions with progress, safe stopping between moves, and reviewed session Undo with accurate partial recovery.
- Implemented task 003: isolated scan sessions, metadata-first application inventory, read-only streaming previews, queued replacement, stopping/stall/timeout states, per-feature completed snapshots and scoped permission retry. Native light/dark checks cover navigation, Settings, window reopening, monitoring and cancelled app inspection.
- Task 050: a first independently verified batch of broader cache discovery, with app/category details and coverage, before the later full catalog/child-selection work.
- Hierarchical storage navigation, synchronized map/list selection, and explicit manual review.
- Shared application ownership evidence, clearer footprint categories, and explicit application reset.
- Native appearance, accessibility, performance, lifecycle, and packaged-release review.

Tasks 001–003 are implemented. Tasks 004–007 and near-term tasks 047–048/050 remain planned; 0.3.0 has not been released. Validated community rule files and a personal Homebrew tap follow as tasks 008–009.

## After the current queue

The [extended implementation queue](../tasks/after-current-queue.md) defines tasks 010–030 with dependencies and acceptance criteria. Its phases are intentionally not assigned promised release numbers:

- Developer-project generated data, focused Downloads review, local device-backup review, and a progressive Smart Check.
- Measured local indexing through GRDB when justified, bounded FSEvents invalidation, better duplicate comparison, read-only volume analysis, and Trash review.
- Passive network monitoring, reliable battery details, sustained resource insights, startup/background explanations, and opt-in history/schedules/alerts.
- Source-backed installed-app update discovery, explicit browser privacy workflows, local similar-photo comparison, and read-only Mail storage review.
- Search/favorites, localization and accessibility, community tooling, and individually audited troubleshooting tools.

Sparkle updates for Luma remain a separate conditional task, deferred while Apple distribution credentials are unavailable. Free development releases and other product work continue independently. Broader connected-device/disk-health coverage and additional destructive workflows require their own supported design and validation before being added to the executable backlog.

## Remaining coverage and product-wide validation

[Tasks 031–046](../tasks/mature-product-queue.md) define granular cache review, unused-app evidence, purgeable storage/snapshots, supported disk/thermal/device information, more developer ecosystems, container storage, recent-item privacy, and consistent ignore policies. They also define explicit feasibility assessments for external-volume mutations, narrow Mail cache removal, Photos-library integration, and bundle-resource integrity. Their existence does not enable those capabilities; unsupported assessments may conclude with a documented no-go.

Product-wide scaling/resilience checks, redacted local diagnostics, and a supported-scope release audit complete that queue. The [spec coverage map](../tasks/spec-coverage.md) tracks current foundations and planned work against the canonical requirements and must be updated from implementation evidence.

Binary thinning and localization removal remain conditional on preserving application integrity. No privileged helper is a foundational dependency. Cloud cleaning and antivirus remain out of scope.

The [compiled reference audit](../tasks/compiled-reference-audit.md) now reconciles all 48 original task scopes with executable evidence and Luma-specific requirements. It adds [049](../tasks/049-ai-tool-storage.md) for separately reviewed AI-tool caches and local-model storage; this remains planned work.

## Promoted monitoring and optimization work

After scan-session support, prioritize passive network rates/interface/session usage (017) and sustained resource evidence (018) independently. Task 051 adds explicit app review/normal quit and observed memory-relief outcomes, including a no-action-needed state. It assesses any direct reclaim capability separately; it does not add RAM purging, artificial allocation pressure or automatic termination. Login/background review (019) follows shared ownership work without waiting for network/battery details. Task 052 adds deliberate network quality tests with throughput, latency, loaded responsiveness and native diagnostics handoffs. These are planned parallel follow-ups, not additional implicit 0.3.0 release gates.

Task 053 adds planned live disk activity and supported app attribution, with logical/physical metric scope kept explicit; it does not diagnose drive failure or a bottleneck from traffic alone.

## Code organization and maintenance

Task 028 phase A is now an early engineering foundation with no release/catalog prerequisite. [Architecture.md](Architecture.md) records the current responsibility risks, target feature/core organization, explicit composition and concurrency boundaries, fixture seams and artifact hygiene. Formatter/CI setup and actual source reorganization remain planned; they should land incrementally with focused features and separate mechanical commits. Phase B community rule validation follows task 008.
