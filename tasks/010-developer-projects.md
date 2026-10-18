# 010 — Review generated data inside developer projects

Status: Done
Priority: P2  
Phase: A — More useful space recovery  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [004](004-storage-browser.md), [008](008-community-rules.md)

## Why

Global caches are only part of a developer's disk usage. Show which selected projects contain large build outputs or dependencies, with enough context to decide whether rebuilding or reinstalling them is worthwhile.

## Scope

- Start with explicitly chosen project folders and bounded, versioned rules for Node, Rust, and Swift projects. Identify project roots from supported manifests; never infer a project from a folder name alone.
- Separate source, generated build output, dependency directories, and unknown data. Treat dependency directories as review candidates because local modifications or unavailable packages may matter.
- Explain the rebuild/reinstall command conceptually, expected network requirements, and consequences. Never execute package-manager commands to prove a folder is regenerable.
- Exclude source, manifests, lockfiles, credentials, local databases, virtual machines, vendored code, and shared global stores unless a separate explicit rule supports the exact target.
- Recheck active tools, ownership, path bounds, and reviewed identities through the normal cleanup plan. Ignore rules apply to project roots and descendants.

## Acceptance criteria

- [x] Supported fixture projects show a useful breakdown without classifying source or unknown data as generated output.
- [x] Nested projects, workspaces, linked dependency trees, and shared stores cannot cause overlapping cleanup or escape the chosen root.
- [x] Modified dependency contents remain clearly Review, with nothing selected automatically.
- [x] Active builds/package managers block affected changes, and reviewed moves can be recovered through Activity.

## Validation

Add positive/negative fixtures for each initial ecosystem, including monorepos, linked directories, misleading folder names, ignored projects, and concurrent build changes. Recheck official ecosystem documentation when adding each rule. Test only against disposable projects.

## Starting points

Task 008's catalog, task 004's storage model, [CleanupActivity.swift](../Sources/LumaCore/CleanupActivity.swift), and [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift). Spec: sections 15, 52, 84–85, and 108.1 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare developer-data grouping, project selection, and regeneration explanations before implementation, during the working flow, and at completion. Record results in [reference-checks.md](reference-checks.md).


## Implementation and evidence — 2026-10-18

- Added a Projects destination and system folder chooser, project cards, source/configuration/other/excluded breakdowns, per-folder Review selection and the existing final confirmation sheet. No selection is automatic. Rebuild/reinstall and network/local-edit consequences are visible in item details and final review. Sidebar navigation scrolls to retain access at smaller window heights.
- Compiled, versioned `project.v1.*` rules recognize bounded JSON `package.json`, literal Cargo package/workspace tables and static Swift package signatures. They support only local `node_modules`, `target` and two macOS Swift build-product directories. They never evaluate a manifest or run a package manager. Custom targets, global/vendored stores, Swift dependency checkouts/repositories/artifacts and linked/shared trees remain excluded. See [Developer-Projects.md](../Documentation/Developer-Projects.md) for exact paths, limits and compatibility exclusions.
- Discovery is bounded and cancellable. Nested projects/workspaces are separate records; dependency/output directories are not recursively treated as more projects. All findings carry project-directory location evidence and manifest identity/SHA-256. The central SafetyEngine requires chosen-root scope, current ignore rules, owned/local/same-volume data, unchanged manifest and selected-tree evidence, no protected source/sensitive/shared contents and known idle tool activity. Unknown or active package/build/runtime tools block all project changes conservatively. Ordinary complete-plan overlap checks and durable Trash/Activity/Restore/Undo remain authoritative; mutations and recovery invalidate project snapshots.
- Fifteen new disposable fixture tests cover Node, Cargo packages/workspaces and Swift outputs; source/lockfile/unknown preservation; modified dependencies remaining Review; nested/monorepo discovery; invalid manifests and misleading names; ignored roots/descendants; symlinks, hardlinks and shared stores; sensitive/vendored/source data in build trees; forged/missing evidence and unauthorized scope; same-size/timestamp-restored manifest edits; concurrent builds; active/unknown tools before a plan and before later moves; provider changes and replaced project parents; final-boundary writes; cancellation; and journal/Restore round trips preserving dependency edits.
- Native light/dark checks of the built debug executable pass: three fixture projects and Review candidates, no default selection, kept source/lockfile/checkout evidence, actual review-sheet presentation for three items, changed-output rejection, snapshot/selection invalidation and continued monitoring. No native Trash action or package command is invoked. Existing Activity/history, ignore list and saved appearance/menu preferences match their pre-check hashes. Initial launcher-based fixture attempts did not produce a completed inventory; retained evidence comes from the current built executable with explicit disposable `/private/tmp` fixtures.
- Own Projects and review captures were inspected in light/dark. They show the Projects selection, per-project cards, Review badges, source-data disclosure and reinstatement/network/local-edit wording in the real confirmation sheet. Lower projects and details require scrolling. Captures/native assertions do not establish a full manual keyboard/VoiceOver session or execution of the system folder chooser. No personal project was scanned or cleaned. The separate native navigation smoke check covers all ten destinations, including Projects, without mutations.
- Reference checks at the start, working flow and completion inspect CleanMyMac 5.7.2 developer build/index and regeneration warnings from `protoypeopensourcemac.dmg`. Comparison is metadata/resources only, not a visual or end-to-end reference workflow. The image was read-only and is ejected. No reference executable/helper/cleanup, proprietary resources or copied code are introduced.
- Remaining intentional boundaries: symbolic links inside ordinary npm `.bin` layouts and some workspaces exclude the whole candidate; Swift checkouts are kept; custom targets and complete manifest interpretation are unsupported. Broad tool blocking favors retaining data. The existing process-start/pathname mutation race remains documented. Task 007's deferred manual accessibility/release gates and the published 0.2.0 Homebrew asset are unchanged.

Final validation: all **190 Swift tests in 18 suites** pass. The debug and optimized release apps build, and strict local signature verification passes. The navigation smoke check passes all **60 samples across ten destinations**, Light/Dark/System and standard/high-contrast window appearances, with menu visibility, live monitoring and no selection/mutation. This is not a full accessibility or GPU profiling review.
