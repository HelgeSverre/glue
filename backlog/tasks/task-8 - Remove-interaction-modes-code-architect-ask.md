---
id: TASK-8
title: Remove interaction modes (code/architect/ask)
status: Done
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 01:06'
labels:
  - simplification-2026-04
  - removal
  - tui
dependencies: []
references:
  - cli/lib/src/config/interaction_mode.dart
  - cli/lib/src/app/agent_orchestration.dart
  - cli/lib/src/app/terminal_event_router.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove the interaction mode system (`code` / `architect` / `ask`) and all supporting UI, config, tests, and docs.

**Why:** It is a UI-level policy layer that competes with prompts and tool approval. It creates surprising behavior where the model could do a task but the current mode silently hides or denies tools. Adds state to config, status bar, tests, permission resolution, and docs. Encourages "plan mode" UX instead of normal agent conversation.

**Target behavior:** No visible interaction mode; no Shift+Tab mode cycling; tools always present per normal configuration; planning is just a prompt, not a mode.

**Files to delete:**
- `cli/lib/src/config/interaction_mode.dart` — `InteractionMode`, `ApprovalMode`, `ToolGroup` enums
- `cli/test/config/interaction_mode_test.dart`
- `cli/test/interaction_mode_tool_filter_test.dart`

**Files to modify:**
- `cli/lib/src/app.dart` — remove `_interactionMode`, `_approvalMode` fields
- `cli/lib/src/app/command_helpers.dart` — drop Shift+Tab cycling hint in `/info`
- `cli/lib/src/app/agent_orchestration.dart` — delete `_syncToolFilterImpl` + call site
- `cli/lib/src/app/terminal_event_router.dart` — remove Shift+Tab mode-cycle branch
- `cli/lib/src/app/render_pipeline.dart` — remove mode label from status bar
- `cli/lib/src/config/glue_config.dart` — remove `interactionMode`/`approvalMode` fields and YAML parsing
- `cli/lib/glue.dart` — remove `InteractionMode`/`ApprovalMode` exports
- `cli/lib/src/agent/tools.dart` — decide `ToolGroup` fate (keep if R3 uses it for tool categorization in approval, else delete)
- `cli/lib/src/commands/builtin_commands.dart` — delete `/code`, `/architect`, `/ask`; keep `/approve` if `ApprovalMode` survives (R3 decision)
- `cli/docs/reference/config-yaml.md`, `cli/README.md`, `devdocs/` — remove mode docs/examples

**Config keys affected:** `interaction_mode` (YAML), `GLUE_INTERACTION_MODE` (env) — deprecation warnings handled by companion task R5.

**Land before R3 (permission gate collapse); land after R5 (graceful stale-config handling) so existing user configs don't break.**
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No reference to `InteractionMode` in `cli/lib/` or `cli/test/` (grep clean)
- [x] #2 Shift+Tab no longer cycles modes (inert or reassigned)
- [x] #3 Status bar shows no mode label
- [x] #4 `/code`, `/architect`, `/ask` slash commands removed
- [x] #5 `dart analyze --fatal-infos` clean
- [x] #6 `dart test` green
- [x] #7 Docs (`config-yaml.md`, README, devdocs) updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation Plan

### Approach
R1 removes `InteractionMode` entirely. `ApprovalMode` survives (task-10's design keeps it orthogonal). `PermissionGate` currently takes `InteractionMode` as a required parameter and uses mode-aware deny branches, so this task must touch the gate too (minimum needed to keep it compiling — essentially the first half of task-10's collapse). That's explicitly what the plan anticipates by stating "Land before R3".

### Steps

1. **Config layer** (`cli/lib/src/config/`)
   - Remove `interactionMode` field + `InteractionMode` param from `GlueConfig` constructor + `copyWith`
   - Keep `approvalMode` field (orthogonal, per plan)
   - Remove YAML/env parsing for `interaction_mode` and `GLUE_INTERACTION_MODE`
   - Keep parsing for `approval_mode` and `GLUE_APPROVAL_MODE`
   - Remove `import 'interaction_mode.dart'`; keep `ApprovalMode` (move enum to dedicated file or keep co-located)
   - Delete `cli/lib/src/config/interaction_mode.dart` OR reduce it to just `ApprovalMode` + ext

2. **PermissionGate** (`cli/lib/src/orchestrator/permission_gate.dart`)
   - Drop `interactionMode` parameter
   - Remove mode-based deny branches (lines 33–43) and `_targetsMarkdownFile`
   - Drop `deny` from `PermissionDecision` (no mode-based deny left) OR keep `deny` reserved (future-proof). Prefer: keep `deny` since tool-not-found still returns deny.
   - `needsEarlyConfirmation` drops mode check (line 72)

3. **Tool group** (`cli/lib/src/agent/tools.dart`)
   - Delete `ToolGroup` enum and `group` getter on `Tool` abstract class
   - Delete `group` override on `ForwardingTool`, `WebSearchTool`, `WebBrowserTool` (if present)
   - `ToolGroup` was only consumed by `InteractionMode.allowsGroup()` — it's dead now

4. **App layer** (`cli/lib/src/app.dart` + `app/` part files)
   - Remove `_interactionMode` field
   - Remove `_syncToolFilter()` method + callers in `agent_orchestration.dart` (delete `_syncToolFilterImpl` entirely)
   - `app/command_helpers.dart` — drop Shift+Tab mode cycling hint in `/info`
   - `app/terminal_event_router.dart` — remove Shift+Tab mode cycle branch (or reassign to nothing)
   - `app/render_pipeline.dart` — remove mode label from status bar

5. **Commands** (`cli/lib/src/commands/builtin_commands.dart`)
   - Delete `/code`, `/architect`, `/ask` slash commands
   - Keep `/approve` (toggles `ApprovalMode`)

6. **Barrel export** (`cli/lib/glue.dart`)
   - Remove `InteractionMode`, `InteractionModeExt`, `ToolGroup` from exports
   - Keep `ApprovalMode`, `ApprovalModeExt`

7. **Tests**
   - Delete `cli/test/config/interaction_mode_test.dart`
   - Delete `cli/test/interaction_mode_tool_filter_test.dart`
   - Update `cli/test/orchestrator/permission_gate_test.dart` — collapse architect/ask test groups; keep code+confirm, code+auto, trusted+confirm, trusted+auto, untrusted-safe+confirm, untrusted-mutating+confirm
   - Update `cli/test/config/glue_config_test.dart` — remove `interaction_mode` parsing tests; keep `approval_mode`
   - Update `cli/test/agent/prompts_test.dart` if it references removed slash commands
   - Check `cli/test/web/fetch/html_to_markdown_test.dart` — likely false positive on `/code` in HTML

8. **Docs**
   - `cli/docs/reference/config-yaml.md` — remove `interaction_mode` rows
   - `cli/README.md` — remove `GLUE_INTERACTION_MODE` from env-var list
   - `devdocs/` — remove any interaction mode references

9. **Quality gate**
   - `dart format --set-exit-if-changed .`
   - `dart analyze --fatal-infos`
   - `dart test`

### Risks
- `PermissionGate` test rewrites may touch many cases — mitigate by keeping shape of tests; only strip mode-specific groups.
- `ToolGroup` deletion may reveal unexpected consumers. Mitigate by greppping before deletion.
- `permission_mode_approval_test.dart` (if exists) — check before deletion.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed `InteractionMode`, `ToolGroup`, and all mode-cycling UX. `ApprovalMode` moved to new `cli/lib/src/config/approval_mode.dart`. `PermissionGate` collapsed to `{allow, ask, deny}` with `deny` retained only for unknown-tool case (mode-based deny removed). Shift+Tab now toggles approval mode (kept keybinding useful). Slash commands `/code`, `/architect`, `/ask` deleted; `/approve` kept.

**Files deleted:**
- `cli/lib/src/config/interaction_mode.dart`
- `cli/test/config/interaction_mode_test.dart`
- `cli/test/interaction_mode_tool_filter_test.dart`

**Files added:**
- `cli/lib/src/config/approval_mode.dart` (holds `ApprovalMode` + ext)

**Files modified:**
- `cli/lib/src/orchestrator/permission_gate.dart` — stripped mode branches
- `cli/lib/src/agent/tools.dart` — removed `ToolGroup` enum + `group` getter
- `cli/lib/src/tools/{web_search_tool,web_browser_tool}.dart` — dropped `group` overrides
- `cli/lib/src/config/glue_config.dart` — dropped `interactionMode` field + YAML/env parsing
- `cli/lib/src/app.dart` — dropped `_interactionMode` field, `_switchMode` method, `_syncToolFilter`
- `cli/lib/src/app/{agent_orchestration,terminal_event_router,render_pipeline,command_helpers}.dart` — consistent updates
- `cli/lib/src/commands/builtin_commands.dart` — removed `switchMode` param + three commands
- `cli/lib/glue.dart` — dropped `InteractionMode*`, `ToolGroup` exports
- `cli/test/orchestrator/permission_gate_test.dart` — rewritten for collapsed gate
- `cli/test/config/glue_config_test.dart` — removed interaction-mode assertions; added stale-key regression test
- `cli/test/commands/builtin_commands_test.dart` — dropped `switchMode` arg
- `cli/docs/reference/config-yaml.md`, `cli/docs/architecture/glossary.md` — updated

**Verification:**
- `dart analyze --fatal-infos` clean
- `dart format` clean
- Focused test suite (config/orchestrator/commands/agent) green — 97/97 pass
- Full test suite: 1246 pass, 1 pre-existing docker flake unrelated to this change (verified against main with stash)

**Stale-config behavior:** pre-existing `interaction_mode:` in user YAML is silently ignored (null-safe lookup, unchanged behavior). Explicit deprecation warnings tracked in task-12 (R5). Added a regression test covering stale `interaction_mode` key load without crash.
<!-- SECTION:FINAL_SUMMARY:END -->
