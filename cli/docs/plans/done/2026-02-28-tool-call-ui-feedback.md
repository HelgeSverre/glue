# Tool Call UI Feedback — Design Investigation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show tool call intent in the UI as soon as the LLM begins generating a tool call, rather than waiting for the full arguments to stream and the entire response to finish.

**Problem:** When the LLM decides to call a tool (e.g. `write_file`), the user sees only a spinner with "⠦ Generating" for the entire duration of argument streaming (potentially 10+ seconds for large file writes). Nothing indicates _what_ is happening until the tool call is fully formed, rendered, and executed.

**Tech Stack:** Dart 3.4+, `package:test`

---

## Root Cause Analysis

There are **two cascading delays** before the UI shows a tool call:

### Delay 1: LLM client waits for full arguments

In `AnthropicClient.parseStreamEvents`, a `ToolCallDelta` is only emitted at `content_block_stop`, after all `input_json_delta` chunks have been accumulated. The tool **name and ID are known at `content_block_start`** but this information is discarded (only stored in the buffer).

```
content_block_start  →  we know: tool name + id     → NOT surfaced
content_block_delta  →  partial JSON args streaming  → NOT surfaced
content_block_stop   →  ToolCallDelta emitted         → first signal
```

Similarly for `OpenAiClient`, the first `tool_calls` delta chunk contains the tool name/ID but `ToolCallDelta` is only emitted on `finish_reason != null`. Ollama delivers tool calls fully formed (no streaming), so no delay exists there.

### Delay 2: Agent core waits for stream end

In `AgentCore.run()`, tool calls are collected into a list during streaming:

```dart
case ToolCallDelta(:final toolCall):
  toolCalls.add(toolCall);  // just stores it
```

`AgentToolCall` events are only yielded **after the entire `llm.stream()` completes** (line 238). This means even after a `ToolCallDelta` is received, the UI doesn't learn about it until all subsequent text/tool deltas finish.

### Combined effect

```
User sends message
  → LLM starts responding (spinner: "Generating")
  → LLM generates text (visible: streaming text appears)
  → LLM starts tool call (content_block_start)
    → 5-15 seconds of JSON arg streaming (NOTHING visible — still "Generating")
  → LLM stream ends
  → AgentToolCall yielded → UI finally shows "▶ Tool: write_file"
  → Tool executes → result shown
```

---

## Proposed Architecture: `ToolCallStart` + eager emission

### Layer 1: New `LlmChunk` subtype

Add `ToolCallStart` to the sealed `LlmChunk` hierarchy in `agent_core.dart`:

```dart
/// Emitted as soon as we know a tool call is starting (name/ID known,
/// arguments still streaming).
class ToolCallStart extends LlmChunk {
  final String id;
  final String name;
  ToolCallStart({required this.id, required this.name});
}
```

### Layer 2: Emit from each provider

**Anthropic** — yield at `content_block_start`:

```dart
case 'content_block_start':
  final block = event['content_block'] as Map<String, dynamic>;
  if (block['type'] == 'tool_use') {
    final id = block['id'] as String;
    final name = block['name'] as String;
    toolBuffers[index] = _ToolUseBuffer(id: id, name: name);
    yield ToolCallStart(id: id, name: name);  // NEW
  }
```

**OpenAI** — yield when a new tool builder is first created:

```dart
if (!toolBuilders.containsKey(index)) {
  final id = (tcMap['id'] as String?) ?? 'call_$index';
  final name = fn?['name'] as String? ?? '';
  toolBuilders[index] = _ToolCallBuilder(id: id, name: name);
  yield ToolCallStart(id: id, name: name);  // NEW
}
```

**Ollama** — no change needed (tool calls arrive fully formed, `ToolCallDelta` is immediate).

### Layer 3: New `AgentEvent` + eager forwarding

Add to the `AgentEvent` sealed class:

```dart
/// Emitted as soon as the LLM begins generating a tool call.
/// Arguments are not yet available.
class AgentToolCallPending extends AgentEvent {
  final String id;
  final String name;
  AgentToolCallPending({required this.id, required this.name});
}
```

In `AgentCore.run()`, forward immediately during streaming:

```dart
await for (final chunk in llm.stream(...)) {
  switch (chunk) {
    case TextDelta(:final text):
      assistantText.write(text);
      yield AgentTextDelta(text);
    case ToolCallStart(:final id, :final name):
      yield AgentToolCallPending(id: id, name: name);  // NEW
    case ToolCallDelta(:final toolCall):
      toolCalls.add(toolCall);
    case UsageInfo(:final totalTokens):
      tokenCount += totalTokens;
  }
}
```

### Layer 4: Emit `AgentToolCall` eagerly (remove delay 2)

Move tool call emission _inside_ the streaming loop so the UI can start approval/execution before the full response ends:

```dart
final toolFutures = <Future<ToolResult>>[];

await for (final chunk in llm.stream(...)) {
  switch (chunk) {
    ...
    case ToolCallDelta(:final toolCall):
      toolCalls.add(toolCall);
      final completer = Completer<ToolResult>();
      _pendingToolResults[toolCall.id] = completer;
      toolFutures.add(completer.future);
      yield AgentToolCall(toolCall);  // emit immediately
  }
}

_conversation.add(Message.assistant(
  text: assistantText.toString(),
  toolCalls: toolCalls,
));

if (toolCalls.isEmpty) break;

// Wait for all results (some may already be completed)
final results = await Future.wait(toolFutures);
```

**Bonus:** Auto-approved tools can start executing while the model is still finishing text output after the tool call.

### Layer 5: UI state map for tool call phases

The `_blocks` list is append-only. To update a tool call's status (preparing → running → done), use a mutable state map alongside a reference entry:

```dart
enum ToolPhase { preparing, awaitingApproval, running, done, denied, error }

class ToolCallUiState {
  final String id;
  final String name;
  Map<String, dynamic>? args;
  ToolPhase phase;
  ToolCallUiState({required this.id, required this.name, this.phase = ToolPhase.preparing});
}
```

In `App`:

```dart
final Map<String, ToolCallUiState> _toolUi = {};
```

Add `_EntryKind.toolCallRef` — stores only a `callId`, renders by looking up `_toolUi[callId]`.

### Layer 6: Wire events to UI state

In `_handleAgentEvent`:

| Event                            | Action                                                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AgentToolCallPending(id, name)` | Flush streaming text. Create `_toolUi[id]`. Append `toolCallRef(id)` to `_blocks`. Render.                                                       |
| `AgentToolCall(call)`            | Update `_toolUi[call.id].args = call.arguments`. Set phase to `awaitingApproval` (or `running` if auto-approved). Show confirm modal or execute. |
| `AgentToolResult(result)`        | Set `_toolUi[result.callId].phase = done`. Append tool result block.                                                                             |

### Layer 7: Rendering

In `BlockRenderer`, add phase-aware rendering:

```dart
String renderToolCallRef(ToolCallUiState state) {
  final suffix = switch (state.phase) {
    ToolPhase.preparing => ' \x1b[90m(preparing…)\x1b[0m',
    ToolPhase.awaitingApproval => ' \x1b[33m(awaiting approval)\x1b[0m',
    ToolPhase.running => ' \x1b[36m(running…)\x1b[0m',
    ToolPhase.done => '',
    ToolPhase.denied => ' \x1b[31m(denied)\x1b[0m',
    ToolPhase.error => ' \x1b[31m(error)\x1b[0m',
  };
  final header = ' \x1b[1m\x1b[33m▶ Tool: ${state.name}\x1b[0m$suffix';
  if (state.args == null || state.args!.isEmpty) return header;
  final argsStr = state.args!.entries
      .map((e) => '${e.key}: ${ansiTruncate('${e.value}', _inner - 6)}')
      .join(', ');
  return '$header\n    \x1b[90m$argsStr\x1b[0m';
}
```

---

## User-visible result

```
User sends message
  → LLM starts responding (spinner: "Generating")
  → LLM generates text (visible: streaming text appears)
  → LLM starts tool call
    → IMMEDIATELY: "▶ Tool: write_file (preparing…)" appears
    → Status bar: still "Generating" (model may have more blocks)
  → Tool call arguments complete
    → Args shown, phase → "running…" (if auto-approved)
    → Or confirmation modal shown
  → Tool executes → result shown
```

---

## Edge cases & guardrails

- **Cancelled stream:** On cancel, mark any `preparing`/`running` entries as `error` in `_toolUi`.
- **Multiple concurrent tool calls:** All keyed by `callId` — safe for parallel execution.
- **Ollama (non-streaming tools):** `ToolCallStart` is never emitted; `AgentToolCallPending` is skipped. `AgentToolCall` still works as today. The `toolCallRef` entry is created at `AgentToolCall` time with phase `running` directly.
- **Don't execute on `Pending`:** Only start tool execution on the finalized `AgentToolCall` (args must be complete).

---

## Files to modify

| File                                    | Change                                                                           |
| --------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/src/agent/agent_core.dart`         | Add `ToolCallStart`, `AgentToolCallPending`. Emit eagerly.                       |
| `lib/src/llm/anthropic_client.dart`     | Yield `ToolCallStart` at `content_block_start`.                                  |
| `lib/src/llm/openai_client.dart`        | Yield `ToolCallStart` when builder first created.                                |
| `lib/src/app.dart`                      | Add `_toolUi` map, `ToolCallUiState`, `toolCallRef` entry kind. Wire new events. |
| `lib/src/rendering/block_renderer.dart` | Add `renderToolCallRef(ToolCallUiState)`.                                        |
| `test/agent/agent_core_test.dart`       | Test that `AgentToolCallPending` is emitted before `AgentToolCall`.              |

**Effort estimate:** M (2-4 hours)
