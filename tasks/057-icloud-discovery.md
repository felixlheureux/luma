# 057 — Include iCloud files in storage discovery without downloads

Status: Planned  
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

- [ ] Available iCloud Drive and relocated Desktop/Documents observations appear automatically in Storage with local/online-only/unknown state and distinct logical/local sizes.
- [ ] Optimized and dataless fixtures never trigger content access or downloads, including through ancestor enumeration and image/icon APIs.
- [ ] Cloud observations cannot become ordinary Trash candidates; downloaded provider files retain provider identity rather than becoming unmanaged local files.
- [ ] Indexed stale results, offline roots and unavailable sizes remain explicitly partial/unknown, with no claimed local savings from cloud-only bytes.
- [ ] Record real macOS/iCloud integration results for online-only folders, downloaded files, offline mode and synced Desktop/Documents. Fixtures alone cannot establish actual iCloud support; missing access is recorded as an unresolved validation limit, not a pass.

## Validation and starting points

Use injected provider/metadata observations and read observers for non-materialization, state changes and alias deduplication. Update the storage native checker so cloud metadata visibility is expected while cleanup remains rejected. Run real integration only against disposable test files; never delete or request downloads of personal cloud data. Record exact tested macOS/provider behavior and coverage limits.

Start in `FilesystemAccess.swift`, `DescriptorFilesystem.swift`, 056's observation index and `StorageView.swift`. Keep adapters narrow rather than creating a general cloud-cleaning subsystem. Follow [README](README.md) for reference evidence.

## Primary platform evidence

Reviewed 2026-10-19: [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files) covers intermediate materialization and non-materializing I/O; [standard directories](https://developer.apple.com/documentation/foundation/filemanager/urls(for:in:)), [logical size](https://developer.apple.com/documentation/foundation/urlresourcekey/filesizekey), [allocated size](https://developer.apple.com/documentation/foundation/urlresourcekey/fileallocatedsizekey), [download state](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemdownloadingstatuskey), and [metadata queries](https://developer.apple.com/documentation/foundation/nsmetadataquery) define the observation inputs. [Ubiquity container lookup](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)) is app-container scoped; it is not a global user iCloud root locator.
