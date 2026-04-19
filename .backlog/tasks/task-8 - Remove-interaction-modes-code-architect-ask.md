---
id: TASK-8
title: Remove interaction modes (code/architect/ask)
status: In Progress
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 00:44'
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
- [ ] #1 No reference to `InteractionMode` in `cli/lib/` or `cli/test/` (grep clean)
- [ ] #2 Shift+Tab no longer cycles modes (inert or reassigned)
- [ ] #3 Status bar shows no mode label
- [ ] #4 `/code`, `/architect`, `/ask` slash commands removed
- [ ] #5 `dart analyze --fatal-infos` clean
- [ ] #6 `dart test` green
- [ ] #7 Docs (`config-yaml.md`, README, devdocs) updated
<!-- AC:END -->
