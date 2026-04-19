---
id: TASK-9
title: Remove plan-mode UI (PlanStore + /plans command)
status: Done
assignee:
  - Claud
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 00:54'
labels:
  - simplification-2026-04
  - removal
  - tui
dependencies: []
references:
  - cli/lib/src/plans/plan_store.dart
  - cli/lib/src/app/plans.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove the plan-mode UX and `PlanStore` infrastructure.

**Why:** Plan mode doesn't work well enough to justify a top-level UX concept; duplicates what the agent can do in normal chat; adds a planning data model and panel surface that isn't central to coding-agent execution. The `architect` interaction mode is going away (see R1), which removes plan mode's natural activation path.

**Target behavior:** User can still ask "make a plan" in chat; a slash command may print a simple markdown task list; no special plan mode or plan panel required for normal operation.

**Files to delete:**
- `cli/lib/src/plans/plan_store.dart` — `PlanStore` + discovery across `~/.glue/plans/` and workspace `docs/plans/`
- `cli/lib/src/app/plans.dart` — `/plans` command, plan viewer, editor integration
- `cli/test/plans/plan_store_test.dart`

**Files to modify:**
- `cli/lib/src/app.dart` — remove `_planStore` field + init
- `cli/lib/src/commands/builtin_commands.dart` — drop `/plans` and related plan slash commands
- `cli/test/commands/builtin_commands_test.dart` — remove plan command tests

**Keep (explicit non-goals):**
- The markdown renderer — unrelated
- Task-list text in assistant output — that's just markdown
- `cli/docs/plans/` and repo-level `docs/plans/` directories — those are developer-facing design docs, not a runtime feature
- Session storage — unrelated to plans
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `grep -r PlanStore cli/lib cli/test` returns nothing
- [x] #2 `/plans` slash command no longer registered
- [x] #3 Normal markdown rendering still works (regression check)
- [x] #4 Task-list text in assistant output still renders (regression check)
- [x] #5 `dart analyze --fatal-infos` clean
- [x] #6 `dart test` green
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Approved Plan

Stored at: /Users/helge/.claude/plans/start-work-on-removing-logical-castle.md

### Files to delete
1. `cli/lib/src/plans/plan_store.dart` (and remove empty `lib/src/plans/` dir)
2. `cli/lib/src/app/plans.dart`
3. `cli/test/plans/plan_store_test.dart` (and remove empty `test/plans/` dir)

### Files to modify
- `cli/lib/src/app.dart` — remove import (L29), part directive (L65), `_planStore` field (L157), init (L227), 2 callback args in BuiltinCommands.create (L474-475), wrappers `_openPlansPanel`/`_openPlanViewer`/`_openPlanInEditor` (L644-654), `_openPlanFromCommand` (L682-684)
- `cli/lib/src/commands/builtin_commands.dart` — drop `openPlansPanel`/`openPlanByQuery` params (L21-22) and `/plans` registration (L136-146)
- `cli/lib/src/app/command_helpers.dart` — drop `_openPlanFromCommandImpl` (L205-248)
- `cli/lib/src/ui/panel_controller.dart` — drop import (L8) and `openPlans({...})` method (L261-343)
- `cli/test/commands/builtin_commands_test.dart` — drop the two params (L15-16, L34-35) and the two `/plans` test cases (L145-177)

### Keep (explicit non-goals)
- markdown renderer
- task-list text in assistant output
- `cli/docs/plans/` and repo `docs/plans/`
- session storage
- `Environment.plansDir` getter (benign)

### Verification
```sh
cd cli
grep -r 'PlanStore\|PlanDocument\|plan_store' lib test  # expect empty
grep -rn "name: 'plans'" lib                            # expect empty
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implementation complete. Removed:
- `cli/lib/src/plans/plan_store.dart` (and empty `lib/src/plans/`)
- `cli/lib/src/app/plans.dart`
- `cli/test/plans/plan_store_test.dart` (and empty `test/plans/`)

Modified per plan, plus follow-on cleanup of two imports that were only used by the deleted code:
- `cli/lib/src/app.dart` — also removed unused `markdown_renderer.dart` import (was only used inside the deleted `plans.dart` part)
- `cli/lib/src/ui/panel_controller.dart` — also removed unused `package:path/path.dart` import (was only used inside the deleted `openPlans` method)

Verification results:
- `grep -r 'PlanStore|PlanDocument|plan_store' cli/lib cli/test` → no matches
- `grep -rn "name: 'plans'" cli/lib` → no matches
- `dart format --set-exit-if-changed .` → clean
- `dart analyze --fatal-infos` → No issues found!
- `dart test` → 1267 pass, 1 skipped, 1 failure in `DockerExecutor runCapture executes in container` — confirmed pre-existing failure on main (`git stash` repro), root cause is Docker daemon not running locally on this machine; unrelated to plan removal.
- AC #3/#4 (markdown + task-list rendering): markdown_renderer.dart and block_renderer.dart untouched; their unit tests pass within the suite.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed plan-mode UI entirely: `PlanStore` infrastructure, the `/plans` slash command, plan viewer/editor wiring, and the `Plans` panel.

**Deleted (3 files + 2 empty dirs):**
- `cli/lib/src/plans/plan_store.dart`
- `cli/lib/src/app/plans.dart`
- `cli/test/plans/plan_store_test.dart`

**Modified (5 files):**
- `cli/lib/src/app.dart` — dropped `_planStore` field/init, `plan_store.dart` import, `app/plans.dart` part directive, `openPlansPanel`/`openPlanByQuery` callbacks in `BuiltinCommands.create(...)`, and four wrapper methods (`_openPlansPanel`, `_openPlanViewer`, `_openPlanInEditor`, `_openPlanFromCommand`). Also dropped the now-orphaned `markdown_renderer.dart` import.
- `cli/lib/src/commands/builtin_commands.dart` — dropped `openPlansPanel`/`openPlanByQuery` parameters and the `/plans` `SlashCommand` registration.
- `cli/lib/src/app/command_helpers.dart` — dropped `_openPlanFromCommandImpl`.
- `cli/lib/src/ui/panel_controller.dart` — dropped `openPlans({...})` method, the `plan_store.dart` import, and the now-orphaned `package:path/path.dart` import.
- `cli/test/commands/builtin_commands_test.dart` — dropped `openPlansPanel`/`openPlanByQuery` params from `createRegistry` and the two `/plans` test cases.

**Kept (explicit non-goals):** `MarkdownRenderer`, task-list rendering in assistant output, `cli/docs/plans/` developer docs, session storage, `Environment.plansDir` getter (benign).

**Quality gate:**
- `grep -r 'PlanStore|PlanDocument|plan_store' cli/lib cli/test` → empty
- `dart format --set-exit-if-changed .` → clean
- `dart analyze --fatal-infos` → No issues found
- `dart test` → 1267 pass; 1 unrelated pre-existing Docker failure (Docker daemon not running locally; reproduces on `main` HEAD)
<!-- SECTION:FINAL_SUMMARY:END -->
