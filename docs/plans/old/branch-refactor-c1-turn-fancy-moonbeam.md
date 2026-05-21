# Plan: Dispatch Tasks 1–4 from `refactor/c1-turn` handoff

## Context

Branch `refactor/c1-turn` is 28 commits ahead of `origin/main` with the Group A/B/C/D1 refactor complete, analyzer clean, 1511 tests passing. `docs/plans/2026-04-24-handoff.md` defines six follow-up tasks. The user wants to run Tasks 1–4 now, in parallel where possible, on the shared `refactor/c1-turn` working tree.

Parallelism is constrained by file overlap:
- **Task 1 (runtime test coverage)** writes only to `cli/test/**` — zero conflict.
- **Task 2 (merge Adapter + Client into Provider per vendor)** is scoped to `cli/lib/src/providers/` + `cli/lib/src/llm/` + one interface move in `cli/lib/src/agent/agent.dart` — zero overlap with Tasks 1/3/4.
- **Task 3 (rename slash commands)** and **Task 4 (codify arg-completer convention)** both edit `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` + the six controller files. Decision: **Task 4 first, Task 3 after.**

Outcome: Batch 1 dispatches Tasks 1 + 2 + 4 concurrently on the shared branch. Batch 2 runs Task 3 once Task 4 lands.

---

## Decisions captured (from Q&A)

- **Task 3 vs 4 ordering:** Task 4 first (pure refactor), Task 3 after (renames localize to strings once the registration machinery has been redone).
- **Task 2 scope:** All 4 vendors (Anthropic → OpenAI-compat → Ollama → Copilot). Copilot last; tests gate merge.
- **Isolation:** Shared branch, multiple concurrent agents. Safe *only* because Tasks 1/2/4 touch disjoint files (verified below).

---

## Parallel file-ownership map (Batch 1)

| Path | Task 1 | Task 2 | Task 4 |
|---|---|---|---|
| `cli/test/runtime/**` + `cli/test/agent/**` + `cli/test/shell/**` | **W** | — | — |
| `cli/test/providers/**` + `cli/test/llm/**` | — | **W** | — |
| `cli/lib/src/providers/**` | — | **W** | — |
| `cli/lib/src/llm/**` | — | **W** | — |
| `cli/lib/src/agent/agent.dart` (move `LlmClient` interface out) | R | **W** | — |
| `cli/lib/src/commands/slash_commands.dart` | — | — | **W** |
| `cli/lib/src/commands/arg_completers.dart` | — | — | R |
| `cli/lib/src/runtime/commands/command_module.dart` | — | — | **W** |
| `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` | — | — | **W** |
| `cli/lib/src/runtime/controllers/{model,skills,session,provider,system,share}_controller.dart` | R | — | **W** |
| `cli/lib/src/share/share_module.dart` | — | — | **W** |

**Conflict check:** Task 1 reads (never writes) the source files it tests. The `LlmClient` interface move in Task 2 changes the import location in tests — Task 1's new tests must be told up-front to import from `package:glue/src/agent/agent.dart` (current location) so they don't race the move. If Task 2 finishes first and moves it, Task 1's PR gets a post-hoc import fix. Low risk.

---

## Task 1 — Runtime test coverage

**Goal:** Add direct unit tests for runtime primitives that landed in Groups C/D without their own test files.

**Files to create** (all under `cli/test/runtime/` unless noted):

- `turn_test.dart` (~450 LoC target)
  - `run()` appends user block, subscribes to agent stream, ends span on done
  - `run()` double-run regression — document current behavior (no guard, `turn.dart:73`); mark test `@Tags(['known-issue'])` or similar
  - `cancel()` mid-stream ends span + cancels subscription
  - `AgentError` interactive path — currently ends span as success (`turn.dart:376`); document behavior with `@Tags(['known-issue'])`
  - `AgentError` print path ends span with error metadata (symmetry check)
  - Tool approval: early confirmation, full modal confirmation, denial, trust-and-auto-approve
  - `runPrint` json-mode output shape
- `transcript_test.dart` (~250 LoC)
  - Block ordering (user → streamingText → assistant → toolCall → toolResult)
  - `system()` appends an `EntryKind.system` entry
  - `handleSubagentUpdate` dedup by `task:index` key; rendering bool signal; JSON pretty-print fallback
  - `clear()` resets all collections including `streamingText`, `toolUi`, `subagentGroups`, `outputLineGroups`
  - Phase transitions on `ToolCallUiState`
- `input_router_test.dart` (~350 LoC)
  - Priority stack: panel > modal > dock > approval-toggle > scroll > bash-toggle > streaming-editor > autocomplete > idle
  - Mode branching (idle vs streaming vs bashRunning)
  - Ctrl+C double-tap exit window
  - Bash mode toggle (`!` at cursor 0 activates; backspace at 0 deactivates)
  - Mouse click on subagent group toggles expansion
  - Autocomplete navigation + escape/accept
- `../shell/bash_mode_test.dart` (~250 LoC) — writes into `cli/test/shell/`
  - Background `&` routes to `ShellJobManager.start()`
  - Blocking path: stdout/stderr stripping, exit code logged, span metadata
  - `cancel()` sends SIGTERM, ends span with `cancelled: true`, mode returns to idle
  - Job events (`JobStarted`, `JobExited`, `JobError`) flow through transcript
- `renderer_test.dart` (~120 LoC)
  - `schedule()` coalesces requests inside 16ms window
  - `markRendered()` resets coalescing clock
  - `startSpinner` idempotent; frame advances modulo 10 over time (`FakeAsync` pattern)
  - `stopSpinner` idempotent when not running
- `services/config_test.dart` (~120 LoC)
  - `trustTool` idempotent; persists via write closure; swallows persist errors without throwing
  - `trustedTools` is the live set `PermissionGate` sees — mutation visible mid-turn
  - `current` null when read closure returns null
- `services/session_test.dart` (~350 LoC)
  - `resume()` clears transcript then replays persisted entries in order
  - `fork()` truncates at user-message index; fires `installDraft` callback
  - Title state machine: initial-request flag, re-eval flag, manual-override blocks both
  - `shouldGenerateInitialTitle` gating
  - `onTurnComplete` re-evaluation criteria (assistant length / tools used / branching)
  - Title generation disabled in config → early return, no `ConfigError` surfaced

**Patterns to reuse:**
- Zone-scoped observability: `cli/test/observability/observability_test.dart:259–363` (`runInSpan` isolation + concurrent save/restore).
- LlmClient mocks: `cli/test/agent/agent_headless_test.dart:7–43` (`_TextOnlyLlm`, `_ToolCallLlm`).
- Test config: `cli/test/_helpers/test_config.dart`.
- Recording sinks: `cli/test/shell/shell_job_manager_test.dart:8–19` (`_RecordingSink`).

**Out of scope (explicit):** Do **not** fix the Turn double-run guard, AgentError span metadata bug, or subagent zone isolation in this task. Tests document current behavior (tagged `known-issue`) so a follow-up fix commit can flip them to passing. This keeps Task 1 a pure test-addition diff.

**Verification:**
```sh
cd cli && dart test test/runtime/ test/shell/bash_mode_test.dart
cd cli && just check
```

---

## Task 2 — Merge `*Adapter` + `*Client` → `*Provider` per vendor

**Goal:** Collapse each vendor's split into one `*Provider` class that implements both `ProviderAdapter` and `LlmClient`. Net ~180 LoC saved across 4 vendors.

**Phased order (low to high risk):**

1. **Anthropic** — merge `cli/lib/src/providers/anthropic_adapter.dart` (41 LoC) + `cli/lib/src/llm/anthropic_client.dart` (167 LoC) into `cli/lib/src/providers/anthropic_provider.dart`.
2. **OpenAI-compatible** — merge `openai_compatible_adapter.dart` (52) + `openai_client.dart` (193) → `openai_provider.dart`.
3. **Ollama** — merge `ollama_adapter.dart` (95) + `ollama_client.dart` (199) → `ollama_provider.dart`. Keep `discoverModels()` override.
4. **Copilot** — merge `copilot_adapter.dart` (284) + private `_CopilotClient` into `copilot_provider.dart`. `copilot_token_manager.dart` (122 LoC, stateless helpers) stays — `freshCopilotToken(store)` is called inside `stream()`. OAuth device flow + polling loop stay embedded in the provider.

**Interface move** (after Phase 1 or alongside it):
- Move `abstract class LlmClient` + `sealed class LlmChunk` family out of `cli/lib/src/agent/agent.dart` into `cli/lib/src/llm/llm.dart` (new file). Update 4 provider imports + 3 test files + `agent.dart` itself.

**Factory wiring:** `cli/lib/src/providers/llm_client_factory.dart` keeps current shape — it still calls `adapter.createClient()`. Each `*Provider` returns `this` from `createClient()` (since it implements `LlmClient` directly). Alternative: rename the method to `build()` at the end of the task. Keep for now; rename is a separate polish pass.

**Tests to consolidate:**
- `cli/test/providers/{anthropic,openai_compatible,ollama,copilot}_adapter_test.dart` + `cli/test/llm/{anthropic,openai,ollama}_client_test.dart` → `cli/test/providers/{anthropic,openai,ollama,copilot}_provider_test.dart` (one per vendor). Same test logic; imports repointed. `copilot_token_manager_test.dart` stays as-is. `message_mapper_test.dart` stays (mappers unmoved).

**MessageMapper:** untouched. Each `*Provider` instantiates its mapper as a `const` field (same pattern the clients use today).

**Out of scope:** Renaming `createClient()` → `build()`. Unifying `LlmClientFactory` into a `ProviderFactory`. These are optional polish for a later task.

**Verification:**
```sh
cd cli && dart analyze --fatal-infos
cd cli && dart test
cd cli && just check
# Sanity-check the Copilot device flow only if you have a GitHub test account;
# otherwise rely on copilot_provider_test.dart + copilot_token_manager_test.dart.
```

---

## Task 4 — Codify the arg-completer convention

**Goal:** Eliminate ~40 LoC of boilerplate across 6 controllers + simplify `register_builtin_slash_commands.dart`. Introduce one typedef + closure-factory pattern so controllers don't each redeclare a forward method.

**Current shape:**
- Typedef `SlashArgCompleter` already exists at `cli/lib/src/commands/slash_commands.dart:23–26`.
- Each of 6 controllers (`model`, `skills`, `session`, `provider`, `system`, `share`) declares a `*ArgCandidates(prior, partial)` method that delegates to a pure function in `arg_completers.dart`, filtering on priorArgs length + pulling live state (catalog, skill list) as needed.
- Modules in `register_builtin_slash_commands.dart` call `registry.attachArgCompleter(name, context.controller.*ArgCandidates)`.

**Target shape:**
- Rename or alias the typedef to `ArgCompleter` in `slash_commands.dart` (drop the `Slash` prefix — it's already scoped by the folder).
- Move the priorArgs/partial-filter boilerplate into `arg_completers.dart` as closure factories that take the live-state dependencies directly, e.g.:
  ```dart
  ArgCompleter modelArgCompleter(Config config) =>
      (prior, partial) {
        if (prior.isNotEmpty) return const [];
        final cfg = config.current;
        if (cfg == null) return const [];
        return modelRefCandidates(cfg.catalogData.providers, partial);
      };
  ```
- Drop the `*ArgCandidates` methods on the 6 controllers entirely.
- `attachArgCompleters()` in each module calls the factory with the dependencies it already has:
  ```dart
  @override
  void attachArgCompleters(registry, context) {
    registry.attachArgCompleter('model', modelArgCompleter(context.config));
    registry.attachArgCompleter('skills', skillsArgCompleter(context.skillRuntime));
    // …
  }
  ```

**Files to edit:**
- `cli/lib/src/commands/slash_commands.dart` — add `typedef ArgCompleter = ...` (keep `SlashArgCompleter` as deprecated alias, or rename outright; lean toward outright rename since this is a cohesive refactor branch).
- `cli/lib/src/commands/arg_completers.dart` — add 6 closure-factory functions (`modelArgCompleter`, `sessionArgCompleter`, `skillsArgCompleter`, `providerArgCompleter`, `openArgCompleter`, `shareArgCompleter`). Keep the low-level pure functions; factories wrap them.
- `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` — 6 modules' `attachArgCompleters()` bodies get shorter; no change to `register()`.
- `cli/lib/src/share/share_module.dart` — same treatment.
- `cli/lib/src/runtime/controllers/{model,session,skills,provider,system,share}_controller.dart` — delete the 6 `*ArgCandidates` methods + their tests if any.

**Test update:** `cli/test/commands/slash_autocomplete_test.dart` may reference the controller methods directly; swap to invoking the factory-returned closures instead.

**Verification:**
```sh
cd cli && just check
cd cli && dart run bin/glue.dart   # interactive smoke: tab-complete /model, /skills, /provider
```

---

## Task 3 — Audit + rename slash commands for ergonomics (runs after Task 4 lands)

**Goal:** Produce a rename table first, agree with user on renames, then implement. Touches mostly strings in `register_builtin_slash_commands.dart` once Task 4 has shipped the cleaner registration shape.

**Audit inputs (already collected):** 17 commands — `/help /clear /exit /tools /debug /approve /model (/models) /session /history /resume /rename /skills /share /provider /paths (/where) /config /open`. Survey of Claude Code + OpenCode naming for comparison is in the exploration report.

**Workflow:**
1. Build rename proposal table with columns: current → proposed → rationale → breaking? (alias kept for back-compat?). Save as `docs/plans/2026-04-24-slash-command-audit.md`.
2. **Loop with user for approval** (ExitPlanMode-equivalent checkpoint) before any string edits.
3. Implement approved renames:
   - `registry.register(SlashCommand(name: ...))` strings in `register_builtin_slash_commands.dart` + `share_module.dart`.
   - Any hidden aliases (current: `models → model`, `quit → exit`, `q → exit`, `where → paths`).
   - `buildHelpLines()` in `system_controller.dart` regenerates from registry — no manual edit needed.
4. Update tests that reference command names by string (`cli/test/commands/slash_autocomplete_test.dart`, `cli/test/commands/builtin_commands_test.dart`, etc.).
5. Update docs: `docs/plans/2026-04-24-cli-roadmap.md` + any README references.

**Rename candidates worth considering** (for the audit doc — not a final list):
- None of the 17 names is obviously broken. Exploration found current naming concise and consistent. The highest-value audit outcomes are likely:
  - Making `/session` action grammar uniform (`/session copy` today, `/session new`? `/session rename`?).
  - Deciding whether `/config` and `/config init` should split into `/config edit` + `/config init` (symmetry with `glue config init|show` at the CLI).
  - Deciding whether `/provider` subcommands (add/remove/test) are worth top-level aliases.
  - Dropping `/models` (alias of `/model`) if the plural is confusing.

**Out of scope:** Major restructures (e.g. moving slash commands to a noun-verb scheme `/model switch`, `/skill activate`). That's a bigger UX decision and should be its own plan.

**Verification:**
```sh
cd cli && just check
cd cli && dart run bin/glue.dart   # interactive smoke: each renamed command still works + old name errors cleanly if alias removed
```

---

## Execution plan

**Batch 1 (concurrent, shared branch):**
- Agent A → Task 1 (test coverage only — adds files; reads source)
- Agent B → Task 2 (providers + llm merge, all 4 vendors)
- Agent C → Task 4 (codify arg-completer)

Each agent commits independently on `refactor/c1-turn`. Because file sets are disjoint (verified above), concurrent commits rebase cleanly.

**Gate after Batch 1:** Run `just check` on the merged state. Confirm analyzer clean + all tests green + binary builds. Review the Task 2 Copilot work carefully — OAuth is the highest-risk change in this batch.

**Batch 2 (sequential):**
- Agent D → Task 3 (audit doc + user-gated rename implementation). Starts after Task 4 has landed so it operates on the cleaner arg-completer shape.

---

## Known risks

- **Concurrent commits on one branch** — `git pull --rebase` between every push. If Task 2 moves `LlmClient` interface before Task 1's tests land, Task 1's test imports need a small post-hoc adjustment.
- **Task 2 Copilot merge** — OAuth device-code flow is ~114 LoC inside the new `CopilotProvider`. Testing must confirm `beginInteractiveAuth` + `freshCopilotToken` refresh still work. If the test suite can't hit a real GitHub account, lean on unit tests with mocked HTTP (pattern exists in `copilot_adapter_test.dart`).
- **Task 4 alias vs. rename of `SlashArgCompleter`** — rename is cleaner in a refactor branch but risks collisions if there are any third-party call-sites. Confirmed: only internal use. Outright rename.
- **Review.md open concerns** stay open — Task 1 documents them as `known-issue` tests; a separate fix commit (post-Batch-1) flips them to passing.

---

## Critical files (quick index)

- `cli/lib/src/runtime/turn.dart` — Turn lifecycle (Task 1)
- `cli/lib/src/runtime/transcript.dart` — Transcript primitive (Task 1)
- `cli/lib/src/runtime/input_router.dart` — Input priority stack (Task 1)
- `cli/lib/src/shell/bash_mode.dart` — Bash `!`-mode (Task 1)
- `cli/lib/src/runtime/renderer.dart` — 60fps scheduler + spinner (Task 1)
- `cli/lib/src/runtime/services/{config,session}.dart` — runtime services (Task 1)
- `cli/lib/src/providers/{anthropic,openai_compatible,ollama,copilot}_adapter.dart` (Task 2)
- `cli/lib/src/llm/{anthropic,openai,ollama}_client.dart` (Task 2)
- `cli/lib/src/providers/llm_client_factory.dart` — stays, re-wired (Task 2)
- `cli/lib/src/agent/agent.dart` — `LlmClient` interface moves out (Task 2)
- `cli/lib/src/commands/{slash_commands,arg_completers}.dart` (Task 4)
- `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` (Tasks 4 + 3)
- `cli/lib/src/runtime/controllers/*.dart` (Task 4)
- `docs/plans/2026-04-24-slash-command-audit.md` — new artifact (Task 3)

---

## End-to-end verification (post Batch 2)

```sh
cd cli
just check                # gen-check + analyze + test
just e2e                  # Ollama-backed real-model loop (optional but recommended)
dart run bin/glue.dart    # interactive smoke — run /help, /tools, each renamed command,
                          # tab-complete /model + /skills + /provider, toggle /debug + /approve,
                          # issue a real turn, cancel it, start a shell command via `!`
```

If all green: proceed to Task 5 (context-window merge from `origin/main`) per handoff doc, then Task 6 (smoke + merge to main). Those are out of scope for this plan.
