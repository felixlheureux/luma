# After the current queue

Tasks 010–030 extend the original task queue with concrete implementation work. Most remain backlog, with acceptance criteria and dependencies in each file; 017–019 have been promoted to the near-term parallel track in README.md. The near-term additions 047–048 belong to the 0.3.0 milestone in [README.md](README.md), ahead of these later phases. Phase names describe product outcomes rather than promised version numbers or delivery dates. The [complete specification](../Documentation/Product-Spec.md) remains the full-product boundary.

After the immediate milestone, the promoted monitoring/optimization track and follow-ups 008–009, **010: developer-project review** is implemented. Continue with Downloads review, device-backup review, and Smart Check. These features make the existing storage and safety foundations useful in more everyday situations before adding advanced discovery.

P2 is the next expansion or supporting work. P3 follows the core expansion or needs more platform validation. Dependencies determine when a task can start; cross-cutting work can land as soon as its prerequisites are complete. Task 027 is explicitly deferred to the availability of distribution credentials and blocks none of the other phases.

## Phase A — Recover useful space with clear decisions

| ID | Task | Priority | User outcome |
| --- | --- | --- | --- |
| 010 | [Developer-project review](010-developer-projects.md) | P2 | Done: review bounded generated output/dependencies in explicitly chosen Node, Rust and Swift projects; linked/shared stores and source remain protected. |
| 011 | [Downloads review](011-downloads-review.md) | P2 | Review installers, archives, large/old files, and verified duplicate downloads. |
| 012 | [Device backups](012-device-backups.md) | P2 | Identify local iPhone/iPad backups and review supported actions as user-data decisions. |
| 013 | [Progressive Smart Check](013-smart-check.md) | P2 | Get useful, current recommendations with evidence and coverage, linked to the right review. |

Exit evidence: representative project/Downloads/backup fixtures preserve personal data and ownership boundaries, and Smart Check reports the checks that actually ran without double-counting findings or inventing a health score.

## Phase B — Make deeper analysis fast and understandable

| ID | Task | Priority | User outcome |
| --- | --- | --- | --- |
| 014 | [Incremental local index](014-incremental-index.md) | P2 | Revisit scans with less repeated traversal/hashing and explicit cache freshness. |
| 015 | [Exact-duplicate comparison](015-duplicate-review.md) | P2 | Compare copies and deliberately choose which location to keep. |
| 016 | [Volume analysis](016-volume-analysis.md) | P2 | Browse supported internal/external targets read-only with truthful scope and capacity. |
| 030 | [Trash review](030-trash-review.md) | P2 | Understand space already in Trash and use verified recovery or Finder. |

Exit evidence: measured warm-scan improvements, correct invalidation after change/unmount, usable comparison, and no expansion of mutation authority merely because a location became browsable.

## Phase C — Make the monitor useful over time

| ID | Task | Priority | User outcome |
| --- | --- | --- | --- |
| 017 | [Network and battery details](017-monitoring-depth.md) | P1, near-term | See passive network activity and reliable portable-Mac battery information. |
| 018 | [Process insights](018-process-insights.md) | P1, near-term | Distinguish sustained resource issues and unresponsive apps from normal spikes. |
| 019 | [Login/background items](019-startup-background.md) | P1, near-term | Understand app ownership, measured activity, and available native controls. |
| 023 | [History, schedules, and alerts](023-history-scheduling-alerts.md) | P3 | Compare scans and opt into useful read-only checks/notifications. |

Task [051](051-memory-relief.md) adds the guided memory-relief workflow after 018; [052](052-network-diagnostics.md) adds deliberate active network tests after 017. Task [053](053-disk-activity.md) adds supported live disk I/O with honest attribution/physical-versus-logical scope. Network/battery providers are not prerequisites for memory/process or startup review.

Exit evidence: sample-sequence tests cover sleep, resets, stale identities, and unknown metrics; the menu remains lightweight; no automatic termination, cleanup, or manufactured performance score is introduced.

## Phase D — Add broader discovery and application workflows

| ID | Task | Priority | User outcome |
| --- | --- | --- | --- |
| 020 | [Installed-app update discovery](020-application-updates.md) | P3 | Find supported updates with visible sources and native/vendor handoffs. |
| 021 | [Browser privacy and permissions](021-privacy-workflows.md) | P3 | Review privacy state separately from caches with specific consequences. |
| 022 | [Similar photos](022-similar-photos.md) | P3 | Compare related images locally without calling resemblance an exact duplicate. |
| 029 | [Mail storage review](029-mail-storage-review.md) | P3 | Understand supported Mail storage without modifying mailbox internals. |

Exit evidence: unsupported sources/formats stay unsupported, privacy actions remain separate and explicit, image grouping has documented limits, and network/analysis activity remains user-controlled.

## Cross-cutting and conditional work

| ID | Task | Priority | When to take it |
| --- | --- | --- | --- |
| 024 | [Search and favorites](024-search-favorites.md) | P2 | After Smart Check, as specialized destinations multiply. |
| 025 | [Localization and accessibility](025-localization-accessibility.md) | P2 | After the rule format and navigation registry; individual features must already be accessible. |
| 028 | [Code structure and contributor tooling](028-contributor-tooling.md) | P1, phase A now | Establish architecture/formatting conventions now; integrate community rule validation in phase B after 008. |
| 026 | [Troubleshooting maintenance](026-maintenance-tools.md) | P3 | After each specific operation is verified against current platform behavior. |
| 027 | [Luma's signed in-app updater](027-luma-secure-updates.md) | P3, deferred | When the required credentials become available through a future user decision. |

Luma's own updater is separate from third-party update discovery. The user's current decision to continue without paid Apple enrollment remains in force. GitHub releases, Homebrew preparation, and product features continue independently.

## Reference checks and release discipline

Every task inherits the before/during/completion checks of the Downloads reference DMGs in [README.md](README.md#reference-dmgs-check-throughout-the-work), with evidence in [reference-checks.md](reference-checks.md). Refresh the image inventory and compare actual relevant workflows where accessible; metadata/resource inspection alone is not a visual or behavioral comparison.

Repeat the native appearance, accessibility, lifecycle, fixture safety, packaging, and downloaded-checksum review established by task 007 for every later release. Update its matrix for the features included in that release rather than treating the 0.3.0 review as permanent coverage.

## After 030

Continue with [tasks 031–046](mature-product-queue.md): granular cache review (after the early batch in [050](050-expanded-cache-discovery.md)), unused apps, purgeable storage/snapshots, supported diagnostics/devices, more developer ecosystems, consistent ignores, and product-wide validation. Conditional tasks assess external-volume removal, bounded Mail cache actions, Photos-provider integration, and binary/resource integrity; a documented no-go retains inspection/handoff behavior rather than enabling an unsafe fallback.

The [spec coverage map](spec-coverage.md) records where current foundations and planned tasks meet the mature requirements. Permanent in-app Trash emptying and unsupported destructive provider/database operations remain separate from existing native handoffs and read-only review. Do not mark the full specification complete because the main navigation and task files exist.

