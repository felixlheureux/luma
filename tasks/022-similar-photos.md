# 022 — Find and compare similar photos locally

Status: Backlog  
Priority: P3  
Phase: D — Broader application and discovery tools  
Depends on: [001](001-cleanup-plans.md), [002](002-filesystem-identity.md), [003](003-scan-sessions.md), [014](014-incremental-index.md), [015](015-duplicate-review.md)

## Why

Similar photos are a valuable discovery feature, but resemblance is not exact duplication. Users need a visual comparison and control over which images matter to them.

## Scope

- Start with explicitly selected ordinary image folders and local Vision/ImageIO analysis, subject to verified format support. Keep Photos-library internals outside this first scope.
- Bound thumbnail generation, memory, concurrency, and analysis time. Skip cloud placeholders without downloading them, report unsupported/corrupt images, and support cancellation.
- Present explainable similarity groups distinct from SHA-256 duplicate groups, with resolution, dates, relevant metadata, and accessible comparison descriptions.
- Make any best-copy suggestion informational and explain the criteria. Start with no removal selections and preserve originals/metadata without recompressing or editing images.
- Use normal manual review and journal operations for selected files. Revalidate changed images and preserve at least one reviewed keeper in each selected similarity set.
- Represent similarity review sets separately from exact-content groups in the core plan. A similar-image keeper does not establish the full-content equivalence required for an exact-duplicate claim.

## Acceptance criteria

- [ ] Near-identical, resized, edited, and unrelated fixture images demonstrate documented grouping limits and do not receive exact-duplicate labels.
- [ ] Unsupported or cloud-only items are skipped visibly without side-effect downloads.
- [ ] Users can compare originals and metadata, reject a group, and choose manually; nothing is removed by a suggestion.
- [ ] Cancellation and large image sets stay bounded, and changed files require new analysis/review.

## Validation

Use original or permissively licensed image fixtures with a documented similarity evaluation set, corrupt files, huge dimensions, rotation metadata, and changed content. Test selection/keeper invariants independently from the similarity algorithm and perform fixture-only recovery checks.

## Starting points

Task 015's comparison UI, task 014's index, task 003's coordinator, and task 001's executor. Spec: sections 56, 90, 98, and 108.13 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare similarity grouping, visual comparison, best-copy explanations, and final review where supported. Record accessible and untestable states in [reference-checks.md](reference-checks.md).

