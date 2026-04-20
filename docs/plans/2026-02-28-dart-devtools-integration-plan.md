# Dart DevTools Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add developer-only observability to Glue using `dart:developer` primitives (Timeline, log, service extensions, postEvent) and justfile recipes for launching with DevTools.

**Architecture:** A single new module `lib/src/dev/devtools.dart` centralizes all `dart:developer` instrumentation. Existing files get 2-5 line changes each (import + method calls). All instrumentation is zero-cost in AOT builds.

**Tech Stack:** `dart:developer`, `dart:convert` (for JSON in service extension responses). No new pub dependencies.

**Design doc:** `docs/plans/2026-02-28-dart-devtools-integration-design.md`

---

### Task 1: Create the GlueDev instrumentation module

**Files:**

- Create: `cli/lib/src/dev/devtools.dart`
- Test: `cli/test/dev/devtools_test.dart`

**Step 1: Write the failing test**

Create `cli/test/dev/devtools_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/dev/devtools.dart';

void main() {
  group('GlueDev', () {
    test('log does not throw without initialization', () {
      // Should be safe to call before init — no-ops gracefully
      expect(() => GlueDev.log('test', 'hello'), returnsNormally);
    });

    test('timeSync executes function and returns result', () {
      final result = GlueDev.timeSync('test', () => 42);
      expect(result, 42);
    });

    test('startAsync returns a TimelineTask', () {
      final task = GlueDev.startAsync('test');
      expect(task, isNotNull);
      task.finish();
    });

    test('postToolExec does not throw', () {
      expect(
        () => GlueDev.postToolExec(
          tool: 'bash',
          durationMs: 123,
          resultSizeBytes: 456,
        ),
        returnsNormally,
      );
    });

    test('postAgentStep does not throw', () {
      expect(
        () => GlueDev.postAgentStep(
          iteration: 1,
          toolsChosen: ['bash'],
          tokenDelta: 100,
        ),
        returnsNormally,
      );
    });

    test('postLlmRequest does not throw', () {
      expect(
        () => GlueDev.postLlmRequest(
          provider: 'anthropic',
          model: 'claude-sonnet-4-6',
          ttfbMs: 200,
          streamDurationMs: 3000,
          inputTokens: 500,
          outputTokens: 1200,
        ),
        returnsNormally,
      );
    });

    test('UserTag constants are distinct', () {
      expect(GlueDev.tagRender.label, 'Render');
      expect(GlueDev.tagLlmStream.label, 'LlmStream');
      expect(GlueDev.tagToolExec.label, 'ToolExec');
      expect(GlueDev.tagAgentLoop.label, 'AgentLoop');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/dev/devtools_test.dart -v`
Expected: FAIL — file not found / cannot import

**Step 3: Write the implementation**

Create `cli/lib/src/dev/devtools.dart`:

```dart
import 'dart:convert';
import 'dart:developer';

/// Centralized developer instrumentation for Glue.
///
/// All `dart:developer` usage goes through this module. Business logic
/// files call these lightweight methods — no `dart:developer` imports
/// scattered across the codebase.
///
/// Everything here is a no-op in AOT-compiled binaries.
class GlueDev {
  GlueDev._();

  // ── UserTags for CPU profiler filtering ──────────────────────────────

  static final tagRender = UserTag('Render');
  static final tagLlmStream = UserTag('LlmStream');
  static final tagToolExec = UserTag('ToolExec');
  static final tagAgentLoop = UserTag('AgentLoop');

  // ── Structured logging ───────────────────────────────────────────────

  /// Emit a structured log event viewable in DevTools Logging view.
  ///
  /// [category] maps to the `name` field in DevTools (filterable).
  /// Categories: `llm.request`, `llm.stream`, `tool.exec`, `tool.bash`,
  /// `agent.loop`, `agent.subagent`, `render.frame`, `render.slow`,
  /// `shell.job`, `session.io`.
  ///
  /// [level] defaults to 0 (FINEST). Use 900 for WARNING, 1000 for SEVERE.
  static void log(String category, String message, {int level = 0, Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: category,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // ── Timeline helpers ─────────────────────────────────────────────────

  /// Wrap a synchronous operation in a Timeline span.
  static T timeSync<T>(String name, T Function() fn, {Map<String, dynamic>? args}) {
    return Timeline.timeSync(name, fn, arguments: args);
  }

  /// Start an async timeline task. Caller must call `.finish()` on the
  /// returned task when the operation completes.
  static TimelineTask startAsync(String name, {Map<String, dynamic>? args}) {
    final task = TimelineTask();
    task.start(name, arguments: args);
    return task;
  }

  // ── Event posting (for custom DevTools extension) ────────────────────

  /// Post a tool execution event.
  static void postToolExec({
    required String tool,
    required int durationMs,
    required int resultSizeBytes,
    String? argsSummary,
  }) {
    postEvent('glue.toolExec', {
      'tool': tool,
      'durationMs': durationMs,
      'resultSizeBytes': resultSizeBytes,
      if (argsSummary != null) 'argsSummary': argsSummary,
    });
  }

  /// Post an agent step event (one ReAct iteration).
  static void postAgentStep({
    required int iteration,
    required List<String> toolsChosen,
    required int tokenDelta,
  }) {
    postEvent('glue.agentStep', {
      'iteration': iteration,
      'toolsChosen': toolsChosen,
      'tokenDelta': tokenDelta,
    });
  }

  /// Post an LLM request completion event.
  static void postLlmRequest({
    required String provider,
    required String model,
    required int ttfbMs,
    required int streamDurationMs,
    required int inputTokens,
    required int outputTokens,
  }) {
    postEvent('glue.llmRequest', {
      'provider': provider,
      'model': model,
      'ttfbMs': ttfbMs,
      'streamDurationMs': streamDurationMs,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    });
  }

  /// Post render metrics event.
  static void postRenderMetrics({
    required double frameMs,
    required int blockCount,
    required int lineCount,
    required bool overBudget,
  }) {
    postEvent('glue.renderMetrics', {
      'frameMs': frameMs,
      'blockCount': blockCount,
      'lineCount': lineCount,
      'overBudget': overBudget,
    });
  }

  // ── Service extensions ───────────────────────────────────────────────

  /// Register all Glue service extensions. Call once at startup.
  ///
  /// [stateProvider] is a callback that returns a JSON-serializable map
  /// for a given extension name.
  static void registerExtensions(Map<String, dynamic> Function(String) stateProvider) {
    for (final name in ['getAgentState', 'getConfig', 'getSessionInfo', 'getToolHistory']) {
      registerExtension('ext.glue.$name', (method, params) async {
        try {
          final data = stateProvider(name);
          return ServiceExtensionResponse.result(jsonEncode(data));
        } catch (e) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            e.toString(),
          );
        }
      });
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/dev/devtools_test.dart -v`
Expected: All 7 tests PASS

**Step 5: Commit**

```bash
git add cli/lib/src/dev/devtools.dart cli/test/dev/devtools_test.dart
git commit -m "feat: add GlueDev instrumentation module (dart:developer)"
```

---

### Task 2: Add barrel export for GlueDev

**Files:**

- Modify: `cli/lib/glue.dart`

**Step 1: Add the export**

Add this line to `cli/lib/glue.dart` after the `DebugLogger` export (line 61):

```dart
export 'src/dev/devtools.dart' show GlueDev;
```

**Step 2: Verify tests still pass**

Run: `cd cli && dart test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add cli/lib/glue.dart
git commit -m "feat: export GlueDev from barrel"
```

---

### Task 3: Instrument LLM clients with Timeline and logging

**Files:**

- Modify: `cli/lib/src/llm/anthropic_client.dart`
- Modify: `cli/lib/src/llm/openai_client.dart`
- Test: `cd cli && dart test test/llm/anthropic_client_test.dart test/llm/openai_client_test.dart`

**Step 1: Instrument AnthropicClient.stream()**

Add import at top of `cli/lib/src/llm/anthropic_client.dart`:

```dart
import '../dev/devtools.dart';
```

Replace the `stream()` method body to add timeline and TTFB tracking. The key changes:

- Start a `TimelineTask` before the HTTP request
- Track TTFB (time to first TextDelta)
- Finish the task with timing data at the end
- Post `glue.llmRequest` event

```dart
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final task = GlueDev.startAsync('LlmStream:$model', args: {'provider': 'anthropic'});
    final sw = Stopwatch()..start();
    int? ttfbMs;

    final mapper = const AnthropicMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 8192,
      'stream': true,
      'system': mapped.systemPrompt,
      'messages': mapped.messages,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const AnthropicToolEncoder().encodeAll(tools);
    }

    final request = http.Request(
      'POST',
      _baseUri.resolve('/v1/messages'),
    );
    request.headers.addAll({
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': _apiVersion,
    });
    request.body = jsonEncode(body);

    GlueDev.log('llm.request', 'POST /v1/messages model=$model');

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      task.finish(arguments: {'error': response.statusCode});
      throw Exception(
        'Anthropic API error ${response.statusCode}: $errorBody',
      );
    }

    int inputTokens = 0;
    int outputTokens = 0;

    await for (final chunk in parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    )) {
      if (ttfbMs == null && chunk is TextDelta) {
        ttfbMs = sw.elapsedMilliseconds;
      }
      if (chunk is UsageInfo) {
        inputTokens = chunk.inputTokens;
        outputTokens = chunk.outputTokens;
      }
      yield chunk;
    }

    final totalMs = sw.elapsedMilliseconds;
    task.finish(arguments: {
      'ttfbMs': ttfbMs ?? totalMs,
      'totalMs': totalMs,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    });

    GlueDev.postLlmRequest(
      provider: 'anthropic',
      model: model,
      ttfbMs: ttfbMs ?? totalMs,
      streamDurationMs: totalMs,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
```

**Step 2: Instrument OpenAiClient.stream()**

Same pattern — add import and wrap `stream()` with the same timeline/logging. Add import:

```dart
import '../dev/devtools.dart';
```

Replace the `stream()` method body (same pattern as Anthropic — `GlueDev.startAsync`, track TTFB, finish with args, post event):

```dart
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final task = GlueDev.startAsync('LlmStream:$model', args: {'provider': 'openai'});
    final sw = Stopwatch()..start();
    int? ttfbMs;

    final mapper = const OpenAiMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'stream': true,
      'stream_options': {'include_usage': true},
      'messages': mapped.messages,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
    }

    final request = http.Request(
      'POST',
      _baseUri.resolve('/v1/chat/completions'),
    );
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    });
    request.body = jsonEncode(body);

    GlueDev.log('llm.request', 'POST /v1/chat/completions model=$model');

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      task.finish(arguments: {'error': response.statusCode});
      throw Exception(
        'OpenAI API error ${response.statusCode}: $errorBody',
      );
    }

    int inputTokens = 0;
    int outputTokens = 0;

    await for (final chunk in parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    )) {
      if (ttfbMs == null && chunk is TextDelta) {
        ttfbMs = sw.elapsedMilliseconds;
      }
      if (chunk is UsageInfo) {
        inputTokens = chunk.inputTokens;
        outputTokens = chunk.outputTokens;
      }
      yield chunk;
    }

    final totalMs = sw.elapsedMilliseconds;
    task.finish(arguments: {
      'ttfbMs': ttfbMs ?? totalMs,
      'totalMs': totalMs,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    });

    GlueDev.postLlmRequest(
      provider: 'openai',
      model: model,
      ttfbMs: ttfbMs ?? totalMs,
      streamDurationMs: totalMs,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
```

**Step 3: Run existing LLM tests to verify no regressions**

Run: `cd cli && dart test test/llm/anthropic_client_test.dart test/llm/openai_client_test.dart -v`
Expected: All existing tests PASS (instrumentation is transparent)

**Step 4: Commit**

```bash
git add cli/lib/src/llm/anthropic_client.dart cli/lib/src/llm/openai_client.dart
git commit -m "feat: instrument LLM clients with Timeline and logging"
```

---

### Task 4: Instrument AgentCore with Timeline and agent step events

**Files:**

- Modify: `cli/lib/src/agent/agent_core.dart`
- Test: `cd cli && dart test test/agent_core_test.dart`

**Step 1: Add import**

Add to `cli/lib/src/agent/agent_core.dart`:

```dart
import 'dart:developer' show Flow, Timeline;
import '../dev/devtools.dart';
```

**Step 2: Instrument the `run()` method**

Wrap the ReAct loop with a `TimelineTask` and add `Flow` tracing and `postAgentStep` calls. Replace the `run()` method:

```dart
  Stream<AgentEvent> run(String userMessage) async* {
    _conversation.add(Message.user(userMessage));

    final reactTask = GlueDev.startAsync('ReActLoop');
    int iteration = 0;

    try {
      while (true) {
        iteration++;
        final assistantText = StringBuffer();
        final toolCalls = <ToolCall>[];

        final flow = Flow.begin();
        Timeline.startSync('LlmStream', flow: flow);
        final tokensBefore = tokenCount;

        await for (final chunk in llm.stream(
          _conversation,
          tools: tools.values.toList(),
        )) {
          switch (chunk) {
            case TextDelta(:final text):
              assistantText.write(text);
              yield AgentTextDelta(text);
            case ToolCallDelta(:final toolCall):
              toolCalls.add(toolCall);
            case UsageInfo(:final totalTokens):
              tokenCount += totalTokens;
          }
        }

        Timeline.finishSync();

        _conversation.add(Message.assistant(
          text: assistantText.toString(),
          toolCalls: toolCalls,
        ));

        GlueDev.postAgentStep(
          iteration: iteration,
          toolsChosen: toolCalls.map((c) => c.name).toList(),
          tokenDelta: tokenCount - tokensBefore,
        );

        // No tool calls → turn is complete.
        if (toolCalls.isEmpty) break;

        // Create completers and capture futures before yielding
        Timeline.startSync('ToolExecution', flow: Flow.end(flow.id));
        final futures = <Future<ToolResult>>[];
        for (final call in toolCalls) {
          final completer = Completer<ToolResult>();
          _pendingToolResults[call.id] = completer;
          futures.add(completer.future);
        }

        // Emit all tool calls
        for (final call in toolCalls) {
          yield AgentToolCall(call);
        }

        // Wait for all results
        final results = await Future.wait(futures);
        Timeline.finishSync();

        // Add results to conversation and yield events
        for (var i = 0; i < toolCalls.length; i++) {
          _conversation.add(Message.toolResult(
            callId: toolCalls[i].id,
            content: results[i].content,
            toolName: toolCalls[i].name,
          ));
          yield AgentToolResult(results[i]);
        }

        // Loop: send tool results back to the LLM.
      }

      reactTask.finish(arguments: {'iterations': iteration});
      GlueDev.log('agent.loop', 'ReAct completed: $iteration iterations, $tokenCount tokens');
      yield AgentDone();
    } on Object catch (e) {
      reactTask.finish(arguments: {'error': e.toString()});
      yield AgentError(e);
    } finally {
      for (final completer in _pendingToolResults.values) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Agent stream cancelled while awaiting tool result'),
          );
        }
      }
      _pendingToolResults.clear();
    }
  }
```

**Step 3: Run tests**

Run: `cd cli && dart test test/agent_core_test.dart -v`
Expected: All existing tests PASS

**Step 4: Commit**

```bash
git add cli/lib/src/agent/agent_core.dart
git commit -m "feat: instrument AgentCore ReAct loop with Timeline and Flow"
```

---

### Task 5: Instrument tool execution with timing

**Files:**

- Modify: `cli/lib/src/app.dart` (the `_executeAndCompleteTool` method)
- Test: `cd cli && dart test`

**Step 1: Add import to app.dart**

Add to the imports at the top of `cli/lib/src/app.dart`:

```dart
import 'dev/devtools.dart';
```

**Step 2: Instrument `_executeAndCompleteTool`**

Replace the method at line 982:

```dart
  Future<void> _executeAndCompleteTool(ToolCall call) async {
    final sw = Stopwatch()..start();
    try {
      final result = await GlueDev.timeSync('Tool:${call.name}', () => agent.executeTool(call));
      final ms = sw.elapsedMilliseconds;
      GlueDev.log('tool.exec', '${call.name} completed in ${ms}ms');
      GlueDev.postToolExec(
        tool: call.name,
        durationMs: ms,
        resultSizeBytes: result.content.length,
      );
      agent.completeToolCall(result);
    } catch (e) {
      GlueDev.log('tool.exec', '${call.name} failed: $e', level: 1000);
      agent.completeToolCall(ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      ));
    }
  }
```

**Step 3: Run tests**

Run: `cd cli && dart test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add cli/lib/src/app.dart
git commit -m "feat: instrument tool execution with Timeline and timing"
```

---

### Task 6: Instrument render loop with frame budget monitoring

**Files:**

- Modify: `cli/lib/src/app.dart` (the `_doRender` method)

**Step 1: Add frame timing to `_doRender()`**

The import was already added in Task 5. Add a `Stopwatch` and render metrics to the `_doRender` method. At the very beginning of `_doRender()` (after `_lastRender = DateTime.now();`), add:

```dart
    final _renderSw = Stopwatch()..start();
```

And at the very end of `_doRender()` (just before the closing `}`), add:

```dart
    final frameMs = _renderSw.elapsedMicroseconds / 1000.0;
    if (frameMs > 16.0) {
      GlueDev.log('render.slow', 'Frame took ${frameMs.toStringAsFixed(1)}ms (${_blocks.length} blocks)', level: 900);
    }
```

**Step 2: Run tests**

Run: `cd cli && dart test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add cli/lib/src/app.dart
git commit -m "feat: add render frame budget monitoring"
```

---

### Task 7: Instrument shell jobs and subagent spawning

**Files:**

- Modify: `cli/lib/src/shell/shell_job_manager.dart`
- Modify: `cli/lib/src/agent/agent_manager.dart`
- Test: `cd cli && dart test test/shell/shell_job_manager_test.dart test/agent/agent_manager_test.dart`

**Step 1: Instrument ShellJobManager**

Add import to `cli/lib/src/shell/shell_job_manager.dart`:

```dart
import '../dev/devtools.dart';
```

In the `start()` method, after `_events.add(JobStarted(id, command));` (line 69), add:

```dart
    GlueDev.log('shell.job', 'started [$id]: $command');
```

In the exit handler (inside the `unawaited` closure), after `_events.add(JobExited(id, code));` (line 84), add:

```dart
        GlueDev.log('shell.job', 'exited [$id]: code=$code');
```

After `_events.add(JobError(id, e));` (line 88), add:

```dart
        GlueDev.log('shell.job', 'error [$id]: $e', level: 1000);
```

**Step 2: Instrument AgentManager**

Add import to `cli/lib/src/agent/agent_manager.dart`:

```dart
import '../dev/devtools.dart';
```

In `spawnSubagent()`, right after the depth check (after line 78), add:

```dart
    GlueDev.log('agent.subagent', 'spawning at depth=$currentDepth: $task');
    final sw = Stopwatch()..start();
```

Before `return runner.runToCompletion(task);` (line 123), replace it with:

```dart
    final result = await runner.runToCompletion(task);
    GlueDev.log('agent.subagent', 'completed in ${sw.elapsedMilliseconds}ms: $task');
    return result;
```

**Step 3: Run tests**

Run: `cd cli && dart test test/shell/shell_job_manager_test.dart test/agent/agent_manager_test.dart -v`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add cli/lib/src/shell/shell_job_manager.dart cli/lib/src/agent/agent_manager.dart
git commit -m "feat: instrument shell jobs and subagent spawning"
```

---

### Task 8: Register service extensions at startup

**Files:**

- Modify: `cli/bin/glue.dart`
- Modify: `cli/lib/src/app.dart` (add state provider method)

**Step 1: Add a state provider method to App**

Add this public method to the `App` class in `cli/lib/src/app.dart` (after `requestExit()`):

```dart
  /// Returns a JSON-serializable snapshot of internal state for DevTools.
  Map<String, dynamic> devtoolsState(String name) => switch (name) {
    'getAgentState' => {
      'mode': _mode.name,
      'tokenCount': agent.tokenCount,
      'model': _modelName,
      'conversationLength': agent.conversation.length,
      'pendingTools': _mode == AppMode.toolRunning ? 'active' : 'none',
    },
    'getConfig' => {
      'provider': _config?.provider.name ?? 'unknown',
      'model': _config?.model ?? 'unknown',
      'maxSubagentDepth': _config?.maxSubagentDepth ?? 0,
      'bashMaxLines': _config?.bashMaxLines ?? 0,
    },
    'getSessionInfo' => {
      'blockCount': _blocks.length,
      'scrollOffset': _scrollOffset,
    },
    'getToolHistory' => {
      'note': 'Tool history tracking not yet implemented',
    },
    _ => {'error': 'Unknown extension: $name'},
  };
```

**Step 2: Wire up in bin/glue.dart**

Add import to `cli/bin/glue.dart`:

```dart
import 'package:glue/src/dev/devtools.dart';
```

After `final app = App.create(...)` and before the `sigintSub` line, add:

```dart
  GlueDev.registerExtensions(app.devtoolsState);
```

**Step 3: Run tests**

Run: `cd cli && dart test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add cli/bin/glue.dart cli/lib/src/app.dart
git commit -m "feat: register DevTools service extensions at startup"
```

---

### Task 9: Add justfile recipes for DevTools workflows

**Files:**

- Modify: `cli/justfile`

**Step 1: Add dev recipes**

Append these recipes to `cli/justfile`:

```just

# Run with DevTools observability (JIT mode, dev only)
dev *ARGS:
    dart run --enable-vm-service --timeline_streams=Dart bin/glue.dart {{ARGS}}

# Run with DevTools, paused at start for debugger attachment
dev-pause *ARGS:
    dart run --enable-vm-service --pause-isolates-on-start --timeline_streams=Dart bin/glue.dart {{ARGS}}

# Run with full profiling streams (VM, Isolate, GC, Dart)
dev-profile *ARGS:
    @echo "Starting Glue with full profiling..."
    dart run --enable-vm-service --timeline_streams=VM,Isolate,GC,Dart bin/glue.dart {{ARGS}}
```

**Step 2: Verify recipes parse**

Run: `cd cli && just --list`
Expected: `dev`, `dev-pause`, and `dev-profile` appear in the list

**Step 3: Commit**

```bash
git add cli/justfile
git commit -m "feat: add justfile recipes for DevTools dev workflows"
```

---

### Task 10: Run full test suite and verify

**Step 1: Run all tests**

Run: `cd cli && dart test`
Expected: All tests PASS

**Step 2: Run analyzer**

Run: `cd cli && dart analyze --fatal-infos`
Expected: No issues found

**Step 3: Verify build still works**

Run: `cd cli && dart compile exe bin/glue.dart -o /tmp/glue-test`
Expected: Compiles successfully (instrumentation is stripped in AOT)

**Step 4: Clean up**

Run: `rm /tmp/glue-test`
