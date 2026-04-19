# Dart DevTools Integration for Glue

## Overview

Add developer-only observability to Glue using `dart:developer` primitives and a custom DevTools extension. All instrumentation is zero-cost in AOT-compiled binaries (the installed `glue` binary) — it only activates when running in JIT mode with `--enable-vm-service`.

Two phases: Phase A instruments the codebase with `dart:developer` primitives (Timeline, log, service extensions) that work with built-in DevTools views. Phase B builds a custom DevTools extension with Glue-specific UI panels.

## Phase A: Instrumentation Layer

### New file: `lib/src/dev/devtools.dart`

A single module centralizing all `dart:developer` instrumentation. Business logic files call lightweight methods from here — no `dart:developer` imports scattered across the codebase.

#### Structured Logging

Wraps `dart:developer log()` with predefined categories. Each category maps to a filterable name in DevTools Logging view.

Categories:
- `llm.request` — HTTP request start/end, model, token counts
- `llm.stream` — Per-chunk streaming events (opt-in, very noisy)
- `tool.exec` — Tool invocation and result
- `tool.bash` — Bash-specific execution details
- `agent.loop` — ReAct iteration boundaries
- `agent.subagent` — Subagent spawn/complete
- `render.frame` — Render cycle metrics
- `render.slow` — Frames exceeding 16ms budget (level: WARNING)
- `input.key` — Key event processing (opt-in, very noisy)
- `session.io` — Session persistence read/write
- `shell.job` — Background job lifecycle

Falls through to existing `DebugLogger` for file logging so both work simultaneously.

#### Timeline Helpers

Thin wrappers around `Timeline` and `TimelineTask`:
- `GlueDev.timeSync(name, fn, {args})` — synchronous span
- `GlueDev.startAsync(name, {args})` — returns `TimelineTask` for async spans
- Pre-defined `UserTag` constants for CPU profiler filtering: `tagRender`, `tagLlmStream`, `tagToolExec`, `tagAgentLoop`

#### Service Extensions

Registered once at startup via `GlueDev.init(app)`. Each returns a JSON snapshot of internal state, queryable from DevTools or any VM service client.

| Extension | Returns |
|-----------|---------|
| `ext.glue.getAgentState` | `{mode, iteration, pendingTools, tokenCount, model}` |
| `ext.glue.getConversation` | Conversation history (truncated to last N messages) |
| `ext.glue.getConfig` | Resolved config values |
| `ext.glue.getSessionInfo` | `{sessionId, messageCount, startTime}` |
| `ext.glue.getToolHistory` | Last N tool calls with name, args summary, duration, result size |

#### Event Posting

Pushes structured events via `postEvent()` for the custom DevTools extension to consume. No-op if nobody is listening.

| Event Kind | Data |
|------------|------|
| `glue.agentStep` | `{iteration, toolsChosen, tokenDelta, loopReason}` |
| `glue.toolExec` | `{tool, argsSummary, durationMs, resultSizeBytes}` |
| `glue.llmRequest` | `{provider, model, ttfbMs, streamDurationMs, inputTokens, outputTokens}` |
| `glue.renderMetrics` | `{frameMs, blockCount, lineCount, overBudget}` |

### Instrumentation Points in Existing Files

Each change is 2-5 lines (import + method call at entry/exit boundaries):

#### `bin/glue.dart`
- After `App.create()`, before `app.run()`: call `GlueDev.init(app)` to register service extensions and start the root timeline span.

#### `app.dart`
- `_startAgent()`: `Timeline.startSync('AgentReactLoop')` at method entry. Emit `GlueDev.log('agent.loop', 'started')`.
- `_handleAgentEvent()`: `GlueDev.log('agent.event', event.runtimeType.toString())` at top of the switch. For `AgentDone`: `Timeline.finishSync()`.
- `_doRender()`: Wrap body in `Timeline.timeSync('RenderFrame', () { ... })`. Measure wall time with `Stopwatch`. If > 16ms, `GlueDev.log('render.slow', ...)` at WARNING level. Post `glue.renderMetrics` event.
- `_executeAndCompleteTool()`: `Timeline.timeSync('ToolExec:${call.name}', () { ... })`. Post `glue.toolExec` event with duration.

#### `agent_core.dart`
- `run()`: Create `TimelineTask()..start('ReActLoop')` before the `while(true)`. Call `task.finish()` after loop exits.
- Inside the while loop: after each `llm.stream()` completes, post `glue.agentStep` with iteration count, tools chosen, and token delta.
- LLM streaming: create a `Flow.begin()` when entering `await for`, `Flow.end()` when the stream completes. This connects the LLM request to the tool execution visually in Timeline.

#### `anthropic_client.dart` / `openai_client.dart`
- `stream()`: Create `TimelineTask()..start('LlmStream:$model')` before the HTTP request. Record TTFB timestamp when first `TextDelta` is yielded. Call `task.finish(arguments: {ttfbMs, totalMs, tokens})` at end. Post `glue.llmRequest` event.

#### `tools.dart`
- Each `Tool.execute()`: Wrap body in `Timeline.timeSync('Tool:$name', () => ...)`. Log via `GlueDev.log('tool.exec', '$name completed in ${ms}ms')`. Post `glue.toolExec` event.
- `BashTool.execute()` specifically: additional `GlueDev.log('tool.bash', 'command: $command')` and process lifecycle logging.

#### `shell_job_manager.dart`
- `start()`: `GlueDev.log('shell.job', 'started: $command')` after process start.
- On job exit/error: `GlueDev.log('shell.job', 'exited: $id code=$exitCode')`.

#### `agent_manager.dart`
- `spawnSubagent()`: Wrap in `Timeline.timeSync('Subagent:depth$depth', () => ...)`. Log spawn and completion. Post `glue.agentStep` with subagent context.
- `spawnParallel()`: Timeline span covering the `Future.wait()`.

#### `debug_logger.dart`
- No changes. Continues to work as-is. `GlueDev.log()` calls it internally as a fallback.

### Justfile Recipes

Added to `cli/justfile`:

```just
# Run with DevTools observability (dev only, JIT mode)
dev *ARGS:
    dart run --enable-vm-service --timeline_streams=Dart bin/glue.dart {{ARGS}}

# Run with DevTools, paused at start for debugger attachment
dev-pause *ARGS:
    dart run --enable-vm-service --pause-isolates-on-start --timeline_streams=Dart bin/glue.dart {{ARGS}}

# Run with DevTools and print connection URL prominently
dev-profile *ARGS:
    @echo "Starting Glue with profiling enabled..."
    dart run --enable-vm-service --timeline_streams=VM,Isolate,GC,Dart bin/glue.dart {{ARGS}}
```

### VS Code Launch Config

Add `.vscode/launch.json` with DevTools-aware configuration:

```json
{
  "configurations": [
    {
      "name": "Glue (DevTools)",
      "type": "dart",
      "request": "launch",
      "program": "cli/bin/glue.dart",
      "vmAdditionalArgs": ["--timeline_streams=VM,Isolate,GC,Dart"]
    }
  ]
}
```

## Phase B: Custom DevTools Extension

### Package Structure

A separate Flutter web package alongside the CLI:

```
salvador/
  cli/                              ← Existing CLI package
    extension/
      devtools/
        config.yaml                 ← Extension discovery metadata
        build/                      ← Pre-compiled Flutter web (generated)
  glue_devtools_extension/          ← NEW: Flutter web app
    lib/
      main.dart                     ← DevToolsExtension wrapper
      src/
        panels/
          agent_tree_panel.dart     ← Agent decision tree
          llm_metrics_panel.dart    ← Token flow & latency charts
          tool_timeline_panel.dart  ← Tool execution gantt chart
          state_inspector_panel.dart ← Live state query UI
        services/
          glue_service.dart         ← Calls ext.glue.* service extensions
          event_stream.dart         ← Listens to glue.* postEvent streams
    pubspec.yaml
```

### config.yaml

```yaml
name: glue
issueTracker: https://github.com/user/glue/issues
version: 0.1.0
materialIconCodePoint: "0xe3ae"
requiresConnection: true
```

### Communication Pattern

```
Glue CLI (dart:developer)          DevTools Extension (Flutter web)
─────────────────────────          ────────────────────────────────
registerExtension('ext.glue.*')  ◄── serviceManager.callServiceExtension()
postEvent('glue.*', data)        ──► serviceManager.onExtensionEvent.listen()
```

### Extension Panels

#### Panel 1: Agent Decision Tree

Shows each ReAct iteration as a node in a tree. Data source: `glue.agentStep` events.

Each node displays:
- Iteration number
- Tools chosen (or "final response")
- Token delta for that iteration
- Expandable: full tool call arguments and result summary

Interactive: click a node to query `ext.glue.getConversation` and show the relevant messages.

#### Panel 2: LLM Metrics Dashboard

Charts built from `glue.llmRequest` events:
- TTFB (time to first byte) per request — line chart over time
- Tokens/second streaming throughput — bar chart
- Input vs output token ratio — stacked bar
- Cumulative token usage — running total
- Provider/model breakdown

#### Panel 3: Tool Execution Timeline

Gantt-style chart from `glue.toolExec` events:
- Each tool call as a horizontal bar, length = duration
- Color-coded by tool type (Bash=red, ReadFile=blue, Grep=green, etc.)
- Sortable by duration to find bottlenecks
- Aggregated stats: avg duration per tool type, total time in tools vs LLM

#### Panel 4: State Inspector

Live query interface for all `ext.glue.*` service extensions:
- Buttons to query each extension
- JSON tree view of results
- Auto-refresh toggle (poll every 2s)
- Shows: current mode, token count, active model, session info, config

### Build & Distribution

```bash
# From glue_devtools_extension/:
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../cli/extension/devtools

# Validate:
dart run devtools_extensions validate --package=../cli
```

Add justfile recipe:
```just
# Build the DevTools extension
build-devtools:
    cd ../glue_devtools_extension && dart run devtools_extensions build_and_copy --source=. --dest=../cli/extension/devtools
```

### Development Workflow for the Extension

Use simulated DevTools environment for fast iteration:
```bash
cd glue_devtools_extension
flutter run -d chrome --dart-define=use_simulated_environment=true
```

## Limitations

- **JIT only:** All Timeline, log, service extensions, and profiling require `dart run` (JIT mode). The AOT-compiled binary (`dart compile exe`) strips VM service infrastructure. This is desirable for developer-only tooling — zero cost in production.
- **No retroactive capture:** `postEvent()` drops events silently if DevTools isn't connected. Events before connection are lost. Mitigation: buffer last N events in a ring buffer inside `GlueDev` and serve via `ext.glue.getRecentEvents`.
- **Browser context switch:** DevTools runs in Chrome. Developer switches between terminal (Glue TUI) and browser (DevTools). No way to render DevTools inside the terminal.
- **Flutter SDK required for Phase B:** Building the custom extension requires Flutter SDK, not just Dart SDK. This is only needed for extension development, not for using Phase A instrumentation.
- **No hot reload for CLI:** Code changes require restarting Glue. The extension itself supports Flutter hot restart for faster UI iteration.
- **Single isolate:** Service extensions are registered per-isolate. Glue currently runs in one isolate, so this is simple. If subagents move to separate isolates in the future, each would need its own registrations.
- **Raw mode conflict:** Glue's raw terminal mode means the VM service URL printed to stdout gets overwritten when the TUI starts. The justfile recipes and VS Code config handle this by managing the URL automatically.

## The 5 Interesting Things

### 1. LLM Request Flow Tracing
In `anthropic_client.dart`, create `Flow.begin()` when HTTP request starts, `Flow.step()` on first `TextDelta` (TTFB marker), `Flow.end()` on `message_stop`. In DevTools Timeline, connected arrows show the full streaming lifecycle. Add `arguments: {model, inputTokens, ttfbMs}` for hover-to-inspect.

### 2. Agent Decision Tree Visualization
The custom extension's star feature. Each ReAct iteration posts `glue.agentStep` with `{iteration, toolsChosen, tokenDelta}`. The extension renders an expandable tree where each node shows what the agent decided and why. Click to drill into the full conversation at that point via `ext.glue.getConversation`.

### 3. Render Frame Budget Monitor
`_doRender()` measures wall time. Frames > 16ms log at WARNING level to `render.slow`. Timeline shows each frame as a bar — visually obvious when frames exceed budget. The custom extension's metrics panel tracks frame time distribution over the session.

### 4. Tool Cost Tracker
Every `Tool.execute()` posts `glue.toolExec` with timing. The custom extension aggregates into a dashboard: "Bash avg 2.3s, ReadFile avg 12ms, Grep avg 340ms, 73% of wall time spent in tools". Identifies which tools are bottlenecks during agent loops.

### 5. Interactive State Inspector
Service extensions (`ext.glue.getAgentState`, etc.) let you query live state without print statements or restarts. Works from DevTools UI, the custom extension's inspector panel, or even `curl` against the VM service WebSocket. Invaluable for debugging stuck agents or unexpected behavior mid-session.
