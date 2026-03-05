# Plan Capture + Observer/Harness Split (Practical Scope)

## Decision: Cut Scope to What Will Actually Be Used

We will **not** build a heavy plan-status system right now.

Keep:
- Plan capture mode (Shift+Tab)
- Clarification + revision loop
- Save plan as markdown
- Plan viewer (`/plans`) and open-in-editor
- Runtime split so work can run async and UI can observe/switch between runs

Defer:
- Rich plan lifecycle/status model (`draft/running/done/...`)
- Complex plan metadata database
- Advanced analytics/history features

Reason:
- Current bottleneck is execution ergonomics, not plan bookkeeping.
- Markdown-first plans are enough if capture + revision + retrieval are smooth.

---

## Product Goal

Glue should support this workflow:
1. User enters plan capture mode with Shift+Tab.
2. User describes intent.
3. Agent asks clarifying questions when needed.
4. Agent drafts plan.
5. User revises plan iteratively.
6. User saves plan to markdown.
7. User can execute work while UI observes one run at a time and hot-swaps between active runs/workspaces.

---

## Non-Goals (for this implementation)

- No plan DAGs/task graphs.
- No plan status machine beyond file existence + last modified.
- No automatic “plan completion detection.”
- No remote/backend orchestration.

---

## Architecture (Target)

### 1) Plan Capture Layer (UI + prompts)

New mode in app input router:
- `InputMode.normal`
- `InputMode.planCapture`

When in `planCapture`:
- Next submit is routed to planner flow.
- Planner can emit:
  - Clarifying question(s)
  - Draft plan markdown
  - Revised plan markdown
- UI keeps a local in-memory `PlanDraftSession`:
  - `prompt`
  - `clarifications[]`
  - `currentMarkdown`
  - `suggestedTitle`

### 2) Plan Persistence (simple)

Persist only markdown file + minimal header.

File format:
- Markdown with frontmatter:
  - `title`
  - `created_at`
  - `workspace`
  - `source_prompt`
- Body = plan content

Paths:
- Global default: `~/.glue/plans/YYYY-MM-DD-<slug>.md`
- Optional workspace save target: `./docs/plans/YYYY-MM-DD-<slug>.md`

No extra state file required for v1.

### 3) Runtime split: Harness vs Observer

Separate concerns:
- **Harness**: executes turns/runs (agent runtime, tools, streaming, lifecycle).
- **Observer**: renders one selected run in TUI and routes input to that run.

Minimal runtime registry:
- `runId`
- `workspacePath`
- `startedAt`
- `label`
- `isActive`

No rich run status taxonomy in v1; just active/inactive + last event time.

---

## Implementation Plan

## Phase 1: Plan Capture Mode + Draft Loop

Files:
- `cli/lib/src/app/terminal_event_router.dart`
- `cli/lib/src/app/models.dart`
- `cli/lib/src/app/event_router.dart`
- `cli/lib/src/commands/builtin_commands.dart`

Changes:
1. Add input mode flag (`normal` / `planCapture`).
2. Shift+Tab behavior:
   - If not in plan capture: enter plan capture.
   - If in plan capture: exit plan capture.
   - Move permission mode cycling to dedicated key (e.g. Ctrl+P) or slash command to avoid conflict.
3. In plan capture mode, submit routes to planner flow.
4. Add slash helpers:
   - `/plan` open plan capture explicitly
   - `/plan-exit` leave plan capture
5. Display mode indicator in status bar.

Acceptance:
- User can enter/exit plan capture reliably.
- Normal chat unaffected when not in plan mode.

## Phase 2: Clarify + Revise Loop

Files:
- `cli/lib/src/app/agent_orchestration.dart`
- `cli/lib/src/app/command_helpers.dart`
- `cli/lib/src/app/models.dart`
- `cli/lib/src/agent/prompts.dart` (or planner prompt location)

Changes:
1. Add planner prompt contract:
   - Return either `CLARIFY:` or `PLAN:`.
2. If clarify response:
   - render question and keep session open.
3. If plan response:
   - render markdown preview in plan viewer panel/modal.
4. Add revise action:
   - user free-text input modifies current draft.
5. Keep latest markdown draft in memory.

Acceptance:
- Multi-turn clarify/revise works without leaving plan mode.
- Latest draft is always available for save.

## Phase 3: Save Plan (Markdown-first)

Files:
- `cli/lib/src/plans/plan_store.dart`
- `cli/lib/src/app/plans.dart`
- `cli/lib/src/core/environment.dart`

Changes:
1. Add `savePlanDraft(...)`:
   - generate slug from title/prompt
   - write markdown with frontmatter
2. Save target choice:
   - default global
   - optional workspace path
3. Reuse existing `/plans` browser to confirm saved file is visible.
4. Keep open-in-editor integration.

Acceptance:
- User can save plan from capture loop in one action.
- Saved plan appears in `/plans` immediately.

## Phase 4: Harness/Observer Split (minimal viable)

Files (new):
- `cli/lib/src/runtime/run_harness.dart`
- `cli/lib/src/runtime/run_registry.dart`
- `cli/lib/src/runtime/run_observer.dart`

Files (modify):
- `cli/lib/src/app.dart`
- `cli/lib/src/app/agent_orchestration.dart`
- `cli/lib/src/app/render_pipeline.dart`

Changes:
1. Extract execution from `App` into harness abstraction.
2. Registry tracks active runs (multiple).
3. UI observer attaches to selected run only.
4. Add run switcher command/panel:
   - `/runs` list active runs
   - select one to observe/control
5. Ensure background runs continue when UI switches.

Acceptance:
- Two concurrent runs can exist.
- UI can switch observed run without stopping the other.

## Phase 5: Workspace Hot-Swap on top of Run Registry

Files:
- `cli/lib/src/app/plans.dart`
- `cli/lib/src/ui/*` (run/workspace selector panel)
- `cli/lib/src/runtime/run_registry.dart`

Changes:
1. Add workspace-aware run list.
2. Hot-swap current observer workspace/run.
3. Keep command execution scoped to selected run/workspace.

Acceptance:
- User can jump between workspaces/runs from one TUI.

---

## Parallelization

Can run in parallel:
1. Phase 1 (input/mode plumbing) + Phase 3 persistence internals.
2. `/plans` panel UX polish + plan save formatting.
3. Runtime extraction groundwork (interfaces only) while plan loop is implemented.

Must be sequential:
1. Phase 2 depends on Phase 1 mode routing.
2. Phase 5 depends on Phase 4 registry/harness split.

---

## Risks + Mitigations

Risk: Keybind conflict (Shift+Tab currently used for permissions).
- Mitigation: Move permission cycle to explicit command/key before enabling plan capture on Shift+Tab.

Risk: Harness split causes regressions in streaming/tool approval flow.
- Mitigation: Introduce harness interface first, then migrate one flow at a time behind adapter.

Risk: Too much runtime refactor at once.
- Mitigation: Keep minimal v1 registry and avoid status model expansion.

---

## Verification

After each phase:
1. `cd cli && dart analyze`
2. `cd cli && dart test`
3. Manual:
   - Enter/exit plan mode
   - Clarify/revise/save cycle
   - `/plans` open and editor handoff
   - Multiple runs active + observer switch

---

## Definition of Done

- Shift+Tab opens practical plan capture flow.
- Clarification + revision loop is usable end-to-end.
- Plan saves to markdown and is discoverable via `/plans`.
- Harness/observer split supports concurrent runs and hot-swapping observation.
- No heavy status subsystem introduced.
