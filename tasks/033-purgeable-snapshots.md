# 033 — Explain purgeable space and local snapshots

Status: Backlog — reclaim actions require verified platform support  
Priority: P3  
Phase: G — Explain system-managed storage  
Depends on: [016](016-volume-analysis.md), [026](026-maintenance-tools.md)

## Why

Available capacity, purgeable storage, and local snapshots can explain apparent differences in disk usage. They must not be added together as guaranteed cleanup savings or presented as evidence that macOS is managing storage badly.

## Scope

- Add separate capacity/reclaimability observations with their source, measurement time, volume identity, and limitations. Do not invent a purgeable total by subtracting incompatible values.
- Inspect accessible local Time Machine snapshot metadata, showing count, dates, and size estimates only when the source supports that interpretation.
- Explain automatic system management and distinguish snapshot estimates, file sizes, available capacity, and confirmed free-space changes.
- Assess any manual thinning/reclaim operation against current documented platform behavior, backup activity, authorization, and bounded targeting. Unsupported or uncertain actions remain unavailable.
- Reuse maintenance outcome recording rather than promising Trash/Restore for system-managed operations. No automatic thinning, synthetic disk filling, or ordinary-file deletion to force reclamation.

## Acceptance criteria

- [ ] APFS/shared-capacity fixtures do not produce misleading additive totals or guaranteed physical-savings claims.
- [ ] Missing permissions or unsupported metadata remain unknown, not zero snapshots or zero purgeable bytes.
- [ ] Any enabled reclaim action has a documented supported mechanism, exact volume scope, explicit consequences, and verified completion evidence.
- [ ] If safe reclaim support is not established, the completed inspection feature includes a documented no-action decision without weakening other protections.

## Validation

Use injected volume/snapshot providers and disposable disk-image fixtures. Verify active-backup, removed-volume, permission, command-failure, and ambiguous-size cases. Never thin the user's real backup snapshots for testing.

## Starting points

Task 016's volume model, task 026's maintenance lifecycle, [SystemMonitor.swift](../Sources/LumaApp/SystemMonitor.swift), and [OverviewView.swift](../Sources/LumaApp/OverviewView.swift). Spec: sections 30–32 and 66 in the [product specification](../Documentation/Product-Spec.md).

Reference checkpoints: compare purgeable/snapshot terminology, capacity explanation, actions, and unknown states. Record what was observable in [reference-checks.md](reference-checks.md).

