# After 030 — Remaining product work

Tasks 031–046 close remaining everyday-feature gaps, define conditional capability assessments, and add product-wide validation. They extend the [earlier queue](after-current-queue.md). None is implemented by creating these files; the [spec coverage map](spec-coverage.md) distinguishes current foundations from planned work.

The early cache-discovery batch is now [050](050-expanded-cache-discovery.md), included in 0.3.0. This later queue starts with **031 — granular cleanup** and **032 — unused-app review**, then take **043 — consistent ignore policies** as a cross-cutting improvement. Follow dependency order for the other tasks. The priority of a feature is more useful than its numeric position; unsupported optional assessments and task 027's credential constraint do not block unrelated work.

## Finish everyday coverage

| ID | Task | Priority | Outcome |
| --- | --- | --- | --- |
| 031 | [Granular cleanup and broader cache rules](031-granular-cleanup.md) | P2 | Inspect supported cache children and review smaller selections with the same core guarantees. |
| 032 | [Unused-application review](032-unused-applications.md) | P2 | Review old usage evidence without treating missing metadata or old apps as junk. |
| 049 | [AI-tool caches and local-model storage](049-ai-tool-storage.md) | P2 | Separate verified agent caches from conversations, installed versions, and deliberately retained model assets. |
| 036 | [More developer ecosystems](036-more-developer-ecosystems.md) | P3 | Extend explicit project/cache support to Go, Python, Gradle, Ruby, Flutter, and .NET in reviewed batches. |
| 037 | [Container storage](037-container-storage.md) | P3 | Understand local runtime storage and assess exact, bounded runtime actions. |
| 042 | [Recent-activity privacy](042-recent-activity-privacy.md) | P3 | Review supported recent-item references separately from personal files and browser state. |
| 043 | [Visible ignore policies](043-ignore-policies.md) | P2 | Apply file, app, rule, volume, project, and duplicate exclusions consistently. |

## Explain system-managed storage and hardware

| ID | Task | Priority | Outcome |
| --- | --- | --- | --- |
| 033 | [Purgeable storage and snapshots](033-purgeable-snapshots.md) | P3 | Explain reclaimability and evaluate supported, explicit system actions without inflated savings. |
| 034 | [Disk and thermal diagnostics](034-disk-and-thermal-diagnostics.md) | P3 | Show measured supported diagnostics and honest unavailable states. |
| 035 | [Connected devices](035-connected-devices.md) | P3 | Add supported accessory/drive context and opt-in alerts to the monitor. |

## Assess capabilities before extending mutation boundaries

| ID | Task | Priority | Decision required |
| --- | --- | --- | --- |
| 038 | [External-volume Trash/Restore support](038-external-cleanup-support.md) | P3, conditional | Verify exact volume identity, native Trash, disconnection recovery, and non-overwriting Restore. |
| 039 | [Mail cache removal](039-mail-cache-feasibility.md) | P3, conditional | Establish that a specific versioned target is regenerable and safe, or retain read-only review. |
| 040 | [Photos-library integration](040-photos-library-support.md) | P3, conditional | Establish supported provider permissions/identity/recovery, beginning with read-only review. |
| 041 | [Binary and language-resource integrity](041-bundle-resource-integrity.md) | P3, conditional | Demonstrate preserved signing/runtime/update integrity or document omission of mutation. |

A conditional assessment can finish with a supported, fixture-backed proposal or a documented no-go. A no-go does not mean the corresponding mutation feature is implemented. Preserve the useful inspection/handoff feature and record the outcome in the coverage map. Required evidence must not be replaced by an unsafe fallback or a false recovery promise.

## Validate the expanded product

| ID | Task | Priority | Outcome |
| --- | --- | --- | --- |
| 044 | [Scale and resilience](044-scale-and-resilience.md) | P2 | Measure combined scan/index/monitor behavior under large datasets, interruption, and long sessions. |
| 045 | [Local diagnostics](045-local-diagnostics.md) | P2 | Make failures inspectable with bounded local logs and previewable redacted exports. |
| 046 | [Stable-milestone audit](046-stable-milestone-audit.md) | P2 | Verify included capabilities against the spec, tested platforms, actual app, and released installer. |

Every task includes dependencies, acceptance criteria, validation, and the recurring [reference-DMG checkpoints](README.md#reference-dmgs-check-throughout-the-work). Continue logging the filename/version, comparison method, observations, and limits in [reference-checks.md](reference-checks.md). Task 046 repeats the comparison across the included product rather than treating the planning resource inventory as workflow evidence.

## Planning boundary

These tasks form a requirements-backed queue. The later-numbered [047](047-provider-aware-filesystem.md), [048](048-cleanup-session-undo.md), and [050](050-expanded-cache-discovery.md) are near-term 0.3.0 additions for provider access, session recovery, and expanded cache discovery, as ordered in [README.md](README.md). Keep task state honest as implementation and platform evidence change. Add further tasks for a demonstrated gap, supported new ecosystem, measured regression, or user need; update the existing task when the work is already represented. The product remains local-first, has no foundational privileged helper, and excludes antivirus, cloud cleaning, fabricated memory boosts, and arbitrary command execution.

