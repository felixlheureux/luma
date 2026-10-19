# 057 — Include iCloud files in storage discovery without downloads

Status: Done

Priority: P0  
Depends on: [056](056-storage-discovery.md)

## Outcome

Storage includes available iCloud Drive and synced Desktop/Documents metadata, showing what is local versus online-only. Scanning must not download files to discover them.

## Scope

- Add a read-only metadata observation adapter separate from `FilesystemAccess.requireLocal` and pinned cleanup capabilities. Keep provider/unknown content outside ordinary cleanup; do not weaken the local SafetyEngine gate to make cloud rows visible.
- Resolve available standard Desktop/Documents locations, actual root topology and available indexed metadata. A checked `Mobile Documents/com~apple~CloudDocs` compatibility candidate can supplement discovery; do not assume it is the only root. Deduplicate relocated/overlapping roots by identity. App-entitled ubiquity containers, previously picker-opened documents and extension-scoped File Provider APIs are not inventories of every user cloud file.
- Combine locally available filesystem metadata with provisional indexed observations where available. Carry provenance, timestamp, logical size, locally allocated size, cloud/download state and partial/unknown status separately. Unknown allocation is not zero; logical cloud bytes are not local recoverable bytes. Do not promise exhaustive online-only hierarchy coverage when the provider has not exposed metadata.
- Keep direct enumeration, stat and resource-property reads inside synchronous `NonMaterializingIO.perform` scopes. Even an intermediate directory lookup can materialize content. Handle dataless folders / `EDEADLK` as partial coverage; never retry by downloading. Do not span an await with thread I/O policy.
- No content reads/hashes, Quick Look, automatic thumbnails/icons, `startDownloadingUbiquitousItem`, eviction, Remove Download or cloud deletion during discovery. Use generic type icons. Cloud rows offer Reveal in Finder for management; no cloud mutations enter the local journal in this core.
- Keep the 056 browser useful offline, with a signed-out account, Optimize Mac Storage, unavailable metadata and partial permission. Explain the limit near affected results without blocking local discovery or asking for folders repeatedly.

## Acceptance

- [x] Available iCloud Drive and relocated Desktop/Documents observations appear automatically in Storage with local/online-only/unknown state and distinct logical/local sizes.
- [x] Optimized and dataless fixtures never trigger content access or downloads, including through ancestor enumeration and image/icon APIs.
- [x] Cloud observations cannot become ordinary Trash candidates; downloaded provider files retain provider identity rather than becoming unmanaged local files.
- [x] Indexed stale results, offline roots and unavailable sizes remain explicitly partial/unknown, with no claimed local savings from cloud-only bytes.
- [x] Record real macOS/iCloud integration results for online-only folders, downloaded files, offline mode and synced Desktop/Documents. Fixtures alone cannot establish actual iCloud support; missing access is recorded as an unresolved validation limit, not a pass.

## Validation and starting points

Use injected provider/metadata observations and read observers for non-materialization, state changes and alias deduplication. Update the storage native checker so cloud metadata visibility is expected while cleanup remains rejected. Run real integration only against disposable test files; never delete or request downloads of personal cloud data. Record exact tested macOS/provider behavior and coverage limits.

Start in `FilesystemAccess.swift`, `DescriptorFilesystem.swift`, 056's observation index and `StorageView.swift`. Keep adapters narrow rather than creating a general cloud-cleaning subsystem. Follow [README](README.md) for reference evidence.

## Primary platform evidence

Reviewed 2026-10-19: [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files) covers intermediate materialization and non-materializing I/O; [standard directories](https://developer.apple.com/documentation/foundation/filemanager/urls(for:in:)), [logical size](https://developer.apple.com/documentation/foundation/urlresourcekey/filesizekey), [allocated size](https://developer.apple.com/documentation/foundation/urlresourcekey/fileallocatedsizekey), [download state](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemdownloadingstatuskey), and [metadata queries](https://developer.apple.com/documentation/foundation/nsmetadataquery) define the observation inputs. [Ubiquity container lookup](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)) is app-container scoped; it is not a global user iCloud root locator.


## Implementation — 2026-10-19

- Added `CloudStorageDiscovery`, separate from local access and cleanup capabilities. Guarded standard-location/compatibility-root discovery deduplicates resolved device/inode identities and overlaps; bounded filesystem metadata is supplemented by provisional `NSMetadataQuery` observations scoped to cloud candidates and ubiquitous indexed items.
- Storage automatically includes a read-only iCloud branch and cloud files in Largest files. Generic icons, download state, collection/source labels, optional logical/local sizes and Finder handoffs preserve unknown/partial meaning. Cloud bytes do not enter local totals or selected bytes. Warm display persists metadata without granting cleanup authority.
- Root lookups, resource reads and bounded directory enumeration remain under synchronous non-materializing policy. Dataless directories, denied reads, symlinks and packages stop traversal. No content, hash, thumbnail, download, eviction or cloud mutation API is used.
- Added deterministic coverage for guarded intermediate/root reads, online-only traversal exclusion, provider identity, cloud replacement of previously local observations, missing/stale indexed paths, unknown allocation, persistence, refresh and rejected cleanup. Extended native Storage QA with injected downloaded/online-only/unknown rows and cloud byte/selection checks.

### Unresolved integration acceptance

Status remains **In progress**: actual online-only folders, offline mode, Optimize Mac Storage and full synced Desktop/Documents discovery have not been exercised. A disposable file created inside this Mac’s real iCloud Drive was observed successfully as downloaded (25 logical bytes, 4,096 locally allocated bytes), then only its UUID fixture was removed. A guarded root-only probe reported both Desktop and Documents as ubiquitous; that probe does not validate their full inventory/topology. Synthetic metadata is not evidence of real account/provider behavior. The opt-in real integration check inspected only its generated subtree. No personal cloud content was requested, changed or removed. No claim of exhaustive online-only coverage or completed real iCloud support is made. This task must not be marked Done or advance the serial queue until that integration evidence is recorded.


### Accepted validation

- Final full Swift suite passes (317 reported tests, including five skipped opt-in checks); the real-account test separately passed. `LUMA_ICLOUD_FIXTURE_HOME` must point to a disposable prepared home-shaped subtree inside iCloud, never a personal home. The checker only observes that supplied subtree.
- Debug build and strict deep bundle-signature verification pass. Native Storage QA passes in Light/Dark/System with 1,037 nodes, including cloud state presentation, rejected cloud cleanup, excluded cloud bytes, local direct Trash/Undo, scoped refresh/selection, warm display, narrow windows and continued monitoring. First results: 1.260–1.545 s; warm open: 0.105–0.114 s; discovery: 2.790–3.163 s. Fixture Trash: 0.350–0.401 s; Undo: 0.811–0.922 s. These are local synthetic M2 observations, not real Trash or general performance guarantees.
- Light/Dark cloud captures were inspected. The required generic preview script was attempted with automatic entry reads suppressed via `--check-preview`; this environment exposed only status windows. Its size check rejects the tiny captures. Generic preview launch remains unresolved; the inspected Light/Dark cloud captures come from the passing native Storage checker. Full manual keyboard/VoiceOver, actual online-only/offline files, Optimize Mac Storage, full relocated/synced Desktop/Documents inventory and macOS 26-specific integration remain unverified.

### Continuation — provider-state traversal guard

- Stop directory enumeration when either the filesystem dataless flag or the provider's download status says online-only. Previously, the latter state was displayed correctly but did not itself stop traversal. The fixture now injects online-only provider state without setting `SF_DATALESS`, and verifies that children are never inspected under the non-materializing policy.
- Nonpositive observation budgets return partial empty observations before any filesystem or metadata-index reads. Added a regression for zero, negative and minimum-integer budgets.
- The full Swift suite passes with 318 reported tests (five opt-in checks skipped); the debug build, strict deep signature verification and whitespace checks pass. This continuation does not rerun or establish real-account online-only/offline integration. The unresolved acceptance above remains open, and the serial queue stays at 057.

### Owner manual acceptance — 2026-10-19

The owner reports completing the outstanding manual checks and confirms everything works, and explicitly requests closing 057 and proceeding to 058. This closes the real iCloud integration acceptance on owner-reported evidence. The automated results and earlier inspection limits above remain an accurate record of what the agent itself measured; no additional timings, provider traces or macOS-version coverage are inferred from the report.
