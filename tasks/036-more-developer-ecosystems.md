# 036 — Extend reviewed cleanup to additional developer ecosystems

Status: Backlog  
Priority: P3  
Phase: F follow-up — Broader developer coverage  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [008](008-community-rules.md), [010](010-developer-projects.md)

## Why

The first project rules cover Node, Rust, and Swift. Extend the same inspectable model to other ecosystems without assuming every environment, repository, or dependency directory is disposable.

## Scope

- Evaluate Go, Python, Android/Gradle, Ruby, Flutter, and .NET in separate reviewed batches, using current official path/regeneration guidance and per-layout fixtures.
- Separate global download/build caches, project outputs, installed toolchains, virtual environments, SDKs, and source/vendor data. Broad stores or environments are not ordinary cache cleanup.
- Declare supported versions/locations and regeneration consequences, including offline availability, network downloads, environment recreation, and potentially local modifications.
- Extend active-tool checks for the supported operations. Custom/unrecognized layouts stay unknown; no package manager or build command is executed to classify a folder.
- Use exact catalog rules and the existing project/plan executor. Docker/container storage is handled separately in task 037.

## Acceptance criteria

- [ ] Each evaluated ecosystem has a support matrix and either bounded rules with fixtures or an explicit unsupported decision.
- [ ] Source, secrets, lockfiles, local repositories, toolchains, and unknown environments are not silently classified as Safe.
- [ ] Active or unknown tool activity blocks affected mutations, including project-local and shared-cache cases.
- [ ] Rule versions, child selection, ignore policies, and actual execution enforce the same boundary.

## Validation

Add positive/negative fixtures for each supported batch, including nested workspaces, custom cache overrides, linked outputs, offline dependencies, and active tools. Verify the relevant ecosystem's current primary documentation when introducing its rules.

## Starting points

Task 008's catalog, task 010's project discovery, [CleanupActivity.swift](../Sources/LumaCore/CleanupActivity.swift), and [SafetyEngine.swift](../Sources/LumaCore/SafetyEngine.swift). Spec: sections 15, 52, and 84–85 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare ecosystem categories, supported scope, regeneration explanations, and project review. Record actual reference coverage and missing/untestable states in [reference-checks.md](reference-checks.md).

