---
id: TASK-10
title: Collapse permission gate to simple approval
status: In Progress
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 00:45'
labels:
  - simplification-2026-04
  - refactor
  - security
dependencies:
  - TASK-8
references:
  - cli/lib/src/orchestrator/permission_gate.dart
  - cli/lib/src/app/agent_orchestration.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Once interaction modes are removed (see R1), `PermissionGate` has no mode dimension. Collapse it to a simple allow/ask decision based on trust + approval mode.

**Why:** Current `PermissionGate` combines interaction mode and approval mode. After interaction modes are gone, the gate should either disappear or shrink to a small approval decision. A simple "ask before mutating tools" prompt is understandable; a persistent trusted-tools list stays useful.

**Approach (recommended — collapse, not delete):**
- Remove `InteractionMode` branches (lines 33–43 today)
- Remove architect-mode `.md` file check (lines 37–43 today)
- Drop `deny` from `PermissionDecision` (mode-based deny is gone)
- Enum becomes `{ allow, ask }`
- Keep `ApprovalMode { confirm, auto }` — orthogonal and useful standalone
- Final logic: if `trusted` → allow; if `auto` → allow; if `!isMutating` → allow; else `ask`

**Files to modify:**
- `cli/lib/src/orchestrator/permission_gate.dart` (~80 lines) — rewrite
- `cli/lib/src/app/agent_orchestration.dart` — update call sites (lines 75, 143, 153); delete `_syncToolFilterImpl` entirely
- `cli/lib/src/agent/tools.dart` — decide `ToolGroup` fate; if kept, document that it is only a categorization hint, not a permission boundary
- `cli/test/orchestrator/permission_gate_test.dart` (~228 → ~100 lines) — rewrite

**Trusted-tools persistence unchanged** — still stored in `~/.glue/preferences.json` via `ConfigStore`.

**Depends on:** R1 (remove interaction modes) must land first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `PermissionGate` has no `InteractionMode` reference
- [ ] #2 `PermissionDecision` enum has no `deny` variant
- [ ] #3 Tests cover: trusted+confirm, trusted+auto, untrusted-safe, untrusted-mutating+confirm, untrusted-mutating+auto
- [ ] #4 Trusted-tools persistence (`ConfigStore`, `~/.glue/preferences.json`) unchanged
- [ ] #5 `dart test test/orchestrator/` green
- [ ] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->
