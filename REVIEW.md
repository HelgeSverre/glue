# Review

## Blocker

### Parallel subagents reuse the parent turn's Zone holder
`Turn.run` installs one `runInContext` for the parent turn, but `Subagents.spawnParallel` starts sibling subagents inside that same Zone and `spawn` calls `agent.runHeadless` without creating a fresh observability context. `Agent.run` then mutates `obs.activeSpan` around each LLM stream, so parallel subagents can save/restore each other's `llm.stream` span and leave a stale active span in the parent holder. The tests prove isolation only when each concurrent task explicitly enters its own `runInSpan`/`runInContext` (`cli/test/observability/observability_test.dart:301`, `cli/test/observability/observability_test.dart:321`); the real subagent tests only assert returned text.  
`cli/lib/src/agent/subagents.dart:124`

## Strong Concern

### Interactive `AgentError` ends the turn span as success
`Agent.run` catches failures and yields `AgentError`; the interactive `Turn` handler appends the error and sets idle state, but does not end `agent.turn` with error metadata. The subscription `onDone` then calls `_endSpan()` with no error, while `runPrint` handles `AgentError` by marking the span as failed. That makes interactive failed turns look successful at the parent-span level. I found no test covering this event path; `AgentError` is only asserted indirectly by switch exhaustiveness.  
`cli/lib/src/runtime/turn.dart:376`

### Print-mode teardown is skipped before the turn starts
`_runPrintMode` has early returns for bare `--resume`, missing resume targets, and missing prompts before the `try/finally` that disposes tools, flushes/closes observability, and closes the session. Exceptions before `turn.runPrint` is entered, such as expansion failures, also bypass that cleanup. `App.run` has no outer print-mode lifecycle cleanup, so these failure modes leak app-level resources. Existing tests cover parser/prompt shaping, not teardown.  
`cli/lib/src/app.dart:436`

### `Turn.run` has no live-run guard
Calling `run()` twice on the same `Turn` appends a second user block, overwrites `_span` and `_sub`, and leaves the first subscription able to keep mutating the same `Transcript`/`Session`; `cancel()` can only see the latest subscription/span. `App` currently constructs a fresh `Turn` per submit, but `Turn` is now the lifecycle owner and its double-run behavior should be explicit. There is no direct `Turn` test for double-run or cancellation races.  
`cli/lib/src/runtime/turn.dart:73`

## Nit

None.

## Checked With No Finding

The UI layering check passes, and `cli/lib/src/ui/**` has no imports from feature modules or `runtime/`. Controllers under `runtime/controllers/` do not import `app.dart` or `app/`; feature modules do not reach into `App` private fields. `Panels`, `Docks`, `Confirmations`, `Config`, and `Session` have not grown feature-specific helpers beyond the documented session/config responsibilities. `PermissionGate` reads the current trusted-tool set through `permissionGateFactory`, and `Config.trustedTools` exposes the backing set, so `trustTool()` is visible mid-turn. `Agent.runHeadless` drives `run()` and switches over `AgentEvent`, so it does not duplicate the lower-level `LlmChunk` streaming loop. The deleted `lib/glue.dart` barrel is not referenced; tests import `src/` directly, which is consistent with the binary-only decision.

## Context-Window Merge Punch List

- Change all new context imports from `package:glue/src/agent/agent_core.dart` to `package:glue/src/agent/agent.dart`; update tests the same way.
- Reintroduce `ContextManager? contextManager` on the renamed `Agent`, or inject an equivalent into `Agent.run`; do not resurrect `AgentCore`.
- Merge `prepareForLlm` before `llm.stream` while preserving current `agent.iteration` and `llm.stream` spans, especially the `finally` that restores `activeSpan`.
- Add overflow retry inside the current LLM stream try/catch without bypassing `llmSpan` ending or `iterationSpan` accounting.
- Add estimator calibration to the current `UsageInfo` branch, which now tracks prompt/completion totals separately.
- Wire context construction in `ServiceLocator` after the current `Agent` creation and before `Subagents`; use `Subagents`, not `AgentManager`, and keep `providers/llm_client_factory.dart`.
- Merge `GlueConfig.contextConfig` through constructor, field, `copyWith`, and `load` without dropping the current OTLP observability and title-generation fields.
- Add `/compact` through `runtime/commands/register_builtin_slash_commands.dart` and a controller method, not by registering directly in `App`.
- Do not restore `lib/glue.dart`; expose context code only through direct `package:glue/src/...` imports in tests and internal files.

End-goal verdict: yes on layered code and naming, because the UI/controller/app boundaries are materially cleaner; yes on narrow services, because features route through the named services and I found no App-private leaks; partially on streaming smoothness, because there is no pubsub/re-render regression, but the new async seams still have span-isolation and lifecycle gaps that should be fixed before merge.
