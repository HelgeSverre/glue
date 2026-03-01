# Architecture Fixes & Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix architectural issues found in code review and add ~/.glue/ infrastructure for logging, config, and conversation storage.

**Architecture:** Event-driven TUI app with agent loop. Fixes target error handling, parallel tool execution, provider correctness, and rendering. New infrastructure adds persistent storage under ~/.glue/ using JSONL for conversations, plain text for debug logs, and JSON for config.

**Tech Stack:** Dart 3.4+, package:http, package:yaml, dart:convert, dart:io

---

## Task 1: Fix fire-and-forget .then() chains in tool approval

**Files:**

- Modify: `lib/src/app.dart` (lines 490-538)

**Step 1: Create `_executeAndCompleteTool` helper**

Add this method to `App`:

```dart
Future<void> _executeAndCompleteTool(ToolCall call) async {
  try {
    final result = await agent.executeTool(call);
    agent.completeToolCall(result);
  } catch (e) {
    agent.completeToolCall(ToolResult(
      callId: call.id,
      content: 'Tool error: $e',
      success: false,
    ));
  }
}
```

**Step 2: Replace all three `.then()` sites**

In `_handleAgentEvent`, replace:

```dart
agent.executeTool(call).then((result) {
  agent.completeToolCall(result);
});
```

With:

```dart
unawaited(_executeAndCompleteTool(call));
```

There are 3 occurrences: auto-approve (L494), Yes (L521), Always (L530). Add `import 'dart:async';` if not already present (it is).

**Step 3: Run tests**

Run: `dart test`
Expected: All 211 tests pass (no behavioral change)

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "fix: replace fire-and-forget .then() with proper async error handling"
```

---

## Task 2: Parallel tool execution in AgentCore

**Files:**

- Modify: `lib/src/agent/agent_core.dart` (lines 170-258)
- Modify: `test/agent_core_test.dart`

**Step 1: Write failing test for parallel tool calls**

In `test/agent_core_test.dart`, add a test where the mock LLM returns 2 tool calls in one response. Verify both `AgentToolCall` events are yielded before either result is awaited. Use the existing `_MockLlm` pattern.

```dart
test('emits all tool calls before awaiting results (parallel)', () async {
  // Mock LLM returns 2 tool calls, then a text response after results
  final llm = _MockLlm([
    [
      TextDelta('thinking'),
      ToolCallDelta(ToolCall(id: 'tc1', name: 'read_file', arguments: {'path': 'a.txt'})),
      ToolCallDelta(ToolCall(id: 'tc2', name: 'read_file', arguments: {'path': 'b.txt'})),
    ],
    [TextDelta('done')],
  ]);

  final tools = <String, Tool>{
    'read_file': _EchoTool('read_file'),
  };

  final agent = AgentCore(llm: llm, tools: tools);
  final events = <AgentEvent>[];

  // Collect events, complete tool calls as they arrive
  await for (final event in agent.run('test')) {
    events.add(event);
    if (event is AgentToolCall) {
      final result = await agent.executeTool(event.call);
      agent.completeToolCall(result);
    }
  }

  // Both AgentToolCall events should appear before any AgentToolResult
  final toolCallIndices = <int>[];
  final toolResultIndices = <int>[];
  for (var i = 0; i < events.length; i++) {
    if (events[i] is AgentToolCall) toolCallIndices.add(i);
    if (events[i] is AgentToolResult) toolResultIndices.add(i);
  }
  expect(toolCallIndices.length, 2);
  expect(toolResultIndices.length, 2);
  // All tool calls emitted before first result
  expect(toolCallIndices.last, lessThan(toolResultIndices.first));
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/agent_core_test.dart`
Expected: FAIL — current code emits AgentToolCall, then AgentToolResult sequentially

**Step 3: Refactor AgentCore to support parallel tool results**

Replace `_toolResultCompleter` (single) with `_pendingToolResults` (map):

```dart
final Map<String, Completer<ToolResult>> _pendingToolResults = {};
```

In `run()`, change the tool call loop:

```dart
// Emit all tool calls, create completers for each
for (final call in toolCalls) {
  _pendingToolResults[call.id] = Completer<ToolResult>();
  yield AgentToolCall(call);
}

// Wait for all results
final results = await Future.wait(
  toolCalls.map((c) => _pendingToolResults[c.id]!.future),
);

// Add results to conversation and yield events
for (var i = 0; i < toolCalls.length; i++) {
  _conversation.add(Message.toolResult(
    callId: toolCalls[i].id,
    content: results[i].content,
  ));
  yield AgentToolResult(results[i]);
}
```

Update `completeToolCall`:

```dart
void completeToolCall(ToolResult result) {
  final completer = _pendingToolResults.remove(result.callId);
  if (completer == null || completer.isCompleted) return;
  completer.complete(result);
}
```

Update `finally` block to clean up all pending completers.

**Step 4: Run tests**

Run: `dart test`
Expected: All tests pass including new parallel test

**Step 5: Commit**

```bash
git add lib/src/agent/agent_core.dart test/agent_core_test.dart
git commit -m "feat: support parallel tool execution in AgentCore"
```

---

## Task 3: Fix OpenAI arguments serialization bug

**Files:**

- Modify: `lib/src/llm/message_mapper.dart` (line 117)
- Modify: `test/llm/message_mapper_test.dart`

**Step 1: Write failing test**

```dart
test('OpenAiMessageMapper serializes tool call arguments as JSON string', () {
  final mapper = const OpenAiMessageMapper();
  final messages = [
    Message.assistant(
      text: '',
      toolCalls: [
        ToolCall(id: 'tc1', name: 'read_file', arguments: {'path': '/foo.txt'}),
      ],
    ),
  ];
  final result = mapper.mapMessages(messages, systemPrompt: '');
  final assistantMsg = result.messages.last;
  final toolCall = (assistantMsg['tool_calls'] as List).first as Map;
  final fn = toolCall['function'] as Map;
  final args = fn['arguments'] as String;
  // Must be valid JSON, not Dart Map.toString()
  expect(args, '{"path":"/foo.txt"}');
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/message_mapper_test.dart`
Expected: FAIL — produces `{path: /foo.txt}` instead of `{"path":"/foo.txt"}`

**Step 3: Fix the serialization**

In `lib/src/llm/message_mapper.dart`, add `import 'dart:convert';` and change line 117:

```dart
// Before:
'arguments': tc.arguments.toString(),
// After:
'arguments': jsonEncode(tc.arguments),
```

**Step 4: Run tests**

Run: `dart test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/llm/message_mapper.dart test/llm/message_mapper_test.dart
git commit -m "fix: serialize OpenAI tool call arguments as JSON instead of Dart toString()"
```

---

## Task 4: Fix /model command to actually switch the LLM

**Files:**

- Modify: `lib/src/app.dart` (lines 273-281, and App fields/constructor)

**Step 1: Store references needed for model switching**

Add fields to `App`:

```dart
final LlmClientFactory _llmFactory;
final GlueConfig _config;
final String _systemPrompt;
```

Pass them through the constructor and `App.create()`.

**Step 2: Update /model command to rebuild the LLM client**

```dart
_commands.register(SlashCommand(
  name: 'model',
  description: 'Show or set the model name',
  execute: (args) {
    if (args.isEmpty) return 'Current model: $_modelName';
    final newModel = args.join(' ');
    final llm = _llmFactory.create(
      provider: _config.provider,
      model: newModel,
      apiKey: _config.apiKey,
      systemPrompt: _systemPrompt,
    );
    agent.llm = llm;  // Need to make llm non-final in AgentCore
    _modelName = newModel;
    return 'Model switched to: $newModel';
  },
));
```

**Step 3: Make `AgentCore.llm` mutable**

In `agent_core.dart`, change `final LlmClient llm;` to `LlmClient llm;`.

**Step 4: Run tests**

Run: `dart test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/app.dart lib/src/agent/agent_core.dart
git commit -m "fix: /model command now actually switches the LLM client"
```

---

## Task 5: BashTool configurable timeout

**Files:**

- Modify: `lib/src/agent/tools.dart` (BashTool class, lines 134-172)
- Modify: `test/agent_core_test.dart` or create `test/tools/bash_tool_test.dart`

**Step 1: Write failing test**

```dart
test('BashTool respects timeout_seconds parameter', () async {
  final tool = BashTool();
  // Default should work (30s)
  final result = await tool.execute({'command': 'echo hello'});
  expect(result, contains('hello'));
});

test('BashTool with 0 timeout runs without timeout', () async {
  final tool = BashTool();
  final result = await tool.execute({
    'command': 'echo no-timeout',
    'timeout_seconds': 0,
  });
  expect(result, contains('no-timeout'));
});
```

**Step 2: Add `timeout_seconds` parameter to BashTool**

```dart
@override
List<ToolParameter> get parameters => const [
  ToolParameter(
    name: 'command',
    type: 'string',
    description: 'The shell command to execute.',
  ),
  ToolParameter(
    name: 'timeout_seconds',
    type: 'integer',
    description: 'Timeout in seconds. 0 for no timeout. Default: 30.',
    required: false,
  ),
];
```

**Step 3: Update execute() to use the parameter**

```dart
@override
Future<String> execute(Map<String, dynamic> args) async {
  final command = args['command'];
  if (command is! String || command.isEmpty) {
    return 'Error: no command provided';
  }
  final t = args['timeout_seconds'];
  final timeoutSeconds = (t is num) ? t.toInt() : 30;
  try {
    final future = Process.run('sh', ['-c', command]);
    final result = timeoutSeconds == 0
        ? await future
        : await future.timeout(Duration(seconds: timeoutSeconds));
    final buf = StringBuffer();
    if ((result.stdout as String).isNotEmpty) {
      buf.writeln(result.stdout);
    }
    if ((result.stderr as String).isNotEmpty) {
      buf.writeln('STDERR: ${result.stderr}');
    }
    buf.writeln('Exit code: ${result.exitCode}');
    return buf.toString();
  } on TimeoutException {
    return 'Error: command timed out after $timeoutSeconds seconds';
  }
}
```

**Step 4: Run tests**

Run: `dart test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/agent/tools.dart test/tools/bash_tool_test.dart
git commit -m "feat: add configurable timeout_seconds parameter to BashTool"
```

---

## Task 6: Investigate and fix Ollama tool_name field

**Files:**

- Modify: `lib/src/llm/ollama_client.dart` (line 60-64)
- Modify: `lib/src/agent/agent_core.dart` (Message class)
- Modify: `lib/src/llm/message_mapper.dart` (AnthropicMessageMapper — no change needed, uses tool_use_id)
- Modify: `test/llm/ollama_client_test.dart`

**Context:** Ollama's API expects `tool_name` to contain the **function name** (e.g. `"read_file"`), not the internal tool call ID (e.g. `"ollama_tc_1"`). The current code passes `msg.toolCallId` which stores the call ID.

**Step 1: Add `toolName` field to `Message`**

```dart
class Message {
  final Role role;
  final String? text;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;  // Add this

  const Message._({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  factory Message.toolResult({
    required String callId,
    required String content,
    String? toolName,
  }) => Message._(
    role: Role.toolResult,
    text: content,
    toolCallId: callId,
    toolName: toolName,
  );
}
```

**Step 2: Pass tool name when creating tool result messages in AgentCore**

In `agent_core.dart`, `run()` method, where tool results are added to conversation:

```dart
_conversation.add(Message.toolResult(
  callId: toolCalls[i].id,
  content: results[i].content,
  toolName: toolCalls[i].name,  // Add this
));
```

**Step 3: Fix Ollama client to use `toolName`**

```dart
case Role.toolResult:
  mappedMessages.add({
    'role': 'tool',
    'content': msg.text ?? '',
    'tool_name': msg.toolName ?? '',
  });
```

**Step 4: Write test verifying correct mapping**

**Step 5: Run tests**

Run: `dart test`

**Step 6: Commit**

```bash
git add lib/src/agent/agent_core.dart lib/src/llm/ollama_client.dart test/llm/ollama_client_test.dart
git commit -m "fix: Ollama tool results now correctly use tool name instead of call ID"
```

---

## Task 7: Fix status bar padding to use visibleLength

**Files:**

- Modify: `lib/src/terminal/layout.dart` (line 123-125)

**Step 1: Import ansi_utils**

Add to top of `layout.dart`:

```dart
import '../rendering/ansi_utils.dart';
```

**Step 2: Fix padding calculation**

```dart
void paintStatus(String left, String right) {
  terminal.moveTo(statusRow, 1);
  terminal.clearLine();

  final leftVisible = visibleLength(left);
  final rightVisible = visibleLength(right);
  final padding = terminal.columns - leftVisible - rightVisible;
  terminal.writeStyled(
    '$left${' ' * padding.clamp(0, 9999)}$right',
    style: AnsiStyle.inverse,
  );
}
```

**Step 3: Run tests**

Run: `dart test`

**Step 4: Commit**

```bash
git add lib/src/terminal/layout.dart
git commit -m "fix: status bar padding now accounts for ANSI escape sequence lengths"
```

---

## Task 8: Refactor event routing + resize reflow

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Remove dead event classes or wire them up**

Remove `UserCancel` and `UserScroll` if truly unused, or wire them:

- In `_handleTerminalEvent`, emit `UserScroll(delta)` for PageUp/PageDown/MouseScroll instead of handling inline.
- In `_handleTerminalEvent`, emit `UserResize(cols, rows)` for `ResizeEvent` instead of handling inline.
- Handle all state mutation in `_handleAppEvent`.

**Step 2: Fix resize to clear and redraw**

In `_handleAppEvent` for `UserResize`:

```dart
case UserResize(:final cols, :final rows):
  layout.apply();
  terminal.clearScreen();
  _scrollOffset = 0;
  _render();
```

**Step 3: Emit events from \_handleTerminalEvent**

Replace inline scroll/resize handling:

```dart
case KeyEvent(key: Key.pageUp):
  final viewportHeight = layout.outputBottom - layout.outputTop + 1;
  _events.add(UserScroll(viewportHeight ~/ 2));
  return;
case KeyEvent(key: Key.pageDown):
  final viewportHeight = layout.outputBottom - layout.outputTop + 1;
  _events.add(UserScroll(-(viewportHeight ~/ 2)));
  return;

case ResizeEvent(:final cols, :final rows):
  _events.add(UserResize(cols, rows));

case MouseEvent(:final isScroll, :final isScrollUp):
  if (isScroll) {
    _events.add(UserScroll(isScrollUp ? 3 : -3));
  }
```

In `_handleAppEvent`:

```dart
case UserScroll(:final delta):
  _scrollOffset = (_scrollOffset + delta).clamp(0, 999999);
  _render();
case UserResize():
  layout.apply();
  terminal.clearScreen();
  _scrollOffset = 0;
  _render();
```

**Step 4: Run tests**

Run: `dart test`

**Step 5: Commit**

```bash
git add lib/src/app.dart
git commit -m "refactor: route scroll/resize through event bus, fix resize reflow"
```

---

## Task 9: ~/.glue/ infrastructure (config, sessions, logging)

This is the largest task. It adds the persistent storage layer.

**Files:**

- Create: `lib/src/storage/glue_home.dart` — manages ~/.glue/ directory structure
- Create: `lib/src/storage/session_store.dart` — conversation session persistence
- Create: `lib/src/storage/debug_logger.dart` — debug log file writer
- Create: `lib/src/storage/config_store.dart` — config.json read/write
- Modify: `lib/src/app.dart` — wire storage into app lifecycle
- Modify: `lib/src/config/glue_config.dart` — load from config.json
- Create: `test/storage/` — tests for each component

### Directory structure:

```
~/.glue/
  config.json              # user preferences, trusted tools, default model/provider
  sessions/
    <session-id>/
      meta.json            # cwd, model, provider, start_time, end_time
      conversation.jsonl   # append-only event log
  logs/
    debug-YYYY-MM-DD.log   # debug log (HTTP, events) when debug=true
```

### Sub-step 9a: GlueHome — directory management

```dart
// lib/src/storage/glue_home.dart
import 'dart:io';
import 'package:path/path.dart' as p;

class GlueHome {
  final String basePath;

  GlueHome({String? basePath})
      : basePath = basePath ??
            p.join(Platform.environment['HOME'] ?? '.', '.glue');

  String get configPath => p.join(basePath, 'config.json');
  String get sessionsDir => p.join(basePath, 'sessions');
  String get logsDir => p.join(basePath, 'logs');

  void ensureDirectories() {
    Directory(sessionsDir).createSync(recursive: true);
    Directory(logsDir).createSync(recursive: true);
  }

  String sessionDir(String sessionId) => p.join(sessionsDir, sessionId);
}
```

### Sub-step 9b: ConfigStore — config.json

```dart
// lib/src/storage/config_store.dart
import 'dart:convert';
import 'dart:io';

class ConfigStore {
  final String path;

  ConfigStore(this.path);

  Map<String, dynamic> load() {
    final file = File(path);
    if (!file.existsSync()) return {};
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  void save(Map<String, dynamic> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final encoder = const JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert(config));
  }

  // Convenience getters for known keys
  String? get defaultProvider => load()['default_provider'] as String?;
  String? get defaultModel => load()['default_model'] as String?;
  List<String> get trustedTools =>
      (load()['trusted_tools'] as List?)?.cast<String>() ?? [];
  bool get debug => (load()['debug'] as bool?) ?? true;
}
```

Config.json shape:

```json
{
  "default_provider": "anthropic",
  "default_model": "claude-sonnet-4-6",
  "trusted_tools": ["read_file", "list_directory", "grep"],
  "debug": true
}
```

### Sub-step 9c: SessionStore — conversation JSONL

```dart
// lib/src/storage/session_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class SessionMeta {
  final String id;
  final String cwd;
  final String model;
  final String provider;
  final DateTime startTime;
  DateTime? endTime;

  SessionMeta({
    required this.id,
    required this.cwd,
    required this.model,
    required this.provider,
    required this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'cwd': cwd,
    'model': model,
    'provider': provider,
    'start_time': startTime.toIso8601String(),
    if (endTime != null) 'end_time': endTime!.toIso8601String(),
  };
}

class SessionStore {
  final String sessionDir;
  final SessionMeta meta;
  late final IOSink _conversationSink;

  SessionStore({required this.sessionDir, required this.meta}) {
    Directory(sessionDir).createSync(recursive: true);
    _conversationSink = File(p.join(sessionDir, 'conversation.jsonl'))
        .openWrite(mode: FileMode.append);
    _writeMeta();
  }

  void _writeMeta() {
    final encoder = const JsonEncoder.withIndent('  ');
    File(p.join(sessionDir, 'meta.json'))
        .writeAsStringSync(encoder.convert(meta.toJson()));
  }

  void logEvent(String type, Map<String, dynamic> data) {
    final record = {
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      ...data,
    };
    _conversationSink.writeln(jsonEncode(record));
  }

  Future<void> close() async {
    meta.endTime = DateTime.now();
    _writeMeta();
    await _conversationSink.flush();
    await _conversationSink.close();
  }
}
```

### Sub-step 9d: DebugLogger

```dart
// lib/src/storage/debug_logger.dart
import 'dart:io';
import 'package:path/path.dart' as p;

class DebugLogger {
  final IOSink? _sink;
  final bool enabled;

  DebugLogger({required String logsDir, this.enabled = true})
      : _sink = enabled
            ? File(p.join(
                logsDir,
                'debug-${DateTime.now().toIso8601String().substring(0, 10)}.log',
              )).openWrite(mode: FileMode.append)
            : null {
    if (enabled) {
      _sink!.writeln('--- Session started ${DateTime.now().toIso8601String()} ---');
    }
  }

  void log(String category, String message) {
    if (!enabled || _sink == null) return;
    final ts = DateTime.now().toIso8601String();
    _sink.writeln('[$ts] [$category] $message');
  }

  void logHttp(String method, String url, int statusCode, {String? body}) {
    log('HTTP', '$method $url → $statusCode');
    if (body != null && body.length < 1000) {
      log('HTTP', 'Body: $body');
    }
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
```

### Sub-step 9e: Wire into App

- In `App.create()`, instantiate `GlueHome`, `ConfigStore`, `SessionStore`, `DebugLogger`.
- Generate session ID with timestamp + short random suffix.
- Log agent events to `SessionStore.logEvent()`.
- Log HTTP requests in LLM clients via `DebugLogger` (pass logger to factory).
- On shutdown, call `sessionStore.close()` and `debugLogger.close()`.

### Sub-step 9f: Update GlueConfig to read from config.json

- In `GlueConfig.load()`, also read `~/.glue/config.json` as a config source (lower priority than env vars, higher than ~/.glue/config.yaml which can be deprecated).

### Sub-step 9g: Export new types from barrel file

Add to `lib/glue.dart`:

```dart
export 'src/storage/glue_home.dart' show GlueHome;
export 'src/storage/session_store.dart' show SessionStore, SessionMeta;
export 'src/storage/debug_logger.dart' show DebugLogger;
export 'src/storage/config_store.dart' show ConfigStore;
```

### Tests:

- `test/storage/config_store_test.dart` — load/save round-trip, missing file returns defaults
- `test/storage/session_store_test.dart` — logEvent appends JSONL, meta.json written on close
- `test/storage/debug_logger_test.dart` — writes to file when enabled, no-ops when disabled
- `test/storage/glue_home_test.dart` — ensureDirectories creates structure

**Commit after each sub-step or all together:**

```bash
git add lib/src/storage/ test/storage/ lib/glue.dart lib/src/app.dart lib/src/config/glue_config.dart
git commit -m "feat: add ~/.glue/ infrastructure for config, sessions, and debug logging"
```

---

## Task 10: Integrate ScreenBuffer for flicker-free rendering (LAST)

**Files:**

- Modify: `lib/src/terminal/screen_buffer.dart`
- Modify: `lib/src/terminal/layout.dart`
- Modify: `lib/src/app.dart`

**Context:** ScreenBuffer exists but is unused. Integration provides diff-based rendering that only updates changed cells, eliminating flicker during fast streaming.

**Step 1: Assess whether ScreenBuffer helps**

The current `paintOutputViewport` redraws every line every frame. During streaming (many `AgentTextDelta` events per second), this causes visible flicker. ScreenBuffer's diff-flush approach would only write changed cells.

**Step 2: Add render-throttling first**

Before full ScreenBuffer integration, add a render throttle to `_render()`:

```dart
DateTime _lastRender = DateTime(0);
static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps

void _render() {
  final now = DateTime.now();
  if (now.difference(_lastRender) < _minRenderInterval) {
    // Schedule a deferred render
    Future.delayed(_minRenderInterval, () {
      if (DateTime.now().difference(_lastRender) >= _minRenderInterval) {
        _doRender();
      }
    });
    return;
  }
  _doRender();
}

void _doRender() {
  _lastRender = DateTime.now();
  // ... existing render logic
}
```

**Step 3: Integrate ScreenBuffer into Layout (if flicker persists)**

Update `Layout` to accept a `ScreenBuffer` and write through it:

- `paintOutputViewport` → `buffer.writeAt()` per line
- `paintStatus` → `buffer.fillRow()`
- Call `buffer.flush()` at the end of `_render()`

This is a larger refactor — only do if throttling alone doesn't solve flicker.

**Step 4: Handle unicode width properly in ScreenBuffer**

The current `ScreenBuffer.writeAt` uses `text.runes` which doesn't account for East Asian wide characters. For v0.1 this is acceptable but should be noted as a known limitation.

**Step 5: Run tests**

Run: `dart test`

**Step 6: Commit**

```bash
git add lib/src/terminal/screen_buffer.dart lib/src/terminal/layout.dart lib/src/app.dart
git commit -m "perf: add render throttling and ScreenBuffer integration for flicker-free rendering"
```

---

## Execution Order

Tasks can be parallelized in groups:

**Group A (independent, no shared files):**

- Task 3: OpenAI arguments fix (message_mapper.dart)
- Task 5: BashTool timeout (tools.dart)
- Task 6: Ollama tool_name fix (ollama_client.dart + agent_core.dart Message)
- Task 7: Status bar padding fix (layout.dart)

**Group B (depends on Group A for agent_core.dart):**

- Task 2: Parallel tool execution (agent_core.dart)
- Task 1: Fire-and-forget fix (app.dart)

**Group C (depends on B for app.dart):**

- Task 4: /model command fix (app.dart + agent_core.dart)
- Task 8: Event routing refactor (app.dart)

**Group D (can run parallel to B/C):**

- Task 9: ~/.glue/ infrastructure (new files, minimal app.dart touch)

**Group E (last, after all others):**

- Task 10: ScreenBuffer integration (app.dart + layout.dart)

---

## Notes

- **Auto-approval config (issue #9):** Future work. The `config.json` from Task 9 already has `trusted_tools` array. When auto-approval mode becomes default, `App` should load `trusted_tools` from `ConfigStore` into `_autoApprovedTools` on startup, and the "Always" choice should persist back to `config.json`.
- **Conversation replay:** The JSONL format from Task 9 enables future `/replay` command or session continuation.
- Commit after completing each task (snapshot).
