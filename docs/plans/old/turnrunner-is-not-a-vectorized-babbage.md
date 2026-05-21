# Final polish pass + architectural reports

## Context

The structural refactor is done; branch is 23 commits ahead of main. Remaining work:

1. Two cleanup items I'd earlier labelled "tempting but diminishing returns" — user wants them done.
2. A deep-dive into narrowing controller constructors further.
3. A pre-existing analyzer warning to fix before merge.
4. **Research the provider/model/LLM-client/factory stack** for cohesion and elegance — submit recommendation.
5. **Reorganise the test suite** to match the now-cleaned lib structure.
6. **Identify 3 concrete CLI improvements** to do soon — document, not build.

Three agents investigated (4), (5), (6) in parallel. Findings below, plan follows.

---

## Findings from the research pass

### Provider / LLM stack (item 4)

Verdict: **the stack is NOT tangled**. Four layers exist for real reasons — `LlmClient` interface (agent/), concrete wire-protocol clients (llm/), credential adapters (providers/), declarative catalog types (catalog/). Only real redundancies found:

- Adapter → client delegation is thin boilerplate (~6 lines each for Anthropic/OpenAI/Ollama); Copilot is the outlier because its adapter carries OAuth state.
- The model triple (`ModelDef` / `ModelRef` / `ResolvedModel`) is slightly over-engineered but not painful.
- `CompatibilityProfile` enum + switch is fine at current size (5 variants, 3 methods); escalate to object dispatch only if 5+ new profiles land in 6 months.

Two concrete simplification options surfaced:

- **Option α — Self-registration (green risk, ~15 LoC churn):** adapters gain a `static register(registry)` method; `service_locator.dart` stops hardcoding the registry list. Small friction win.
- **Option β — Merge adapter + client into one `Provider` class per vendor (yellow risk, saves ~150 LoC):** `LlmClient` interface moves from `agent/` to a shared `llm/interface.dart`. Each provider becomes one file instead of two. Copilot's OAuth complicates this.

Recommendation: **do Option α now as part of this pass; defer Option β** (bigger, needs its own session, and the audit says the stack is not painful enough to force it).

### Test-suite reorganisation (item 5)

14 test files sit at `test/` root but test production code that lives in subfolders. `test/` does not mirror `lib/src/` cleanly. Concrete moves:

| Move | Target |
|---|---|
| `agent_test.dart`, `content_part_message_test.dart`, `content_part_test.dart`, `execute_with_parts_test.dart` | `test/agent/` |
| `ansi_utils_test.dart`, `block_renderer_test.dart`, `markdown_renderer_test.dart` | `test/ui/rendering/` |
| `line_editor_test.dart`, `text_area_editor_test.dart` | `test/input/` |
| `terminal_test.dart` | `test/terminal/` (new folder) |
| `app_arg_completers_test.dart`, `slash_autocomplete_test.dart`, `slash_commands_test.dart` | `test/commands/` |
| `cli_args_test.dart` | `test/bin/` |
| `test/orchestrator/permission_gate_test.dart` | `test/runtime/` (orchestrator/ folder was retired) |

Plus:
- Duplicate check: `test/slash_autocomplete_test.dart` (root) appears alongside `test/commands/slash_autocomplete_test.dart` — reconcile (delete one, rename the other if needed).
- `test/commands/slash_autocomplete_integration_test.dart` — tag with `@Tags(['integration'])` or move to `test/integration/`.
- Delete empty `test/orchestrator/` folder after moves.

**Out of scope for this pass:** writing new tests for uncovered runtime modules (`turn.dart`, `renderer.dart`, `transcript.dart`, `input_router.dart`, etc.). Mentioned by the audit but that's its own multi-session effort.

### 3 concrete CLI improvements (item 6)

Documented as a roadmap, not built here. The three:

1. **MCP (Model Context Protocol) server integration** — 2-3 days. Auto-load tools from local MCP servers declared in `config.yaml`. Glue currently has zero MCP support; the 2026 ecosystem has standardised around it. Biggest capability unlock.
2. **Git-aware slash commands (`/diff`, `/status`, `/log`)** — 1-2 days. Thin wrappers around `git` via existing `BashTool`, rendered as collapsible transcript blocks. Felt every session; minimal risk.
3. **Clipboard image paste** — 1-2 days. Detect binary image paste, wrap as `ImagePart` (already in the agent domain model), inject as multimodal prompt. Closes the loop on visual debugging.

These go into `docs/plans/cli-roadmap-2026-04.md` — no code in this pass.

---

## Plan

### 1. Fix `shell_job_manager.dart:155` warning

Single unnecessary `!` operator. 30-second edit, drops the analyzer to zero warnings.

Files:
- `cli/lib/src/shell/shell_job_manager.dart:155` — remove the `!` on the assertion that's already known-non-null.

### 2. Cleanup: controllers take `Transcript` directly (drop `addSystemMessage` closure)

The 5 controllers that currently take `addSystemMessage: app._transcript.system` get `transcript: app._transcript` instead and call `transcript.system(...)` at point of use. One less closure per controller.

Controllers affected: `ModelController`, `SessionController`, `ShareController`, `SkillsController`, `ProviderController`. Also the `_Legacy*Commands` test fakes in `test/commands/builtin_commands_test.dart` (if they stay — see cleanup 2).

Files:
- `cli/lib/src/runtime/controllers/model_controller.dart`
- `cli/lib/src/runtime/controllers/session_controller.dart`
- `cli/lib/src/share/share_controller.dart`
- `cli/lib/src/runtime/controllers/skills_controller.dart`
- `cli/lib/src/runtime/controllers/provider_controller.dart`
- `cli/lib/src/app/controllers.dart` — update 5 construction sites
- `cli/lib/src/commands/builtin_commands.dart` — update `_Legacy*Commands` if we keep them
- `cli/test/commands/builtin_commands_test.dart` — may need updating

### 3. Cleanup: delete `*CommandController` + `SlashCommandContext` interfaces

Investigation: the interfaces exist in `runtime/commands/command_host.dart` (74 lines). Implemented by:
- 7 concrete controllers (`SystemController implements SystemCommandController`, etc.)
- 7 legacy `_Legacy*Commands` in `commands/builtin_commands.dart` used by `builtin_commands_test.dart` via `BuiltinCommands.create(...)`.

If the legacy `BuiltinCommands.create` closure-based path is the ONLY reason the interfaces exist, two options:

- **Option 3a — delete interfaces + legacy path.** Test uses real controllers with fakes for their deps. More test code, but single implementation path.
- **Option 3b — keep interfaces, delete the `Command` infix.** `SystemCommandController` → `SystemController` interface; the concrete class becomes `SystemControllerImpl` (re-adds the `Impl` suffix we'd banned). Not worth it.

**Recommendation: 3a.** Rewrite `builtin_commands_test.dart` to construct real controllers against fakes. Delete `command_host.dart`'s 7 interfaces + `SlashCommandContext` + the 7 `_Legacy*Commands` classes + `BuiltinCommands.create`. `buildBuiltinSlashCommands` takes the concrete `_AppControllers` directly.

Net: ~200 lines of ceremony deleted, single-implementation clarity, one less test indirection.

Files:
- Delete: `cli/lib/src/runtime/commands/command_host.dart`
- Rewrite: `cli/lib/src/commands/builtin_commands.dart` — drop `BuiltinCommands.create`; keep only `buildBuiltinSlashCommands` (already in `register_builtin_slash_commands.dart`, verify)
- Rewrite: `cli/test/commands/builtin_commands_test.dart` — construct real controllers with test doubles for their external deps
- Edit: `cli/lib/src/app/controllers.dart` — `_AppControllers` drops `implements SlashCommandContext`
- Edit: 7 `runtime/controllers/*_controller.dart` — drop `implements FooCommandController`

### 4. Cleanup (narrow constructors further): sweep obvious closure→service swaps

After #2 lands, audit the remaining closures per controller. Candidates:

- `setModelId` closure on ModelController — could be `config.setActiveModel(ref)` if `Config` exposes that setter (verify). Drop the closure.
- `setApprovalMode`/`getApprovalMode` on ChatController — already look like field mutations on App; could move to `config` service since approval mode is config-shaped.
- `currentSessionId` closure on SystemController — `session.currentId` already exists. Swap.
- `modelLabel` / `approvalLabel` closures on SessionController — these stitch multiple App fields into a display string. Could become methods on a small formatter, but "keep as closure" is fine (controllers should own display formatting).

Scope: only swap where the replacement is strictly simpler. Don't invent new services.

Files: case-by-case in `runtime/controllers/*_controller.dart` and `app/controllers.dart`.

### 5. Provider/LLM stack: adapter self-registration (Option α)

- Each `*Adapter` gains `static void register(AdapterRegistry r)`.
- `service_locator.dart` changes from `AdapterRegistry([Anthropic…(), OpenAi…(), Ollama…(), Copilot…()])` to one `register()` call per adapter.
- Adding a new adapter touches only the new adapter file + one call site.

No interface changes, no structural refactor. Small green win.

Files:
- `cli/lib/src/providers/anthropic_adapter.dart`
- `cli/lib/src/providers/openai_compatible_adapter.dart`
- `cli/lib/src/providers/ollama_adapter.dart`
- `cli/lib/src/providers/copilot_adapter.dart`
- `cli/lib/src/core/service_locator.dart`

**Deferred (not this pass): Option β (merge adapter + client).** Documented in REFACTOR.md as a future-work item with yellow-risk label; revisit if we onboard 2+ new providers in a session.

### 6. Test-suite reorganisation

Execute the 14 file moves + 4 new folders + duplicate reconciliation. Purely mechanical; `git mv` + verify tests still pass.

Verification: after moves, `dart test` passes with identical pass count (1515 or higher).

Files — 14 moves, 4 folder creations (`test/terminal/`, `test/ui/rendering/`, `test/bin/` may exist, `test/input/` exists). Full list in the findings section above.

### 7. Write `docs/plans/cli-roadmap-2026-04.md`

Document the 3 proposals: MCP, git slash commands, image paste. For each: scope, effort, why now, files it would touch. This aligns with CLAUDE.md's guidance that new command families get documented in `docs/plans/` before implementation.

Files:
- Create: `docs/plans/cli-roadmap-2026-04.md`

### 8. Sync REFACTOR.md

Close out:
- Add "Test suite matches lib structure" to What's Done
- Add "Adapter self-registration landed" to What's Done
- Add a "Deferred (provider/llm)" item for the Option β merge-adapter-client decision

Files:
- Edit: `REFACTOR.md`

---

## Critical files

- `cli/lib/src/shell/shell_job_manager.dart:155` — warning to fix
- `cli/lib/src/runtime/controllers/*.dart` — 7 controllers for cleanups 2/3/4
- `cli/lib/src/runtime/commands/command_host.dart` — 7 interfaces to delete
- `cli/lib/src/commands/builtin_commands.dart` — legacy closure path to delete
- `cli/lib/src/app/controllers.dart` — 7 construction sites to update (drop `addSystemMessage`, drop interface implementation)
- `cli/lib/src/providers/*_adapter.dart` — 4 adapters gain `register()`
- `cli/lib/src/core/service_locator.dart` — switch to self-registration
- `cli/test/` — 14 file moves + duplicate reconciliation
- `cli/test/commands/builtin_commands_test.dart` — rewrite to use real controllers
- `REFACTOR.md` — sync
- `docs/plans/cli-roadmap-2026-04.md` — new

## Verification

After each step:
1. `cd cli && dart format --set-exit-if-changed .`
2. `cd cli && dart analyze --fatal-infos` — expect **zero** issues after step 1 (the shell warning is the last pre-existing one)
3. `cd cli && dart test` — 1515+ tests pass
4. `cd cli && just ui-check` — no ui/ → feature imports
5. `cd cli && dart compile exe bin/glue.dart -o /tmp/glue-polish` — binary builds

Post-pass:
- `ls cli/test/` — only subfolders, no root-level `*_test.dart`
- `grep -r "CommandController" cli/lib/` — zero hits (interfaces deleted)
- `grep -r "addSystemMessage" cli/lib/` — zero hits (closure removed)
- `grep -r "BuiltinCommands.create" cli/` — zero hits (legacy path deleted)

## Out of scope

- **Option β** (merge adapter + client into one `Provider` class) — documented for later; meaningful refactor that needs its own session.
- **New tests** for uncovered runtime modules (`turn_test.dart`, `renderer_test.dart`, etc.) — the reorganisation audit flagged coverage gaps but filling them is its own effort.
- **Building** the 3 CLI improvements — only documenting them in this pass.
- **Interactive smoke test** — still manual; happens before merge.

## What this plan is not

- Not new abstractions. Cleanup 2 deletes abstractions.
- Not a feature commit. Cleanups are structural; improvements #6 are just documentation.
- Not a prerequisite for merging main. Each item is independent; if you stop after cleanup 4 the branch is still shippable.
