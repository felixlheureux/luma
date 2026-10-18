# 010 — Review generated data inside developer projects

Status: Backlog  
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

- [ ] Supported fixture projects show a useful breakdown without classifying source or unknown data as generated output.
- [ ] Nested projects, workspaces, linked dependency trees, and shared stores cannot cause overlapping cleanup or escape the chosen root.
- [ ] Modified dependency contents remain clearly Review, with nothing selected automatically.
- [ ] Active builds/package managers block affected changes, and reviewed moves can be recovered through Activity.

## Validation

Add positive/negative fixtures for each initial ecosystem, including monorepos, linked directories, misleading folder names, ignored projects, and concurrent build changes. Recheck official ecosystem documentation when adding each rule. Test only against disposable projects.

## Starting points

Task 008's catalog, task 004's storage model, [CleanupActivity.swift](../Sources/LumaCore/CleanupActivity.swift), and [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift). Spec: sections 15, 52, 84–85, and 108.1 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare developer-data grouping, project selection, and regeneration explanations before implementation, during the working flow, and at completion. Record results in [reference-checks.md](reference-checks.md).

