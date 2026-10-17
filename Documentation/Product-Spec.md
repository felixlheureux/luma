# Open-Source macOS Maintenance Utility — Complete Product Specification

**Status:** Canonical full-product specification  
**Platform:** macOS  
**Implementation:** Native Swift / SwiftUI  
**License:** Open source  
**Product philosophy:** Transparent, conservative, local-first, explainable, reversible

---

## 1. Product Vision

Build the definitive open-source macOS maintenance application: a native utility that helps users understand where their storage and system resources are going, safely remove unnecessary data, uninstall applications completely, find duplicates and large files, monitor system health, and perform legitimate optimization and maintenance tasks.

The product should provide the useful parts of commercial macOS utilities such as CleanMyMac without:

- scare tactics;
- fake “health” claims;
- unnecessary privileged components;
- antivirus/security-suite scope;
- cloud-cleaner scope;
- opaque deletion rules;
- invasive telemetry;
- aggressive permanent deletion;
- claims that normal macOS behavior is inherently a problem.

The core promise is:

> **Show users what is consuming storage and resources, explain what can safely be changed, and make every destructive operation inspectable and reversible.**

---

# 2. Product Principles

## 2.1 Safety First

Deletion safety is the most important engineering requirement in the project.

The application must never treat “found on disk” as equivalent to “junk.”

Every cleanup candidate must have:

- a known source;
- a classification;
- an explanation;
- a confidence level where applicable;
- a safety level;
- an expected consequence of removal;
- a validated filesystem path;
- a clear user-visible size;
- an owning application or category when known.

No scanner may directly delete arbitrary paths.

All destructive actions pass through the central Safety Engine.

---

## 2.2 Trash by Default

Normal cleanup operations move files to the macOS Trash.

The application should avoid permanent deletion unless:

1. moving the item to Trash is technically impossible or inappropriate;
2. the action is explicitly initiated by the user;
3. the UI clearly explains the consequence.

The default behavior should maximize recoverability.

---

## 2.3 Explain Everything

Every result should be able to answer:

- What is this?
- Where is it?
- What created it?
- Why was it selected?
- How large is it?
- Is it generated data or user data?
- What will happen if it is removed?
- Can it be recreated automatically?
- How confident are we that it belongs to this application?
- Which rule or scanner classified it?

Power users should be able to inspect the exact rule and path.

---

## 2.4 No Fake Optimization

The app must not claim that normal macOS behavior is pathological.

Examples:

- high RAM utilization is not automatically bad;
- cached memory is not automatically wasted memory;
- old files are not automatically junk;
- caches do not automatically slow down a Mac;
- login items are not automatically harmful;
- CPU spikes are not automatically a problem.

Recommendations must be grounded in meaningful signals such as:

- sustained high memory pressure;
- large swap usage;
- low available disk space;
- a hung application;
- a background process with sustained high CPU use;
- unused applications with large footprints;
- very large generated developer artifacts;
- stale application leftovers;
- pending updates;
- unhealthy battery or disk conditions where measurable.

---

## 2.5 Local-First and Private

Scanning, classification, hashing, file analysis, duplicate detection, and photo similarity analysis should happen locally.

By default, the application must not transmit:

- filenames;
- file paths;
- hashes;
- application inventory;
- browser history;
- photo metadata;
- device inventory;
- storage contents;
- cleanup history.

Telemetry should default to **off / none**.

If crash reporting is ever added, it must be opt-in and must sanitize sensitive paths and metadata.

---

## 2.6 Native macOS Experience

The application should feel like a real Mac utility.

Use:

- Swift;
- SwiftUI;
- async/await;
- Foundation;
- native macOS APIs;
- native menus;
- native keyboard behavior;
- system accessibility APIs;
- standard document/file affordances.

Avoid:

- Electron;
- embedded web UIs for the core application;
- fake custom window chrome when native controls work;
- always-running heavy background processes.

---

# 3. Explicit Product Scope

The mature application contains these primary product areas:

```text
Overview / Smart Check

Clean

Optimizer

Applications

Storage

Duplicates

Privacy

System / Monitor

Menu Bar

Platform / Safety Infrastructure
```

---

# 4. Explicit Non-Goals

The project is **not** intended to become:

- antivirus software;
- real-time malware protection;
- EDR;
- VPN software;
- a password manager;
- a cloud cleaner;
- cloud backup software;
- remote device management;
- a “RAM booster” that lies about macOS memory behavior;
- a registry cleaner;
- a driver updater;
- a kernel-extension product;
- an always-running privileged daemon suite.

The following features are intentionally excluded from the canonical product scope:

- malware scanner;
- real-time malware monitoring;
- cloud cleanup;
- mandatory privileged XPC/helper architecture.

A privileged helper may only be reconsidered later for a specific feature with a demonstrated benefit. It must never become a foundational dependency merely because other Mac utility apps use one.

---

# 5. Main Navigation

Suggested top-level navigation:

```text
Overview
Clean
Optimizer
Applications
Storage
Duplicates
Privacy
System
```

Additional access points:

- global search;
- optional menu-bar companion;
- settings;
- history;
- ignore lists;
- diagnostics / power-user details.

---

# 6. Overview / Smart Check

The Overview is the main product surface.

It should provide useful information quickly rather than forcing users through one giant blocking scan.

Example:

```text
Macintosh HD

512 GB total
411 GB used
101 GB available

Potential safe cleanup       18.4 GB
Applications                 72.6 GB
Developer files              41.2 GB
Large files                  96.8 GB
Downloads                    13.4 GB

Memory pressure              Low
Swap                          1.1 GB
Battery health                94%
App updates                     4
```

Below the summary, surface actionable recommendations such as:

```text
12.4 GB of safe cleanup available

7 unused applications
8.1 GB total footprint

Xcode generated data
31.7 GB

Downloads older than 6 months
11.3 GB

3 startup items with sustained background activity

4 applications have updates
```

The Overview should populate progressively.

Fast scanners run first and display results while deeper analysis continues.

---

# 7. Smart Check / Full Check

The final app should support a combined system check.

This is not a fear-based “your Mac is in danger” scan.

It should combine relevant categories such as:

- safe cleanup;
- application updates;
- unused apps;
- storage pressure;
- memory pressure;
- background consumers;
- hung apps;
- developer junk;
- old large downloads;
- duplicate downloads;
- maintenance issues.

Example:

```text
System status

Storage       Good
Memory        Good
Battery       Good
Apps          4 updates
Startup       3 suggestions
Cleanup       18.4 GB available

[ Review Recommendations ]
[ Run Full Check ]
```

The app should avoid manufacturing an arbitrary 0–100 health score.

Use individually explainable statuses instead.

---

# 8. Clean

The Clean section handles generated, disposable, and safely reclaimable data.

Clean must remain conceptually separate from Storage:

> **Clean** tells users what the application can justify removing.

> **Storage** tells users where space is being used and lets the user decide.

---

# 9. Cleanup Safety Classes

Each cleanup item receives one of the following classifications.

## 9.1 Safe

Generated or disposable data that can be recreated.

Examples:

- application caches;
- browser caches;
- generated logs;
- Xcode DerivedData;
- known temporary downloads;
- stale package-manager caches;
- obsolete generated simulator caches.

These may be preselected when confidence is high.

---

## 9.2 Review

Likely removable but potentially contains state or preferences.

Examples:

- Application Support from an uninstalled app;
- preferences;
- archives;
- old device backups;
- browser site data;
- app state;
- abandoned containers.

These should normally require review.

---

## 9.3 User Data

Data intentionally created or stored by the user.

Examples:

- Documents;
- photos;
- videos;
- music;
- source code;
- project files;
- downloads;
- archives.

The app may surface these for manual review but must never label them “junk.”

---

# 10. User Cache Cleanup

Scan known user-level cache locations such as:

```text
~/Library/Caches
```

Results should be grouped by application.

Example:

```text
Safari            1.8 GB
Spotify           760 MB
Slack             540 MB
Xcode             420 MB
```

Each entry should expose:

- path;
- size;
- owning app;
- regeneration behavior;
- last modified date where useful;
- exact cleanup rule.

---

# 11. Application Logs

Scan recognized application log locations.

Features:

- group by application;
- show total size;
- show age distribution;
- allow file-level drill-down;
- avoid deleting active diagnostic data blindly;
- classify known generated logs as Safe;
- classify unknown logs conservatively.

---

# 12. Temporary Data

Identify deterministic temporary files generated by known applications.

The scanner must rely on explicit rules or strong platform conventions.

Unrestricted “temp-like filename” heuristics should not be considered sufficient for automatic cleanup.

---

# 13. Browser Cache Cleanup

Support major browsers independently.

Target browsers may include:

- Safari;
- Chrome;
- Chromium;
- Firefox;
- Brave;
- Edge;
- Arc;
- other Chromium-based browsers through extensible rules.

Potential Safe cleanup:

- browser cache;
- service worker caches where safe;
- website cache;
- crash reports;
- temporary download artifacts.

Privacy-sensitive categories must remain separate.

The Clean section must **not** silently remove:

- cookies;
- browsing history;
- sessions;
- passwords;
- website databases;
- local storage.

Those belong under Privacy.

---

# 14. Mail Attachments and Mail Caches

Where safely detectable, surface large locally cached mail attachments and generated mail data.

The app must distinguish between:

- locally cached copies;
- user-created files;
- mail database/index files;
- content that may be re-downloaded;
- content whose removal could disrupt Mail.

Potential destructive actions should be conservative.

Mail index rebuilding belongs under Optimizer / Maintenance.

---

# 15. Developer Cleanup

Developer machines can accumulate enormous amounts of generated data.

Developer cleanup should eventually be a first-class feature.

---

## 15.1 Xcode

Detect and categorize:

- DerivedData;
- simulator caches;
- simulator device data;
- unavailable simulators;
- old simulator runtimes where safe to remove;
- DeviceSupport;
- archives;
- documentation caches;
- Xcode caches;
- build products;
- crash/log artifacts.

Example:

```text
DerivedData                   14.2 GB   Safe
Unavailable simulators         8.7 GB   Safe
Archives                       6.4 GB   Review
Device Support                 4.1 GB   Review
Simulator devices             22.6 GB   Review
```

The application must clearly distinguish generated build data from potentially valuable archives.

---

## 15.2 Node.js / JavaScript

Potential cleanup:

- package-manager caches;
- stale package downloads;
- generated project output where explicitly recognized;
- old package-manager metadata.

Do not globally classify every `node_modules` directory as junk.

Project-generated data should be handled in Developer Projects.

---

## 15.3 Additional Developer Ecosystems

Potential later support:

- Homebrew;
- CocoaPods;
- Swift Package Manager caches;
- Gradle;
- Android;
- Docker;
- Python;
- pip;
- Poetry;
- uv;
- Rust/Cargo;
- Go;
- Ruby/Bundler;
- JetBrains IDEs;
- Flutter;
- .NET;
- Unity;
- Unreal Engine where practical.

Each ecosystem should have transparent rules and tests.

---

# 16. Trash

Show Trash usage rather than pretending Trash is mysterious “system junk.”

Actions:

```text
Review Trash
Empty Trash
```

Support internal and external volume Trash where macOS permissions allow.

The app should display how much space is already recoverable simply by emptying Trash.

---

# 17. Downloads Review

Downloads is not junk.

Provide a dedicated review interface.

Useful categories:

- large downloads;
- old downloads;
- disk images;
- installers;
- archives;
- duplicate downloads;
- browser downloads;
- Slack downloads;
- other source-attributed downloads when metadata allows.

Example:

```text
Downloads

Installers                 4.2 GB
Disk images                2.8 GB
Archives                   5.4 GB
Older than 1 year          7.8 GB
Duplicate downloads        1.1 GB
```

Nothing should be preselected merely because it is old.

---

# 18. Installer Leftovers

Detect installation artifacts such as:

- `.dmg`;
- `.pkg`;
- extracted installers;
- known installer caches;
- abandoned installer data.

The app should distinguish between:

- user-downloaded installers;
- system/application-generated installer caches;
- required application resources.

---

# 19. iPhone / iPad Backups

Detect local Apple device backups and related storage.

Display:

- device name where available;
- backup date;
- backup size;
- device identifier where appropriate;
- age;
- whether multiple backups exist.

These are user data and should always be Review, never Safe.

---

# 20. Universal Binary Cleanup

Where technically safe, inspect universal binaries and identify architecture slices unusable on the current Mac.

This feature should be conservative and optional.

Requirements:

- only modify supported binary formats;
- preserve code-signing integrity where possible;
- never silently rewrite application bundles;
- provide clear estimated savings;
- back out completely if modification would invalidate the application.

If safe in-place binary thinning cannot be guaranteed, this feature should be omitted rather than implemented dangerously.

---

# 21. Unused Language Resources

Potentially detect application localization resources that are not needed by the user.

This should only exist if it can be implemented safely without breaking app signatures, updates, or runtime behavior.

Like universal binary cleanup, this is optional and must be conservative.

---

# 22. Optimizer

Optimizer is a first-class product area.

Its job is to:

- explain resource pressure;
- expose heavy consumers;
- help users close or disable unnecessary activity;
- surface legitimate maintenance operations;
- reclaim resources where macOS provides a safe mechanism;
- avoid misleading “boost” claims.

---

# 23. Memory Optimizer

Display meaningful memory information:

```text
Memory

Used                  23.8 GB
Available              8.2 GB
Cached                 5.4 GB
Swap                   1.1 GB
Pressure               Low

Top consumers
Chrome                  4.8 GB
Xcode                   3.1 GB
Docker                  2.7 GB
Slack                   1.4 GB
```

Primary metric: **memory pressure**, not merely “free RAM.”

Possible actions:

```text
[ Optimize Memory ]
[ Review Heavy Consumers ]
```

The optimization action may:

- request safe reclaimable-memory behavior where supported;
- surface applications worth quitting;
- identify large inactive consumers;
- explain when no action is necessary.

The app should explicitly avoid implying that low “free RAM” is automatically bad.

---

# 24. Swap Monitoring

Show:

- current swap usage;
- swap trend;
- whether swap is increasing significantly;
- relationship to memory pressure.

Example:

```text
Swap                 6.3 GB
Trend                 Increasing
Memory pressure       High
```

Provide explanation:

> macOS uses swap normally, but sustained high memory pressure combined with rapidly increasing swap can indicate that active applications need more memory than is available.

---

# 25. Heavy RAM Consumers

List applications and processes with significant memory use.

Show:

- app name;
- icon where possible;
- RAM;
- compressed memory where available;
- process count;
- activity trend.

Actions:

- activate app;
- quit;
- force quit where appropriate;
- inspect processes.

System-critical processes must not be offered for casual termination.

---

# 26. Heavy CPU Consumers

Display sustained CPU usage.

Example:

```text
Docker Desktop        88%
Chrome                43%
Xcode                 31%
WindowServer           9%
```

Distinguish:

- momentary spike;
- sustained load;
- foreground expected load;
- long-running background load.

Actions:

- activate app;
- quit user application;
- relaunch user application;
- inspect process details.

---

# 27. Hung Applications

Detect applications that are not responding.

Example:

```text
Adobe Photoshop
Not responding for 2m 13s

[ Force Quit ]
```

Avoid declaring a process hung based on a single short delay.

---

# 28. Login Items

Display user login items.

Show:

- application;
- developer;
- enabled state;
- startup mechanism where known;
- actual recent resource impact when measurable.

Actions:

```text
Enable
Disable
Reveal application
Open application
```

Do not invent arbitrary “High Impact” labels without evidence.

If impact scoring is used, derive it from measurements such as:

- startup CPU duration;
- memory footprint;
- background lifetime.

---

# 29. Background Items

Show user-level background components such as:

- LaunchAgents;
- application helpers;
- scheduled user services;
- background applications.

For each:

- parent application;
- executable path;
- current state;
- current resource use;
- launch mechanism;
- whether macOS settings can disable it.

Actions must respect macOS security restrictions.

Unknown items should be described as unknown, not suspicious.

---

# 30. Purgeable Storage

Display macOS purgeable/reclaimable storage separately from normal files.

Example:

```text
Purgeable storage
12.8 GB potentially reclaimable
```

If the system exposes a safe supported mechanism, provide:

```text
[ Reclaim Space ]
```

The app must not imply that all purgeable storage must be removed.

---

# 31. Time Machine Local Snapshots

Detect local Time Machine snapshots where accessible.

Show:

- snapshot count;
- estimated storage use;
- age;
- whether macOS may reclaim them automatically.

Potential action:

```text
Thin Local Snapshots
```

This should explain that macOS normally manages snapshots automatically.

---

# 32. Maintenance

Provide a curated set of legitimate maintenance actions.

Avoid exposing dozens of shell commands merely to make the app appear powerful.

Potential tasks:

- flush DNS cache;
- reindex Spotlight;
- rebuild/reindex Apple Mail data where appropriate;
- run supported periodic maintenance tasks;
- thin Time Machine snapshots;
- clear recognized stale generated caches;
- trigger other documented macOS maintenance operations.

Every task must explain:

- why someone would run it;
- what it changes;
- expected side effects;
- whether temporary CPU/disk usage will increase.

---

# 33. Flush DNS Cache

Use case:

- DNS changes not resolving correctly;
- stale domain resolution;
- troubleshooting.

UI:

```text
DNS Cache

Useful if:
• a domain recently changed servers
• websites resolve incorrectly
• you're troubleshooting DNS

[ Flush DNS Cache ]
```

Do not market this as a generic speed booster.

---

# 34. Reindex Spotlight

UI:

```text
Spotlight Index

Rebuild the Spotlight search index.

Useful when:
• known files are missing from search
• Spotlight results appear incorrect

Indexing may temporarily use significant CPU and disk activity.

[ Reindex Spotlight ]
```

---

# 35. Reindex / Rebuild Mail Search Data

UI:

```text
Apple Mail

Rebuild Mail search/index data.

Useful when:
• search misses known messages
• results are incomplete
• Mail search behaves incorrectly

[ Reindex Mail ]
```

The exact implementation must be compatible with the current macOS version.

---

# 36. Applications

Applications provides inventory, footprint analysis, uninstall, reset, leftovers, and updates.

---

# 37. Installed Application Inventory

Display installed user-visible applications.

For each:

- icon;
- name;
- developer;
- version;
- path;
- bundle identifier;
- app size;
- related-data size;
- total footprint;
- last used date where reliably available;
- installation date where available;
- update status.

Sorting:

- name;
- app size;
- total footprint;
- last used;
- installation date;
- update status.

---

# 38. Full Application Footprint

An application’s true footprint includes more than the `.app`.

Example:

```text
Spotify

Application
/Applications/Spotify.app
420 MB

Application Support
~/Library/Application Support/Spotify
2.1 GB

Cache
~/Library/Caches/com.spotify.client
680 MB

Preferences
~/Library/Preferences/com.spotify.client.plist
24 KB

Saved State
...
```

Show totals:

```text
Application              420 MB
Generated data            680 MB
User/application data     2.1 GB
Total footprint           3.2 GB
```

---

# 39. Application Uninstaller

Selecting an application should trigger related-file discovery.

Uninstall workflow:

```text
Select app
   ↓
Discover related files
   ↓
Classify relationships
   ↓
Show full footprint
   ↓
User reviews selections
   ↓
Safety Engine validates
   ↓
Move app + selected data to Trash
```

The app should never remove low-confidence related files automatically.

---

# 40. Related File Detection

Use multiple signals.

## Bundle Identifier

Example:

```text
com.spotify.client
```

Match against known macOS application-data locations.

---

## Application Name

Use strong normalized name matches only in appropriate locations.

Avoid fuzzy matching unrelated folders globally.

---

## Bundle Metadata

Relevant metadata may include:

- `CFBundleIdentifier`;
- `CFBundleName`;
- `CFBundleDisplayName`;
- `CFBundleExecutable`;
- team/developer identifiers;
- URL schemes;
- helper bundle identifiers.

---

## Rules Database

Maintain explicit app cleanup rules.

Conceptual example:

```yaml
application: Spotify

bundleIdentifiers:
  - com.spotify.client

paths:
  - ~/Library/Application Support/Spotify

generatedPaths:
  - ~/Library/Caches/com.spotify.client
```

Rules should augment deterministic detection rather than bypass safety.

---

# 41. Relationship Confidence

Every related file receives a confidence classification.

```text
Certain
Very Likely
Possible
Unknown
```

Automatic selection policy:

- Certain: may be preselected;
- Very Likely: may be preselected depending on safety classification;
- Possible: never preselected;
- Unknown: informational only.

---

# 42. Application Reset

Allow resetting an app without removing the application bundle.

Possible reset targets:

- preferences;
- caches;
- saved application state;
- known generated configuration state;
- selected Application Support data.

Because Application Support may contain user data, the UI must distinguish:

```text
Generated settings
Cached data
Account/session state
Potential user data
```

The user chooses exactly what is reset.

---

# 43. Leftover Application Data

Detect files belonging to applications no longer installed.

Example:

```text
Adobe Lightroom
Application no longer installed
Related files: 4.2 GB

Discord
Application no longer installed
Related files: 780 MB
```

Requirements:

- high-confidence ownership;
- app-not-installed verification;
- explain exact ownership evidence;
- manual review for uncertain data.

---

# 44. Unused Applications

Surface applications not used for a configurable period.

Examples:

```text
Not used in 6 months
Not used in 1 year
Never opened
```

Show:

- last-used date;
- total footprint;
- related data size;
- update status;
- whether the app is currently running.

Unused does **not** mean junk.

The feature is a decision aid.

---

# 45. Application Updater

Identify available updates.

Potential update sources:

- Sparkle feeds;
- Homebrew Cask;
- application-provided update metadata;
- official vendor feeds;
- curated open update rules.

Security requirements:

- never install unsigned arbitrary downloads;
- verify signatures where possible;
- prefer launching the application’s native updater when appropriate;
- expose source of update information;
- never silently replace apps based on untrusted metadata.

---

# 46. Storage

Storage answers:

> **Where did my disk space go?**

It is a filesystem analysis and navigation tool, not a junk classifier.

---

# 47. Volumes and Scan Targets

Support:

- internal system volume;
- external disks;
- mounted removable volumes;
- arbitrary user-selected folders.

External volumes should show:

- filesystem;
- total size;
- used;
- free;
- mount point;
- health where available;
- Trash usage where accessible.

---

# 48. Hierarchical Storage Browser

Example:

```text
Users                  283 GB
Applications            91 GB
Library                 62 GB
System                  31 GB
Other                   18 GB
```

Drill down:

```text
Users
└── felix
    ├── Library          97 GB
    ├── Movies           72 GB
    ├── Downloads        34 GB
    ├── Documents        29 GB
    └── Pictures         21 GB
```

Features:

- sort by size;
- sort by name;
- filter hidden files;
- reveal in Finder;
- copy path;
- open;
- inspect metadata;
- move manually selected items to Trash.

---

# 49. Disk Treemap

Provide a visual treemap synchronized with the hierarchy view.

Selecting an item shows:

- name;
- path;
- size;
- type;
- creation date;
- modification date;
- last access date where reliable;
- owning app/category if known.

Actions:

```text
Reveal in Finder
Open
Move to Trash
Copy Path
Get Info
```

Treemap must not be the only way to access storage information.

---

# 50. Large Files

Dedicated view for large files.

Default size filters:

```text
> 100 MB
> 500 MB
> 1 GB
> 5 GB
Custom
```

Group by:

- videos;
- archives;
- disk images;
- applications;
- developer files;
- documents;
- downloads;
- other.

Allow sorting by:

- size;
- modified date;
- path;
- type.

---

# 51. Old Files

Expose files not modified for long periods.

Example filters:

```text
Not modified in 1 year
Not modified in 2 years
Not modified in 5 years
```

Age is informational only.

Old files are never automatically classified as junk.

---

# 52. Developer Projects

Detect software projects and distinguish source code from regenerable data.

Example:

```text
greatshout/

Source                  182 MB
node_modules            1.7 GB
Build output            420 MB
Caches                   86 MB

Potentially regenerable 2.2 GB
```

Supported ecosystems may include:

- Node.js;
- Rust;
- Go;
- Gradle;
- Xcode;
- Python;
- Ruby;
- Flutter;
- .NET;
- Android.

Requirements:

- identify project roots;
- understand ecosystem-specific generated directories;
- never classify source code as cleanup;
- show regeneration consequences;
- allow project-by-project cleanup.

---

# 53. Duplicates

Duplicate detection must verify content.

Do not rely only on:

- filenames;
- timestamps;
- extensions.

Pipeline:

```text
File size
   ↓
Candidate groups
   ↓
Partial content hash
   ↓
Full cryptographic hash
   ↓
Verified duplicates
```

This avoids hashing every file unnecessarily.

---

# 54. Duplicate Groups

Example:

```text
IMG_4827.jpg

~/Pictures/2025/IMG_4827.jpg
~/Downloads/IMG_4827.jpg
~/Desktop/backup/IMG_4827.jpg

3 copies
14.2 MB each
28.4 MB recoverable
```

Actions:

```text
Keep newest
Keep oldest
Keep selected folder
Select manually
Reveal in Finder
```

No automatic deletion without review.

---

# 55. Duplicate Downloads

Provide a focused view of duplicate content in Downloads.

Useful because this category often has low decision cost.

Example:

```text
Chrome.dmg
Chrome (1).dmg
Chrome (2).dmg

3 identical files
612 MB recoverable
```

Still require user review.

---

# 56. Similar Photos

Similar photos are distinct from exact duplicates.

Use local perceptual/image-analysis techniques.

Potential groups:

- burst photos;
- near-identical photos;
- resized copies;
- lightly edited copies;
- screenshots with similar content.

Requirements:

- local-only processing;
- never automatically delete;
- visually compare candidates;
- preserve metadata;
- make best-copy suggestions explainable where possible.

---

# 57. Privacy

Privacy cleanup must be explicitly separated from ordinary cache cleanup because deleting privacy data can sign users out, remove history, or destroy state.

---

# 58. Browser Privacy

For supported browsers, expose:

- history;
- cookies;
- site storage;
- downloads history;
- sessions;
- website data;
- local storage where safe to manage.

Default selection: **none**.

Warnings should explain consequences.

Examples:

> Removing cookies may sign you out of websites.

> Removing site storage may delete offline website data and preferences.

Never touch saved passwords.

---

# 59. Recent Activity / Recent Items

Where supported and safe, expose macOS/application recent-item lists.

This should be transparent and opt-in.

Avoid claiming that recent-item metadata is dangerous.

---

# 60. Application Permissions Viewer

Provide a human-readable overview of application permissions visible through supported macOS mechanisms.

Examples:

- Camera;
- Microphone;
- Location;
- Screen Recording;
- Accessibility;
- Full Disk Access;
- Automation;
- Notifications.

The app should deep-link to the relevant System Settings page where appropriate.

It must not attempt to bypass or rewrite macOS privacy protections.

---

# 61. System / Monitor

The System section provides live resource monitoring and system diagnostics.

It should be useful independently from the cleanup features.

---

# 62. CPU Monitor

Display:

- total CPU utilization;
- user utilization;
- system utilization;
- per-process CPU;
- usage history;
- uptime;
- thermal state;
- CPU temperature when a reliable supported mechanism exists.

Example:

```text
CPU

Usage                  34%
System                   8%
User                    26%
Thermal state          Normal
Uptime                 6d 14h

Top consumers
Chrome                  28%
Xcode                   17%
WindowServer             9%
```

---

# 63. Memory Monitor

Display:

- physical memory;
- used memory;
- available memory;
- cached memory where meaningful;
- compressed memory;
- swap;
- memory pressure;
- top consumers;
- usage history.

Memory pressure should be visually prioritized.

---

# 64. Battery

For portable Macs, display:

- charge level;
- battery condition;
- maximum capacity / health where available;
- cycle count;
- charging state;
- estimated time remaining where reliable;
- battery temperature if reliably available;
- high-energy applications.

Example:

```text
Battery

Charge                 71%
Health                 94%
Cycles                 218
Condition              Normal

High energy use
Chrome
Docker Desktop
Slack
```

Actions may allow quitting user applications.

---

# 65. Disk Health

Display storage condition where macOS exposes reliable information.

Potential fields:

```text
512 GB SSD
184 GB available

SMART status          Healthy
Free space             36%
Purgeable              14.8 GB
```

Only show temperature/SMART details when obtained through reliable supported mechanisms.

Do not fabricate health metrics.

---

# 66. Disk Space Monitoring

Warn when internal or external volumes cross user-configurable thresholds.

Example:

```text
Macintosh HD
38 GB free
Low-space threshold: 40 GB
```

Suggested actions:

- open Storage;
- review large files;
- review safe cleanup;
- review Trash.

---

# 67. Network Monitor

Display:

- current upload rate;
- current download rate;
- interface;
- connection type;
- local IP where appropriate;
- cumulative session usage;
- optional speed test.

Example:

```text
Wi-Fi

Download              14.8 MB/s
Upload                  2.1 MB/s

Session
Downloaded            18.3 GB
Uploaded                2.1 GB
```

Avoid background network measurement that materially impacts battery.

---

# 68. Thermals

Where supported, display:

- macOS thermal state;
- CPU/system temperature when reliable;
- sustained thermal pressure;
- fan information where reliably available without fragile private APIs.

Prefer Apple-supported thermal-state APIs over undocumented sensor hacks.

---

# 69. Connected Devices

Optional mature feature.

Display connected peripherals and devices where macOS exposes information safely.

Examples:

```text
AirPods Pro            18%
Magic Mouse            64%
iPhone                 Connected
Samsung T7             114 GB free
```

Potential alerts:

- low accessory battery;
- low external-drive space;
- disconnected storage during long scan.

This is not core cleanup functionality but is useful in the mature menu-bar/system experience.

---

# 70. Menu-Bar Companion

Optional.

The menu-bar app should provide lightweight live visibility without becoming a heavy daemon.

Possible summary:

```text
Mac

Memory        25 / 32 GB
Pressure      Medium

CPU           28%
Thermal       Normal

Disk          184 GB free

Battery       73%
Health        94%

Network       ↓ 12 MB/s
              ↑  1 MB/s
```

Quick actions:

- open main app;
- review memory consumers;
- optimize memory;
- review CPU consumers;
- review storage;
- open cleanup;
- quit monitor.

Users must be able to disable the menu-bar companion completely.

---

# 71. Recommendations and Alerts

The mature app may provide local recommendations for:

- low disk space;
- sustained high memory pressure;
- large swap growth;
- hung applications;
- sustained high CPU consumers;
- high energy use;
- low accessory battery;
- low external-drive space;
- old unused apps;
- pending updates;
- large Trash size;
- very large generated developer data.

Recommendations must be actionable and explainable.

No fear-based wording.

---

# 72. Ignore Lists

Users should be able to permanently exclude:

- files;
- folders;
- applications;
- cleanup rules;
- volumes;
- duplicate groups;
- developer projects.

Examples:

```text
Always ignore this folder
Ignore this application’s cache
Never suggest uninstalling this app
Ignore this volume
```

Ignore rules should be visible and reversible in Settings.

---

# 73. Global Search / My Tools

Provide global search across the app’s indexed results.

Example query:

```text
spotify
```

Results:

```text
Spotify.app
Application • 420 MB

Spotify Application Support
Application Data • 2.1 GB

Spotify Cache
Safe cleanup • 680 MB

Spotify Update
Version 2.x available
```

Another query:

```text
xcode
```

Could return:

```text
Xcode.app
14.7 GB

DerivedData
18.2 GB

Simulator Data
22.1 GB

Archives
6.4 GB
```

Also provide a searchable My Tools / command launcher.

---

# 74. Favorite Tools

Users may favorite frequent tools.

Examples:

- Clean Xcode data;
- Large Files;
- Duplicates;
- Memory Monitor;
- App Uninstaller;
- Flush DNS;
- Spotlight Reindex.

Favorites can appear on Overview or in the menu-bar app.

---

# 75. Scan History

Store local summaries of past scans.

Useful history:

- scan date;
- categories scanned;
- total potential cleanup;
- storage snapshot;
- app count;
- duplicate count.

Avoid retaining full file inventories forever unless required for a feature.

---

# 76. Cleanup History

Store local records of destructive operations.

Example:

```text
August 20, 2026

Chrome caches
2.4 GB
Moved to Trash

Xcode DerivedData
18.1 GB
Moved to Trash

Spotify
Application + selected leftovers
3.2 GB
Moved to Trash
```

Actions:

```text
Show in Trash
View details
```

---

# 77. Core Architecture

Suggested stack:

```text
Swift
SwiftUI
async/await
Foundation
FileManager
SQLite where useful
Apple-native frameworks
```

Suggested source structure:

```text
App/
    AppEntry
    Navigation
    DesignSystem
    Settings

Core/
    Filesystem
    Scanning
    Cleanup
    Safety
    Rules
    Storage
    Database
    Permissions
    Logging
    ProcessMonitoring

Features/
    Overview/
    Clean/
    Optimizer/
    Applications/
    Uninstaller/
    Storage/
    Duplicates/
    SimilarPhotos/
    Privacy/
    System/
    Monitor/
    MenuBar/

Rules/
    Applications/
    Browsers/
    Developer/
    Cleanup/
    Protected/

Tests/
    Core/
    Rules/
    Integration/
    Fixtures/
    Performance/
```

---

# 78. Scanner Architecture

Do not build one giant scanner.

Each feature implements a common scanning contract.

Conceptually:

```swift
protocol Scanner {
    var id: ScannerID { get }
    func scan() async throws -> ScanResult
}
```

Examples:

- CacheScanner;
- LogScanner;
- XcodeScanner;
- ApplicationScanner;
- LeftoverScanner;
- LargeFileScanner;
- DuplicateScanner;
- BrowserScanner;
- DeviceBackupScanner;
- DeveloperProjectScanner.

Scanners should be independently testable.

---

# 79. Common Cleanup Model

Every removable candidate should eventually map to a common model.

Conceptually:

```swift
struct CleanupItem {
    let id: CleanupItemID
    let category: CleanupCategory
    let path: URL
    let size: Int64
    let owner: ItemOwner?
    let explanation: String
    let safetyLevel: SafetyLevel
    let confidence: Confidence
    let regenerationType: RegenerationType
    let scannerID: ScannerID
    let ruleID: RuleID?
}
```

No feature should bypass this model for arbitrary deletion.

---

# 80. Safety Engine

All destructive actions pass through one central safety component.

```text
Scanner
   ↓
CleanupItem
   ↓
SafetyEngine
   ↓
User review
   ↓
Final validation
   ↓
Trash
```

SafetyEngine responsibilities:

- protected path validation;
- canonical path validation;
- symlink validation;
- hard-link awareness where relevant;
- mount/volume validation;
- user-data protection;
- application ownership validation;
- stale scan detection;
- race-condition mitigation;
- destination validation;
- permission validation;
- ignore-list enforcement.

---

# 81. Protected Paths

Maintain a hardcoded core of protected locations.

Examples conceptually include:

```text
/
~/Documents
~/Desktop
~/Pictures
~/Movies
~/Music
system-critical directories
unknown mounted volumes
```

Specific files inside user locations may still be manually selected in Storage.

Automated cleanup scanners may not generically classify these locations as junk.

---

# 82. Symlink Safety

Never blindly follow symlinks during deletion.

A malicious layout such as:

```text
safe-looking-cache/
    -> ~/Documents
```

must never allow user data deletion.

Requirements:

- resolve canonical path;
- validate path boundaries;
- validate immediately before removal;
- avoid recursive traversal across unsafe symlinks;
- test malicious symlink fixtures.

---

# 83. Race Safety

Files can change between scan and deletion.

Before moving an item to Trash:

- re-check existence;
- re-check canonical path;
- re-check file identity where possible;
- re-check owning volume;
- re-check symlink status;
- re-check rule assumptions.

If meaningful properties changed, invalidate the cleanup item and require a rescan/review.

---

# 84. Rules Repository

Cleanup knowledge should be separated from Swift application logic where practical.

Suggested structure:

```text
Rules/
├── Applications/
├── Browsers/
├── Developer/
├── Caches/
└── Protected/
```

Benefits:

- easier community contributions;
- easier testing;
- easier review;
- transparent behavior;
- versioned cleanup knowledge.

---

# 85. Rules Validation

Every rule should pass automated validation.

Examples:

```text
Rule cannot target a protected path.
Rule cannot contain unrestricted recursive globs.
Rule must declare safety classification.
Rule must include an explanation.
Rule must identify ownership when applicable.
Rule must declare regeneration expectations.
```

Risky rule changes should fail CI.

---

# 86. Community Contribution Model

Rule contributions should be easier than changing Swift code.

Ideal contribution examples:

- add application leftover mapping;
- add new browser cache locations;
- add new developer-tool caches;
- update paths for a new macOS version;
- add protected-path regression case.

The project should document how contributors can verify rules locally.

---

# 87. Local Database

Use SQLite only where it materially improves the product.

Potential data:

- application inventory;
- scan summaries;
- cleanup history;
- ignore lists;
- rule version;
- storage index;
- file metadata cache;
- duplicate hash cache;
- user preferences.

Avoid building a permanent replacement for Spotlight.

---

# 88. Filesystem Indexing

For storage analysis and duplicate scanning, maintain a temporary or incremental index.

Possible fields:

```text
path
file identifier / inode where useful
size
modified time
file type
volume
hash status
partial hash
full hash
```

Only hash files when necessary.

---

# 89. Scan Scheduling and Priorities

Fast scanners run first.

Suggested order:

```text
1. Known safe cleanup paths
2. Application inventory
3. Developer cleanup
4. Startup/background inventory
5. Large directory calculations
6. Storage indexing
7. Duplicate hashing
8. Similar-photo analysis
```

The UI should stream results incrementally.

Example:

```text
Scanning…

Caches                4.2 GB
Xcode                18.7 GB
Logs                   890 MB
Applications           scanning…
Storage                scanning…
```

---

# 90. Performance Requirements

The UI must remain responsive during scanning.

Requirements:

- async/await;
- bounded concurrency;
- cancellation;
- progress reporting;
- incremental results;
- avoid reading file contents unless required;
- hash only duplicate candidates;
- cache expensive metadata;
- respect battery/thermal state for heavy analysis;
- pause/deprioritize deep analysis when system pressure is high.

Large scans should be cancellable without leaving inconsistent state.

---

# 91. Permissions Strategy

Request permissions only when needed.

Do not request everything on first launch.

If Full Disk Access improves a feature, explain it narrowly:

```text
Full Disk Access allows the app to analyze additional application data.

You can continue without granting it.
```

The app should remain useful without Full Disk Access.

---

# 92. No Foundational Privileged Helper

The architecture intentionally avoids requiring:

- root daemon;
- privileged XPC helper;
- kernel extension;
- system extension.

If a particular mature feature cannot be implemented safely without elevation, evaluate that feature independently.

Do not make privilege escalation part of the basic app lifecycle.

---

# 93. Security Requirements

Because the app manipulates sensitive filesystem data:

- no arbitrary shell execution;
- no untrusted shell interpolation;
- minimize shell use entirely;
- canonical path validation;
- symlink protection;
- strict deletion APIs;
- signed releases;
- notarized releases;
- dependency minimization;
- rule validation;
- malicious fixture tests;
- fuzz/property testing for path handling;
- secure update verification.

---

# 94. Testing Philosophy

Deletion safety receives more testing effort than presentation code.

---

## 94.1 Unit Tests

Prioritize:

- path normalization;
- protected-path checks;
- rule matching;
- safety classification;
- bundle matching;
- application relationship confidence;
- duplicate detection;
- hash logic;
- size calculations;
- ignore-list behavior;
- symlink handling;
- scan invalidation;
- updater metadata verification.

---

## 94.2 Integration Tests

Use synthetic filesystem fixtures resembling real macOS layouts.

Example:

```text
FakeHome/
├── Library/
│   ├── Caches/
│   ├── Application Support/
│   ├── Preferences/
│   ├── Containers/
│   └── Logs/
├── Documents/
├── Downloads/
├── Pictures/
├── Developer/
└── Applications/
```

Verify exactly which paths scanners select and reject.

---

## 94.3 Golden Safety Tests

Maintain permanent regression tests for dangerous cases.

Examples:

```text
Scanner must never select ~/Documents recursively.

Symlink from a cache directory into Documents must never be followed.

Uninstaller must not delete data belonging to a similarly named unrelated app.

Unknown Application Support folders must not be classified as Safe automatically.

Interrupted scans must not create executable cleanup plans.

A path that changes after scan must be revalidated.

Ignore rules must always override suggestions.

External-volume boundaries must not be crossed unexpectedly.
```

Any regression blocks release.

---

# 95. UX and Visual Design

The interface should feel:

- calm;
- native;
- fast;
- precise;
- trustworthy;
- dense enough for power users;
- approachable for normal users.

Avoid:

- warning-red dashboards by default;
- fake urgency;
- “Your Mac is at risk!”;
- animated garbage gimmicks;
- meaningless health scores;
- exaggerated “boost” language.

---

# 96. Main Cleanup Interaction

Desired flow:

```text
Overview

18.4 GB potential cleanup
        ↓
Review
        ↓
Safe cleanup
        ↓
Categories
        ↓
Individual items if desired
        ↓
Move 16.8 GB to Trash
```

Users should be able to inspect as deeply as they want.

---

# 97. Power-User Mode

Advanced users should be able to see:

- full path;
- scanner ID;
- rule ID;
- confidence;
- safety level;
- file metadata;
- ownership evidence;
- regeneration behavior;
- canonical path;
- exclusion reason.

Example:

```text
Classification: Safe
Rule: developer.xcode.derived-data

Matched path:
~/Library/Developer/Xcode/DerivedData

Reason:
Xcode-generated compilation output.

Regeneration:
Automatically recreated on the next build.
```

This transparency should be a major open-source differentiator.

---

# 98. Accessibility

Support:

- VoiceOver;
- complete keyboard navigation;
- Increase Contrast;
- Reduce Motion;
- system text scaling where applicable;
- non-visual alternatives to treemaps/charts;
- descriptive labels for resource graphs.

---

# 99. Localization

Architecture should support localization from the beginning.

Initial shipping language may be English-only.

Rule explanations should be localizable separately from matching logic.

---

# 100. Distribution and Updates

Potential distribution:

- GitHub Releases;
- Homebrew Cask;
- direct signed updater.

Requirements:

- Developer ID signed;
- notarized;
- cryptographically verified updates;
- rollback-safe update mechanism;
- published checksums/signatures.

Mac App Store distribution should be considered separately because sandbox restrictions may conflict with filesystem-analysis functionality.

---

# 101. Telemetry

Default:

```text
None
```

If optional crash reporting is introduced:

- opt-in;
- scrub paths;
- scrub filenames;
- never transmit file hashes;
- never transmit browser data;
- never transmit app inventory without explicit consent.

---

# 102. Canonical Mature Feature Tree

```text
OPEN-SOURCE MACOS MAINTENANCE APP
│
├── Overview / Smart Check
│   ├── Storage summary
│   ├── Safe cleanup summary
│   ├── Memory pressure
│   ├── App updates
│   ├── Unused apps
│   ├── Developer storage
│   ├── Recommendations
│   └── Full Check
│
├── Clean
│   ├── User caches
│   ├── Application logs
│   ├── Temporary files
│   ├── Browser caches
│   ├── Mail attachments/caches
│   ├── Developer cleanup
│   │   ├── Xcode
│   │   ├── Homebrew
│   │   ├── Node/package managers
│   │   ├── Android/Gradle
│   │   ├── Docker
│   │   ├── Python
│   │   ├── Rust
│   │   └── Other ecosystems
│   ├── Installer leftovers
│   ├── iOS/iPadOS backups
│   ├── Universal binaries (if safe)
│   ├── Unused languages (if safe)
│   ├── Downloads review
│   └── Trash
│
├── Optimizer
│   ├── Memory pressure
│   ├── Memory consumers
│   ├── Safe memory optimization
│   ├── Swap monitoring
│   ├── Heavy CPU consumers
│   ├── Hung applications
│   ├── Login items
│   ├── Background items
│   ├── Purgeable storage
│   ├── Time Machine snapshots
│   └── Maintenance
│       ├── Flush DNS
│       ├── Reindex Spotlight
│       ├── Reindex Mail
│       └── Supported macOS maintenance tasks
│
├── Applications
│   ├── Installed apps
│   ├── Full footprint
│   ├── Unused apps
│   ├── Uninstaller
│   ├── App reset
│   ├── Leftovers
│   ├── Installer leftovers
│   └── Updates
│
├── Storage
│   ├── Internal volumes
│   ├── External volumes
│   ├── Arbitrary folder scan
│   ├── Hierarchical browser
│   ├── Treemap
│   ├── Large files
│   ├── Old files
│   ├── Downloads
│   └── Developer projects
│
├── Duplicates
│   ├── Exact duplicates
│   ├── Duplicate downloads
│   └── Similar photos
│
├── Privacy
│   ├── Browser history
│   ├── Cookies
│   ├── Sessions
│   ├── Website data
│   ├── Recent activity
│   └── Application permissions
│
├── System / Monitor
│   ├── CPU
│   ├── Memory
│   ├── Swap
│   ├── Disk usage
│   ├── Disk health
│   ├── Battery
│   ├── Thermals
│   ├── Network
│   ├── Uptime
│   ├── External drives
│   └── Connected devices
│
├── Menu Bar
│   ├── Memory / Optimize
│   ├── CPU
│   ├── Disk
│   ├── Battery
│   ├── Network
│   └── Quick actions
│
├── Recommendations
│   ├── Low disk space
│   ├── High memory pressure
│   ├── Excessive swap growth
│   ├── Heavy CPU use
│   ├── Hung apps
│   ├── Battery drain
│   ├── Low accessory battery
│   ├── Low external-drive space
│   ├── Old unused apps
│   ├── Pending app updates
│   └── Large Trash
│
└── Platform
    ├── Safety Engine
    ├── Cleanup rules repository
    ├── Rules validation
    ├── Ignore lists
    ├── Scan history
    ├── Cleanup history
    ├── Local filesystem index
    ├── Global search
    ├── My Tools
    ├── Favorites
    └── Open contribution workflow
```

---

# 103. Product Differentiator

The differentiator is not that the app can delete caches.

Hundreds of utilities can delete caches.

The differentiator is:

> **This is the macOS maintenance application whose decisions users can inspect and trust.**

Every operation should be:

```text
Inspectible
Explainable
Conservative
Reversible
Local-first
Open source
```

Instead of:

> “We discovered 24.7 GB of junk.”

The application should communicate:

> **We found 24.7 GB of potentially reclaimable data.**
>
> - **18.1 GB** is generated data that applications can recreate.
> - **4.3 GB** appears to belong to applications that are no longer installed.
> - **2.3 GB** is user-owned data and requires manual review.

That distinction should define the product.

---

# 104. Final Product Boundary

The complete mature product is intentionally broad enough to replace the useful day-to-day functionality of commercial Mac maintenance utilities while staying focused on:

1. **safe cleanup;**
2. **resource optimization and troubleshooting;**
3. **application lifecycle management;**
4. **storage understanding;**
5. **duplicate detection;**
6. **privacy controls;**
7. **system monitoring;**
8. **transparent open-source rules and safety guarantees.**

It intentionally avoids becoming:

- a security suite;
- a cloud product;
- a root-level optimization daemon;
- a collection of placebo “boost” buttons.

The next planning step should derive the MVP from this specification without changing the full-product architecture.

---

# 105. Dependency Philosophy

The project should deliberately keep third-party dependencies small.

Dependency policy:

> **Prefer Apple platform APIs first. Use mature open-source libraries for solved infrastructure problems. Own all code that determines what files are discovered, classified, modified, or removed.**

A dependency should only be added when:

- it solves a substantial problem better than a small in-house implementation;
- it is actively maintained;
- it has a strong track record and meaningful adoption;
- its license is compatible with the project;
- its API boundary can be isolated cleanly;
- replacing it later would be practical;
- it does not become part of the application's deletion-safety trust boundary.

If a library is not clearly healthy and well maintained, build the functionality ourselves.

The application should prefer the native macOS SDK over third-party wrappers whenever the native API is adequate.

---

# 106. Approved Open-Source Dependencies

The following dependencies are approved for the project, subject to continued maintenance at the time they are introduced.

## 106.1 GRDB.swift

**Purpose:** SQLite persistence and indexing.

Use GRDB for:

- scan/index metadata;
- duplicate hash cache;
- application inventory;
- cleanup history;
- ignore rules;
- filesystem indexes;
- rule-version metadata;
- local application state where SQLite is appropriate.

Prefer GRDB over using the raw SQLite C API directly.

The database remains ordinary SQLite and should not become tightly coupled to ORM-specific behavior.

Decision:

```text
GRDB.swift
Status: APPROVED
```

---

## 106.2 Sparkle 2

**Purpose:** Secure application updates.

Use Sparkle for the direct-distribution update flow:

```text
Check for Update
       ↓
Download
       ↓
Verify
       ↓
Install
       ↓
Relaunch
```

Do not build a custom updater.

Requirements remain:

- signed releases;
- notarized releases;
- cryptographically verified update metadata;
- secure update feeds;
- rollback-safe behavior where practical.

Decision:

```text
Sparkle 2
Status: APPROVED
```

---

## 106.3 swift-collections

**Purpose:** High-quality collection types that are missing from the Swift standard library.

Use only when the data structure is actually needed.

Potentially useful types:

```text
Deque
OrderedSet
OrderedDictionary
Heap
```

Potential uses include:

- scanner work queues;
- priority queues;
- bounded task scheduling;
- ordered result aggregation.

Do not introduce it merely because it is available.

Decision:

```text
swift-collections
Status: APPROVED WHEN NEEDED
```

---

## 106.4 swift-async-algorithms

**Purpose:** Async sequence composition.

Potential uses:

```text
merge
debounce
throttle
combineLatest
```

Example:

```text
CacheScanner ──────┐
AppScanner ────────┤
StorageScanner ────┼── merge ──→ UI
Monitor ───────────┤
DuplicateScanner ──┘
```

Use only when these operators materially simplify production code.

Decision:

```text
swift-async-algorithms
Status: APPROVED WHEN NEEDED
```

---

## 106.5 Yams

**Purpose:** Parse human-editable YAML cleanup-rule definitions.

The cleanup-rules repository should favor a contributor-friendly format.

Example:

```yaml
id: spotify
name: Spotify

bundleIdentifiers:
  - com.spotify.client

paths:
  - path: ~/Library/Application Support/Spotify
    classification: review

  - path: ~/Library/Caches/com.spotify.client
    classification: safe
```

Yams must be isolated behind our own rule-loading abstraction:

```swift
protocol RuleLoader {
    func loadRules(from url: URL) throws -> [CleanupRule]
}
```

The rest of the application must not depend directly on Yams-specific types.

This keeps YAML parsing replaceable.

Decision:

```text
Yams
Status: APPROVED
```

---

## 106.6 SnapshotTesting

**Purpose:** UI and regression snapshots in tests.

Use selectively for high-value interface states such as:

- cleanup results;
- application footprint;
- safety warnings;
- duplicate groups;
- storage screens;
- empty/error/loading states.

Do not create large quantities of brittle snapshot tests for every component.

Decision:

```text
swift-snapshot-testing
Status: APPROVED FOR TESTS
```

---

## 106.7 SwiftFormat

**Purpose:** Consistent Swift formatting.

Use SwiftFormat across the repository and in CI.

Goals:

- predictable formatting;
- low-diff contributions;
- consistent AI-generated code;
- fewer style-only review discussions.

Decision:

```text
SwiftFormat
Status: APPROVED DEV TOOL
```

---

## 106.8 SwiftLint

**Purpose:** Additional static/style lint rules.

Do not include by default merely because it is common.

Start with SwiftFormat.

Add SwiftLint only if the project identifies meaningful rules that SwiftFormat cannot enforce and that provide real value.

Decision:

```text
SwiftLint
Status: OPTIONAL
```

---

## 106.9 swift-system

**Purpose:** Safer low-level system and file-descriptor APIs.

Do not add initially.

Foundation and Darwin/POSIX APIs should be sufficient for the first implementation.

Consider `swift-system` if the project begins using substantial amounts of:

```text
open
read
write
close
file descriptors
low-level path operations
```

and its abstractions materially improve safety/readability.

Decision:

```text
swift-system
Status: APPROVED IF LOW-LEVEL USAGE JUSTIFIES IT
```

---

# 107. Native Apple Frameworks Preferred

For macOS-specific functionality, prefer Apple frameworks directly instead of third-party wrappers.

Core native stack:

```text
SwiftUI
AppKit
Foundation
Charts
Vision
Core Image
ImageIO
CryptoKit
OSLog
FSEvents
IOKit
ServiceManagement
DiskArbitration
Darwin / POSIX
ProcessInfo
Mach APIs where appropriate
```

The project should not add a wrapper dependency merely to avoid learning a native API.

---

# 108. Functionality We Must Build Ourselves

The following functionality is part of the product's core behavior or safety boundary and should not be delegated to third-party libraries.

## 108.1 Filesystem Scanner

Build internally.

Responsibilities include:

- directory traversal;
- permissions;
- symlink behavior;
- mount boundaries;
- package handling;
- file-size aggregation;
- cancellation;
- concurrency;
- error handling;
- partial results;
- filesystem identity tracking.

This logic directly influences what the application sees and may later propose for cleanup.

## 108.2 Safety Engine

Build internally.

Responsibilities include:

- canonicalization;
- protected-path enforcement;
- symlink validation;
- ownership validation;
- mount-boundary checks;
- race validation;
- stale scan invalidation;
- cleanup authorization;
- ignore-list enforcement.

No dependency should decide whether a user's files are safe to remove.

## 108.3 Cleanup Engine

Build internally.

Core components should include concepts such as:

```text
CleanupPlan
CleanupItem
SafetyEngine
TrashService
CleanupHistory
```

The cleanup engine must remain fully auditable.

## 108.4 Application Uninstaller and Leftover Detection

Build internally.

This is a core product capability and differentiator.

It should understand:

- bundle metadata;
- bundle identifiers;
- containers;
- Application Support;
- preferences;
- helper apps;
- launch components;
- rules database;
- relationship confidence;
- ownership evidence.

Do not inherit opaque uninstall heuristics from a third-party library.

## 108.5 Directory-Size Engine

Build internally.

The implementation needs product-specific handling for:

- APFS;
- packages;
- symlinks;
- external volumes;
- hard links where relevant;
- permission failures;
- incremental results;
- cancellation.

This functionality is straightforward enough that a dependency is not justified.

## 108.6 Duplicate Detection Engine

Build internally.

Use native hashing primitives.

Pipeline:

```text
File size
   ↓
Candidate groups
   ↓
Partial hash
   ↓
Full hash
   ↓
Verified duplicates
```

Use `CryptoKit` rather than adding a hashing dependency.

For a macOS-only application:

```text
CryptoKit     YES
swift-crypto  NO
```

`swift-crypto` is unnecessary unless the project later needs a cross-platform cryptographic implementation.

## 108.7 Filesystem Monitoring

Use native FSEvents.

Build a small internal Swift abstraction around it.

Do not add a third-party filesystem-watcher dependency unless native FSEvents proves insufficient.

## 108.8 CPU and Process Monitoring

Build thin internal wrappers around native macOS facilities.

Potential sources include:

```text
Mach
libproc
sysctl
ProcessInfo
host_statistics64
task_info
```

This code is platform-specific by definition, so third-party abstraction provides little value.

## 108.9 Memory Monitoring

Use native macOS APIs and build the monitoring layer internally.

Potential APIs include:

```text
host_statistics64
vm_statistics64
task_info
ProcessInfo
```

The abstraction should expose meaningful product concepts such as:

```text
memory pressure
physical memory
used memory
compressed memory
swap
per-process memory
```

## 108.10 Battery and Power Monitoring

Prefer Apple APIs such as:

```text
IOKit
ProcessInfo
```

where reliable public interfaces exist.

Do not adopt poorly maintained sensor wrappers.

## 108.11 Thermal Monitoring

Use Apple-supported thermal information first:

```swift
ProcessInfo.processInfo.thermalState
```

Only add lower-level temperature readings when a reliable and maintainable method exists.

Do not depend on fragile private-API sensor libraries.

## 108.12 Treemap

Build internally.

The squarified treemap layout algorithm is small enough to own.

Conceptually:

```swift
struct TreemapNode {
    let size: UInt64
    let children: [TreemapNode]
}
```

Render with SwiftUI.

Do not depend on a small/abandoned SwiftUI treemap package.

## 108.13 Similar-Photo Analysis

Prefer native Apple frameworks:

```text
Vision
Core Image
ImageIO
Photos where appropriate
```

Generate similarity features locally and build clustering/grouping internally.

Do not add a large machine-learning framework unless native capabilities prove inadequate.

## 108.14 Login and Background Items

Use native APIs such as:

```text
ServiceManagement
SMAppService
```

Do not add third-party “launch at login” packages unless the native APIs cannot support a specific required behavior.

## 108.15 Menu-Bar App

Use native:

```text
MenuBarExtra
SwiftUI
AppKit where necessary
```

No menu-bar framework dependency should be needed.

## 108.16 Logging

Use native unified logging:

```swift
import OSLog

let logger = Logger(
    subsystem: "app.openmac",
    category: "scanner"
)
```

Benefits:

- Console.app integration;
- privacy annotations;
- subsystem/category filtering;
- signposts/performance tracing;
- no extra dependency.

Do not use `swift-log` by default for a macOS-only application.

## 108.17 Settings

Use native:

```text
UserDefaults
@AppStorage
SwiftUI Settings
```

No settings framework dependency is needed initially.

---

# 109. Charts and Graphs

Use Apple's native Charts framework for:

- CPU history;
- memory pressure/history;
- swap history;
- disk usage;
- network throughput;
- battery trends where appropriate.

Do not add a third-party chart library unless a future requirement cannot reasonably be implemented with Swift Charts.

---

# 110. Dependency Boundary Rules

Third-party libraries must sit behind project-owned interfaces whenever practical.

Examples:

```text
Yams
  ↓
RuleLoader
  ↓
Core rules model
```

```text
GRDB
  ↓
StorageRepository / Database
  ↓
Core application services
```

```text
Sparkle
  ↓
AppUpdateService
  ↓
UI
```

Benefits:

- easier replacement;
- easier testing;
- fewer vendor-specific types leaking through the codebase;
- cleaner architecture;
- easier security review.

---

# 111. Dependency Review Checklist

Before adding any new dependency, evaluate:

```text
[ ] Is the project actively maintained?
[ ] Has it had meaningful recent releases?
[ ] Is it widely used or backed by a reputable organization?
[ ] Is the license compatible?
[ ] Does Apple already provide the functionality?
[ ] Can we build the required subset simply ourselves?
[ ] Does it touch the deletion/safety trust boundary?
[ ] Can it be isolated behind our own interface?
[ ] Can we remove/replace it later?
[ ] Does it materially reduce complexity?
```

If the answer to “Does Apple already provide the functionality?” is yes, prefer the Apple API unless the third-party implementation offers a substantial and justified advantage.

If the dependency would decide what gets deleted, modified, or classified as safe, the default answer is **do not add it**.

---

# 112. Initial Dependency Tree

The initial project should aim for approximately this dependency tree:

```text
App
│
├── GRDB.swift
│   └── SQLite / local index
│
├── Sparkle
│   └── application updates
│
├── Yams
│   └── cleanup-rule files
│
├── swift-collections
│   └── only when required
│
└── swift-async-algorithms
    └── only when required

Tests
└── SnapshotTesting

Development
└── SwiftFormat
```

Optional later dependencies:

```text
SwiftLint
swift-system
```

Everything else should begin with either Apple-native APIs or project-owned implementations.

---

# 113. Canonical Technology Ownership Map

```text
SwiftUI                  Apple
AppKit                   Apple
Foundation               Apple
Charts                   Apple
Vision                   Apple
ImageIO                  Apple
Core Image               Apple
CryptoKit                Apple
OSLog                    Apple
FSEvents                 Apple
IOKit                    Apple
ServiceManagement        Apple
DiskArbitration          Apple
Darwin / POSIX           Apple

GRDB.swift               OSS dependency
Sparkle                   OSS dependency
Yams                      OSS dependency
swift-collections         OSS dependency when needed
swift-async-algorithms    OSS dependency when needed
SnapshotTesting           Test dependency
SwiftFormat               Development dependency

Filesystem Scanner       OURS
Safety Engine             OURS
Cleanup Engine            OURS
Uninstaller               OURS
Rule Semantics            OURS
Storage Analyzer          OURS
Duplicate Engine          OURS
Treemap                   OURS
Process Monitor           OURS
Memory Monitor            OURS
Developer Cleanup         OURS
Application Discovery     OURS
Relationship Confidence   OURS
Cleanup Authorization     OURS
```

This ownership map is intentional.

The project should use third-party software for mature infrastructure problems while retaining complete control over the code that determines:

- what is discovered;
- what is classified;
- what is considered safe;
- what is suggested;
- what is modified;
- what is deleted.
