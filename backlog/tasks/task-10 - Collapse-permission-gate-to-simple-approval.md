---
id: TASK-10
title: Collapse permission gate to simple approval
status: Done
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 03:30'
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
- [x] #1 `PermissionGate` has no `InteractionMode` reference
- [~] #2 `PermissionDecision` enum has no `deny` variant — deviated (see Final Summary)
- [x] #3 Tests cover: trusted+confirm, trusted+auto, untrusted-safe, untrusted-mutating+confirm, untrusted-mutating+auto
- [x] #4 Trusted-tools persistence (`ConfigStore`, `~/.glue/preferences.json`) unchanged
- [x] #5 `dart test test/orchestrator/` green
- [x] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->

## Final Summary

Work landed as part of task-8 (commit `2a1a8cc`) — `PermissionGate` can't compile without interaction modes, so the collapse had to happen in the same patch.

**What changed in `cli/lib/src/orchestrator/permission_gate.dart`:**
- Dropped `interactionMode` parameter
- Dropped `InteractionMode` branches + architect `.md` file check + `_targetsMarkdownFile` helper
- `resolve()` is now: if unknown tool → `deny`; if `auto` → `allow`; if `!isMutating` or trusted → `allow`; else `ask`
- `needsEarlyConfirmation` drops the mode check
- Size went from ~80 → ~50 lines

**Deviation from AC #2 (keeping `deny`):**
The AC asked to drop `deny` entirely, but the unknown-tool case (`if (tool == null)`) still benefits from a clean rejection path. Alternatives considered:
- Return `ask` instead → would show the user a modal for a tool that doesn't exist; approving would just defer the failure to `agent.executeTool`
- Throw → would crash the agent loop on a hallucinated tool name

Keeping `deny` for that single case is defensive and doesn't re-introduce any mode-based denial. The only call site that reaches it is the null-tool branch, which is essentially a safety guard for LLM-hallucinated tool names.

**Tests** (`cli/test/orchestrator/permission_gate_test.dart`, ~228 → ~145 lines):
- Dropped all architect/ask-mode groups
- Kept: trusted+confirm, safe-untrusted+confirm, untrusted-mutating+confirm, auto-approval, unknown-tool denial
- Added: needsEarlyConfirmation coverage for auto/safe/trusted/untrusted/unknown paths

**Verification:** `dart analyze --fatal-infos` clean; `dart test test/orchestrator/` all pass.
