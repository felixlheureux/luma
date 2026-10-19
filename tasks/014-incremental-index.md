# 014 — Make repeated scans faster with a local index

> Core reset, 2026-10-19: 056 extends observations for immediate browsable results; completed hash-cache work alone does not satisfy that task. See [the current queue](README.md). This file retains earlier implementation evidence.

Status: Done
Priority: P2  
Phase: B — Speed and deeper storage analysis  
Depends on: [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [008](008-community-rules.md), [047](047-provider-aware-filesystem.md)

## Why

Once hierarchical scans work, repeated traversal and hashing should not be the normal cost of reopening the same analysis. Introduce persistence only against measured bottlenecks and keep cached data outside the mutation trust boundary.

## Scope

- Measure cold/warm storage scans and duplicate hashing on fixed disposable datasets. Define the useful cache and performance target from that baseline.
- Add a project-owned index interface and use GRDB for SQLite if persistence is justified, following the spec's dependency review. Keep metadata scoped to authorized roots and explicitly chosen scans.
- Store identities, metadata, coverage, rule/catalog version, scan generation, and hash state as needed. Keep schema migrations and a clear way to remove cached local data.
- Use bounded FSEvents invalidation where supported, with a full revalidation fallback for dropped events, journal resets, root replacement, unmounts, or changed rules.
- Never treat a cached record/hash as current authorization for removal. The cleanup executor still performs current identity, ownership, and duplicate-content checks.

## Acceptance criteria

- [x] Measured repeated scans improve without losing coverage or presenting stale results as current.
- [x] Missed events, changed roots, metadata changes, and rule-version changes invalidate affected entries safely.
- [x] Database corruption or a failed migration preserves user files and falls back to a fresh analysis rather than blocking unrelated monitoring.
- [x] Clearing the analysis cache does not erase Activity history, ignore rules, or user data.

## Validation

Add index migration/invalidation fixtures and compare indexed results with cold-scan results. Include cancellation, hard links, root recreation, denied access, and event loss. Verify current dependency maintenance/license at implementation time and record benchmark conditions.

## Starting points

Task 004's transient tree, task 003's scan sessions, [Filesystem.swift](../Sources/LumaCore/Filesystem.swift), and [Package.swift](../Package.swift). Spec: sections 87–90, 105–106.1, and 108.5/108.7 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare repeat-scan feedback, stale/loading states, and storage-navigation continuity. Do not infer the reference's indexing internals. Log observations in [reference-checks.md](reference-checks.md).


## Implementation and measurement — 2026-10-18

`AnalysisIndex` owns a separate disposable SQLite cache through pinned GRDB 7.11.1. `AnalysisEvents` supplies bounded native invalidation hints. Storage/Duplicates are the only consumers; other feature scans and Activity retain their existing stores. Roots must be explicitly scanned, local APFS with a known volume UUID. Other volumes, corruption, unknown/failing migrations and unavailable cache paths fall back to fresh analysis. Settings → General → Saved analysis clears only the owned database/sidecar files, independently of Activity and ignore rules.

Every scan still enumerates current directories, validates paths/provider/access and produces fresh coverage. Hash reuse requires current root/volume/ancestor identity, catalog/policy version and nanosecond stat fingerprints including ctime, birth time, owner/mode/flags and link count. Package/visibility boundaries are checked fresh. No cached coverage, package size or CleanupItem bypasses those checks. A bounded transaction saves reached records with a scan generation; cancellation before commit does not publish a partial generation, and a clear-cache epoch prevents late repopulation. Up to eight roots/100,000 rows per root are retained. All FSEvents notifications conservatively invalidate the whole root; event loss/reset/unmount and unsupported watching retain the full fresh-metadata fallback. Detected changes during analysis produce incomplete/rescan guidance.

The duplicate mutation path never consumes cached hashes: current full-content comparison remains in plan preflight and per-item validation. A poisoned-cache fixture confirms even plausible false digests cannot authorize removal. Storage rescans preserve the current directory when still present, with selection cleared. Saved-versus-fresh feedback appears alongside the completed snapshot; no startup/background scan or saved tree is presented as current.

### Fixed benchmark

macOS 27.0.1 / arm64 / local APFS, Swift debug build, disposable workspace fixture: 20 directories, 600 independent 64-byte files, 16 independent 8 MiB equal-content files (128 MiB), 637 nodes and 252 verified groups. No OS cache purge is performed; “cold” means first application analysis, not a cold disk. Timings include cache loading/commit for indexed scans. Event delivery is disabled in this deterministic benchmark so daemon timing cannot change hit eligibility; the separate native check uses real FSEvents. Run `LUMA_INDEX_BENCHMARK=1 bash Scripts/test.sh --filter AnalysisIndexTests.benchmark`.

| Run | Storage | Duplicate analysis | Reused evidence |
| --- | --- | --- | --- |
| Uncached first | 0.913 s | 9.709 s | None |
| Uncached repeat | 0.890 s | 9.661 s | None |
| Indexed first | 0.914 s | 10.108 s | No hashes reused |
| Indexed repeat | 0.895 s | 3.518 s | 616 metadata records; 1,232 partial/full hashes |

The target was identical groups/coverage, at least 90% eligible hash reuse and a measured repeated-duplicate improvement. Warm duplicate analysis is approximately 64% faster with 100% eligible hash hits. Initial indexed duplicate analysis costs approximately 4% more. Storage traversal is intentionally retained and shows no meaningful speed gain; finer subtree reuse is not claimed. The final package/visibility recheck preserves the same traversal policy. These are fixture/machine measurements, not universal responsiveness guarantees.

### Dependency review

The project specification explicitly approves GRDB for SQLite indexing. Reviewed its [7.11.1 release](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1), [versioned package manifest](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift), [MIT license](https://github.com/groue/GRDB.swift/blob/v7.11.1/LICENSE) and upstream migration/concurrency documentation. The release is dated 2026-06-18 and is the current upstream latest at review; Swift 6.1+ support fits this project. No transitive runtime package is introduced: GRDB uses system SQLite. Package.resolved pins revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`. Notices and its privacy resource bundle ship in Luma; packaging verifies that resource. Only the adapter imports GRDB in production; tests import it solely to build old/corrupt/poisoned fixture databases.

Native FSEvents lifecycle/invalidation follows [Apple’s guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html). Events remain advisory, not proof that unmentioned files are unchanged. The native check allows a bounded two-second daemon-delivery interval; immediate-change metadata fallback is covered separately.

### Validation

- The complete 242-test Swift suite passes (the opt-in benchmark is also run separately). Twelve new deterministic index fixtures cover migrations including future-schema rejection, corruption/fallback/clearing, metadata/event loss, root/catalog changes, hard links, access changes, cancellation, restart and poisoned-cache duplicate preflight.
- Native light/dark index checks pass real FSEvents invalidation after daemon delivery, changed-file results, warm scan equality, nested navigation continuity, no initial selection, real Settings presentation, cache clearing and preserved Activity/ignores/monitoring. Captures are synthetic and temporary. A full keyboard/VoiceOver session and actual external-volume unmount remain unverified; those limits do not substitute for the deterministic invalidation fixtures.
- Existing storage-browser native regressions pass 1,030-node fixtures in both appearances (1.629s/1.634s), including partial/provider/empty states, normal review and stale rejection. Existing scan/window/menu regressions pass 6,000-file fixtures (0.986s/0.985s; maximum sampled main-actor delay 0.080s/0.078s). These timings describe this machine/fixture only.

- Optimized app build, strict deep signature verification, and a local DMG round trip pass. The mounted app includes the pinned catalog, notices and GRDB privacy resource, with its executable matching the build. The image is ejected afterward; no public release/tag is created.
