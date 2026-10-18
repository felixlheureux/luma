# Early cache support matrix

Task 050, reviewed 2026-10-17. This batch adds fixed cache/log units; it does not make an entire Electron profile disposable. Existing 18 rules retain their scope. Four new rules bring the catalog to 22. Nothing is selected automatically.

## Enabled batch

The named app is **Visual Studio Code stable 1.142.0**, default macOS layout only. The [official stable update endpoint](https://update.code.visualstudio.com/api/update/darwin-arm64/stable/latest) reported release commit `6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1` during implementation. This value is pinned in the rule, rather than inferred from a folder called “Code.” Other versions/builds need a separate evidence update. There is no automatic remote version check in Luma.

Every rule checks a supported installed `Visual Studio Code.app` in the user's Applications directory or `/Applications`. Its pinned Info.plist must report the expected bundle identifier and version. Bounded product.json/package.json reads must agree on identifier, product name, release commit and version. A missing, unreadable, linked or changed installation does not authorize cleanup. These are layout/ownership signals, not a cryptographic signing attestation. The first verified supported installation provides the relationship; running instances and helpers are checked separately at execution.

All paths in this table are under `~/Library/Application Support/Code/`. They must be directories. Only the complete listed unit can be selected; its parents and descendants cannot borrow the rule's authority.

| Rule | Exact unit | Evidence and consequence |
| --- | --- | --- |
| `app.vscode.http-cache` | `Cache` | Electron documents Chromium cache subdirectories inside userData and sessionData. Network resources may need downloading again; offline access to those cached resources can be affected. Cookies, Local Storage and Service Worker data are outside this unit. |
| `app.vscode.gpu-cache` | `GPUCache` | Electron identifies this generated Chromium cache within userData. Graphics caches rebuild; first rendering may be slower. |
| `app.vscode.bytecode` | `CachedData` | VS Code's released bootstrap derives a per-commit code-cache directory here and creates it at startup. Its own cache cleaner removes older generated versions. The next launch can compile again and take longer. |
| `app.vscode.logs` | `logs` | VS Code derives timestamped session log directories here, creates them and implements log-session retention. Classified **Review first**: previous app/extension diagnostics are lost unless restored. New diagnostic events are new data, not recovery of old logs. Logs can contain private paths or other diagnostic content. |

Primary provenance:

- [Electron app paths](https://www.electronjs.org/docs/latest/api/app#appgetpathname): distinction between userData/sessionData, Chromium subdirectories and persistent state. This is not authorization to remove all sessionData.
- [VS Code default data-path implementation, release 1.142.0](https://github.com/microsoft/vscode/blob/1.142.0/src/vs/platform/environment/node/userDataPath.ts) and [Microsoft's macOS data-folder documentation](https://code.visualstudio.com/docs/setup/uninstall): default Code data root. Portable layouts, environment overrides and command-line custom paths are not followed.
- [Released bootstrap](https://github.com/microsoft/vscode/blob/1.142.0/src/mainImpl.ts): getCodeCachePath and startup directory creation.
- [Released environment service](https://github.com/microsoft/vscode/blob/1.142.0/src/vs/platform/environment/common/environmentService.ts): logsHome and its separation from User, backups, history and workspace data.
- [Released code-cache cleaner](https://github.com/microsoft/vscode/blob/1.142.0/src/vs/code/electron-utility/sharedProcess/contrib/codeCacheCleaner.ts) and [log cleaner](https://github.com/microsoft/vscode/blob/1.142.0/src/vs/code/electron-utility/sharedProcess/contrib/logsDataCleaner.ts): generated-cache and diagnostic retention lifecycles. Luma does not adopt their permanent-delete implementation or imply that their age policy is Luma's selection policy.

The current release's source and Electron's path contract provide path/lifecycle evidence. Synthetic installed-app fixtures independently verify discovery, boundaries and execution behavior; a real Electron restart or cache-performance benchmark was not run. Existing app data was not cleaned.

## Evaluated families remaining unavailable

| Family | Decision for this batch | Reason / safe boundary |
| --- | --- | --- |
| VS Code Insiders, Code OSS, VSCodium, older/future VS Code releases | Unsupported | Different product identities/layouts or unverified builds; stable metadata is not inherited. No recursive search for alternative installations or custom data roots. |
| Slack, Discord, Obsidian and other named Electron apps | Unsupported | Electron's generic path contract does not establish each vendor's storage overrides, supported release or specific ownership. Their profiles and offline content are not cache roots. Existing explicitly named leftover review is a separate feature. |
| Exact `Library/Containers/<owner>/Data/Library/Caches` leaves | Unsupported | Apple's [cache-directory contract](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) explains disposable cache semantics, but a path name alone does not establish arbitrary sandbox ownership. This batch has no supported external-container ownership attestation. Container and shared/group-container traversal is not added. |
| Shared/ambiguous app and group containers | Unsupported | No exclusive ownership proof; matching a bundle-like name cannot authorize a cache or log rule. |
| Broad `Library/Logs`, DiagnosticReports and system logs | Unsupported | Mixed owners, useful incident records and potential privacy content. Only the named VS Code log unit is added; existing npm/Simulator log rules stay bounded. |
| Additional Xcode application caches, Previews, DeviceSupport, device logs, archives | Unsupported beyond existing rules | [Apple's generated-file location guidance](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html) distinguishes DerivedData from archives, but does not establish a new bounded removal policy for all these families. DerivedData, SwiftPM and the existing Simulator caches/logs retain their current guards. No new archive, device, runtime or source deletion. |
| Darwin, App Store, shared stores, privileged/system caches | Unsupported | No independently established bounded policy; no helper or privilege escalation is added. |

Unsupported here is an explicit decision, not a claim that the data is unnecessary or that all these families were scanned. Only enabled rules appear in scan coverage. Task 031 handles deeper selection, task 008 external rule files, and task 005 broader application relationships.

## Safety, accounting and review

Scans stay read-only. Core execution rechecks exact path, current installed-product evidence, owner/helper activity, process evidence, provider access, ownership, volume and saved filesystem identity. Running VS Code/main helpers block cleanup. Inability to collect process evidence blocks it as well. Test-only task-local roots/activity snapshots isolate generated fixtures from the real installed/running apps; production never enables those overrides. Existing complete plans and the durable journal provide Trash, partial outcomes and verified Restore.

The scan records a transient inode/size index for successful units. Overall, category, app and selected-subset totals count hard links once within that subset, without reading the filesystem from a view. Each displayed group agrees with a plan for that group's units. Different groups/categories can share content and therefore need not sum to the global unique total; the UI states this. Final review recomputes its exact selected logical bytes. These are not promises about APFS allocation, clones, snapshots or physical savings.

After a cleanup attempt or Restore, the app invalidates generated findings, original coverage/category totals, selected generated IDs and completed generated/overview snapshots. A fresh scan is required. This includes stopped/partial outcomes and conservative invalidation after a rejected attempt; no stale results imply success. Individual journal records still describe completed moves and recovery.

## Catalog migration (task 008)

The same 22 supported rules now live in `Sources/LumaCore/Resources/CleanupRules.yaml`, with schema/catalog version, explicit English text, regeneration guidance, provenance and review dates. The installed-product version/commit checks and supported path boundaries above are unchanged. Xcode/SwiftPM and Homebrew guards formerly inferred from stable rule IDs are also explicit catalog fields. The loader requires the minimum path-specific guards and rejects unsupported scopes/profile leaves; runtime policy remains in Swift. No additional cache ecosystem is enabled by this migration. See CONTRIBUTING.md for validation and fixture instructions.
