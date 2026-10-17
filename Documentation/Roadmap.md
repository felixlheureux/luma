# Implementation roadmap

The supplied complete product specification remains canonical. This roadmap records delivery status without narrowing the mature product.

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
- Add finer file-level selection, streaming application inventory, and broader activity guards for additional ecosystems.
- Strengthen filesystem handling with file-descriptor-based identity and race validation.
- Add broader security tests, accessibility review with VoiceOver, localization, signed builds, and notarization.

## 0.3 — Application lifecycle and storage depth

- Broader confidence-based ownership evidence, shared-container explanations, app reset, and expanded leftover matching.
- Nested storage navigation, multiple volumes, deeper permission handling, incremental indexing, and FSEvents.
- Developer projects, Downloads categories, iOS backups, and Trash usage.
- SQLite through GRDB when persistent indexing is introduced.
- Sparkle 2 for Luma updates, with signed feeds; separate third-party app update discovery.

## 0.4 — Advanced discovery and monitoring

- Similar photos through native Vision/ImageIO processing, with visual comparison.
- Trend-based CPU/memory/swap recommendations and hung-app detection.
- Network throughput, connected devices, reliable battery health, and supported disk diagnostics.
- Audited maintenance operations for specific troubleshooting cases.
- Explicit browser privacy workflows, with sessions and website state kept separate from cache rules.

Binary thinning and localization removal remain conditional on preserving application integrity. No privileged helper is a foundational dependency. Cloud cleaning and antivirus remain out of scope.
