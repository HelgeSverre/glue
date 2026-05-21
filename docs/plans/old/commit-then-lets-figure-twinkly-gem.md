# Port: context-window management onto refactor/c1-turn

## Context

Why this work exists:
- `origin/copilot/add-context-window-management-system` (2 commits, +1554/-18 lines, 19 files) was branched from `f7d103c` on `main` and adds a three-tier context-window management system to the Glue agent loop: token budget, estimator with EMA calibration, sliding-window trimmer, tool-result trimmer, LLM-backed conversation compactor, and provider-agnostic overflow detection.
- Since then, the `refactor/c1-turn` branch has split the CLI into `bin → boot → runtime → {agent,tools,session,…}` layers, **deleted** `core/service_locator.dart` (which the copilot branch depends on for wiring), gutted `app.dart` into `runtime/`, and renamed `AgentCore` → `Agent`. The copilot branch will not merge cleanly anywhere — neither to current `main` nor to `refactor/c1-turn`.
- Decision (confirmed): land the feature directly on `refactor/c1-turn`, keep all three tiers, and rewrite the wiring to use `boot/wire.dart` instead of the deleted service locator. No follow-up port to old-shape `main` is needed because `refactor/c1-turn` is the future of the codebase.

Outcome: the Agent loop trims/compacts the conversation before every LLM call, recovers from provider overflow errors, exposes `/compact` to the user, and reads `context:` config from `~/.glue/config.yaml`.

There is also one trailing uncommitted edit on `CLAUDE.md` (architecture-section refresh for the c1-turn refactor) that the user asked to commit first.

## Step 0 — Commit pending CLAUDE.md change

Stage and commit only `CLAUDE.md` with a focused message describing the doc refresh against the new `boot/cli/runtime/share` layout. No other changes ride along.

## Step 1 — Copy the standalone context module

These files are self-contained on the copilot branch (no service-locator dependency). Copy them verbatim, then run `dart format` and `dart analyze` to catch any import-path drift.

Source: `git show origin/copilot/add-context-window-management-system:<path>` for each.

Files to add:
- `cli/lib/src/context/context_config.dart`
- `cli/lib/src/context/context_budget.dart`
- `cli/lib/src/context/context_estimator.dart`
- `cli/lib/src/context/conversation_compactor.dart`
- `cli/lib/src/context/overflow_handler.dart`
- `cli/lib/src/context/sliding_window_trimmer.dart`
- `cli/lib/src/context/tool_result_trimmer.dart`
- `cli/lib/src/context/context_manager.dart`

Tests to add (mirror the same path under `test/`):
- `cli/test/context/context_budget_test.dart`
- `cli/test/context/context_estimator_test.dart`
- `cli/test/context/context_manager_test.dart`
- `cli/test/context/overflow_handler_test.dart`
- `cli/test/context/sliding_window_trimmer_test.dart`
- `cli/test/context/tool_result_trimmer_test.dart`

Imports inside these files must use `package:glue/...` (lint rule `always_use_package_imports`). If any copied file uses relative imports, fix on the way in.

## Step 2 — Add `ContextConfig` to `GlueConfig`

File: `cli/lib/src/config/glue_config.dart` (~729 lines).

Mirror the copilot diff (~22 lines), but place it next to existing optional sub-configs (e.g. `ObservabilityConfig`) for consistency:
- New field `final ContextConfig contextConfig;`
- Parse YAML `context:` block in the loader (keys: `auto_compact`, `compact_threshold`, `critical_threshold`, `keep_recent_turns`, `tool_result_trim_after`)
- Add `contextConfig` to `copyWith()`
- Default to `ContextConfig.defaults()` when the section is absent

## Step 3 — Wire `ContextManager` in `boot/wire.dart` (replace service_locator)

File: `cli/lib/src/boot/wire.dart`, around lines 116–125 where `Agent` is constructed.

The copilot branch's `core/service_locator.dart` is the spec for what to wire — but we re-implement that wiring inline in `wireAppContext()` per the refactor's explicit-wiring rule (`refactor/GOAL.md`).

Sequence to add **after** the existing `final agent = Agent(...)` and **before** `return AppContext(...)`:
1. Resolve the model definition for the active model (already in scope via `config.activeModel`; use the catalog if a `ModelDef` lookup is needed for context-window size).
2. Construct `ContextBudget.fromModelDef(modelDef, config: config.contextConfig)`.
3. If `config.smallModel` is set, build a small-model `LlmClient` via `llmFactory` for the compactor; otherwise pass `null` (Tier 2 disabled, Tiers 1+3 still work).
4. Construct `ContextManager.fromBudget(budget, compactor: smallClient, obs: obs, autoCompact: contextConfig.autoCompact, systemPrompt: systemPrompt)`.
5. Assign `agent.contextManager = contextManager;` (the field must exist on `Agent` — added in Step 4).

Do **not** introduce a service locator. All dependencies are passed by the caller.

## Step 4 — Integrate context manager into the Agent loop

File: `cli/lib/src/agent/agent.dart` (`class Agent` at line 165).

Add nullable field on `Agent`:
- `ContextManager? contextManager;` (mutable, set by `boot/wire.dart`)

In `Stream<AgentEvent> run(String userMessage)`, around the existing `await for (final chunk in llm.stream(_conversation, ...))` at lines 268–269:

1. **Before** the `llm.stream(...)` call: prepare the message list.
   ```
   final prepared = contextManager != null
       ? await contextManager!.prepareForLlm(_conversation)
       : _conversation;
   ```
   Pass `prepared` to `llm.stream(...)` instead of `_conversation`.
2. **Wrap** the `await for` in a try/catch. On exception, call `OverflowClassifier.classify(e)`. If overflow:
   - At most once per top-level user turn, call `contextManager!.requestEmergencyTrim(_conversation)` and re-enter the loop (retry the LLM call with freshly-prepared messages).
   - Otherwise rethrow.
3. **After** the `UsageInfo` chunk handling at line ~296: if `contextManager != null`, call `contextManager!.estimator.calibrate(lastRawEstimate, usage.inputTokens)` to update EMA. Capture the raw estimate just before the LLM call so it's available here.

Keep the existing observability spans intact; the prepared-vs-raw message count delta is interesting and worth recording on the `llm.stream` span as `llm.context.prepared_count`.

## Step 5 — Add `/compact` slash command

File: `cli/lib/src/ui/slash/app_commands.dart` (line 15: `registerCoreSlashCommands(AppCommands commands, AppActions actions)`).

Follow the existing `commands.register(SlashCommand(...))` pattern used by `/clear`, `/help`, etc. The handler:
- Calls `await actions.agent.contextManager?.forceCompact(actions.agent.conversation.toList())`.
- Renders the resulting `CompactionResult` (freed tokens, summary tokens) via `actions`/the renderer.
- Falls back to a friendly "context window already fits" or "context management is disabled" message when the manager is null or the result indicates no-op.

If `AppActions` doesn't expose `agent` directly, add a minimal accessor — don't widen the surface beyond what `/compact` needs.

## Step 6 — Update barrel export

File: `cli/lib/glue.dart`.

Add the 10 export lines from the copilot diff:
- `ContextConfig`, `ContextBudget`, `ContextEstimator`, `ToolResultTrimmer`, `SlidingWindowTrimmer`, `ConversationCompactor`, `OverflowHandler`, `ContextManager`, `CompactionResult`.

## Step 7 — Quality gate + verification

From `cli/`:
- `dart format .`
- `just analyze` — must pass (also enforces the `ui/` layering rule: `context/` must not be imported from `ui/`).
- `just gen-check` — should be untouched (no model catalog changes).
- `dart test test/context/` — run the ported unit tests in isolation first.
- `dart test` — full suite.
- Manual smoke: `dart run bin/glue.dart` with a tiny model (e.g. ollama qwen3:1.7b), drive a long conversation past the `compactAt` threshold, verify a) auto-compact trips, b) `/compact` works on demand, c) provider overflow on Anthropic/OpenAI is recovered (synthesize by setting `compact_threshold` very low in `~/.glue/config.yaml`).
- Doctor sanity: `dart run bin/glue.dart doctor` should still report green.

## Commit shape (suggested)

Three commits to keep review tractable:
1. `chore(docs): refresh CLAUDE.md for c1-turn boot/runtime split` (Step 0).
2. `feat(context): add token budget, estimator, trimmers, compactor, overflow handler` (Steps 1, 2, 6, plus tests). Module + config + exports only — no runtime wiring yet, so the tree compiles and tests pass.
3. `feat(agent): wire ContextManager into Agent loop and /compact command` (Steps 3, 4, 5). The integration commit.

## Critical files

Read / modify list:
- `cli/lib/src/agent/agent.dart` — Agent loop, line ~268 (`llm.stream`), line ~296 (`UsageInfo`).
- `cli/lib/src/boot/wire.dart` — composition root, lines 116–125 + just before `return AppContext`.
- `cli/lib/src/config/glue_config.dart` — config schema + YAML loader.
- `cli/lib/src/ui/slash/app_commands.dart` — slash command registration pattern.
- `cli/lib/glue.dart` — barrel exports.
- `cli/lib/src/context/*` — new module (8 files copied from copilot branch).
- `cli/test/context/*` — new tests (6 files copied).
- Reference only (do **not** copy): `git show origin/copilot/add-context-window-management-system:cli/lib/src/core/service_locator.dart` — the spec for what to wire in `boot/wire.dart`.

## Out of scope (explicit non-goals)

- Re-introducing `core/service_locator.dart` in any form. The refactor explicitly removed it.
- Porting to `main`. The refactor branch is the destination.
- Changing the public LLM client / tool interfaces.
- Tuning default thresholds — ship the copilot branch's defaults and iterate later.
