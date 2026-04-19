# LLM Provider Integration & Subagent System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the fake LLM client with real Anthropic, OpenAI, and Ollama (local) provider integrations, add configuration management, and implement a subagent spawning system (single + parallel).

**Architecture:** Provider-specific concerns (streaming parsing, tool schema translation, message mapping) are isolated behind the existing `LlmClient` interface. `AgentCore` stays unchanged. A new `AgentRunner` decouples tool-approval policy from the loop, enabling headless subagent execution. An `AgentManager` orchestrates subagent spawning via the manager pattern — exposed to the LLM as tool calls.

**Tech Stack:** Dart 3.4+, `http` package (streaming), `yaml` package (config), SSE protocol (Anthropic/OpenAI), NDJSON streaming (Ollama), Anthropic Messages API, OpenAI Chat Completions API, Ollama Chat API.

### Supported Models

**Anthropic** (via `https://api.anthropic.com/v1/messages`):
| Alias | API Model ID | Description |
|-------|-------------|-------------|
| `claude-opus-4-6` | `claude-opus-4-6` | Most intelligent — agents & coding |
| `claude-sonnet-4-6` | `claude-sonnet-4-6` | Best speed/intelligence balance |
| `claude-haiku-4-5` | `claude-haiku-4-5` | Fastest, near-frontier |

**OpenAI** (via `https://api.openai.com/v1/chat/completions`):
| Alias | API Model ID | Description |
|-------|-------------|-------------|
| `gpt-4.1` | `gpt-4.1` | Smartest non-reasoning, 1M context |
| `gpt-4.1-mini` | `gpt-4.1-mini` | Fast, beats GPT-4o, 83% cheaper |
| `gpt-4.1-nano` | `gpt-4.1-nano` | Fastest/cheapest, classification |
| `o3` | `o3` | Reasoning model |
| `o4-mini` | `o4-mini` | Reasoning model (mini) |

**Ollama** (via `http://localhost:11434/api/chat`, local):
| Usage | Description |
|-------|-------------|
| Any model name (e.g. `llama3.2`, `qwen2.5-coder`, `deepseek-r1`) | Whatever is pulled locally |

> **Note:** Ollama uses NDJSON streaming (one JSON object per line), NOT SSE. Its tool calling format uses OpenAI-compatible tool schemas but returns tool_calls in a different structure (arguments as parsed objects, not JSON strings). Tool results use `role: "tool"` with a `tool_name` field.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         App (UI)                             │
│  Uses AgentCore interactively with tool approval flow        │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                      AgentCore                               │
│  ReAct loop: stream → tool calls → execute → loop            │
│  UNCHANGED — only gets a real LlmClient now                  │
└────────┬───────────────────────────────────┬────────────────┘
         │                                   │
┌────────▼────────┐  ┌─────────▼───────────┐  ┌──────────────┐
│ AnthropicClient  │  │   OpenAIClient       │  │ OllamaClient │
│ implements       │  │   implements          │  │ implements    │
│ LlmClient        │  │   LlmClient           │  │ LlmClient     │
└────────┬────────┘  └─────────┬───────────┘  └──────┬───────┘
         │                     │                      │
┌────────▼─────────────────────▼──────┐  ┌────────────▼─────────┐
│        Shared SSE Decoder            │  │   NDJSON Decoder      │
│  Stream<List<int>> → Stream<SseEvent>│  │  (line-delimited JSON)│
└──────────────────────────────────────┘  └────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     AgentManager                             │
│  spawnSubagent(task, profile) → String                       │
│  spawnParallel(tasks, profile) → List<String>                │
│  Uses AgentRunner (headless, auto-approve) internally        │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│              SubagentTool / ParallelSubagentsTool             │
│  Exposed as tools the LLM can call                           │
│  Delegates to AgentManager                                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      GlueConfig                              │
│  CLI args → env vars → ~/.glue/config.yaml → defaults        │
│  Resolves provider, model, API keys, agent profiles          │
└─────────────────────────────────────────────────────────────┘
```

### File Structure (new/modified files)

```
lib/src/
  agent/
    agent_core.dart          ← MODIFY: add system role to Role enum
    agent_runner.dart         ← NEW: headless runner with approval policies
    agent_manager.dart        ← NEW: subagent orchestrator
    prompts.dart              ← NEW: system prompt templates
    tools.dart                ← UNCHANGED
  llm/
    sse.dart                  ← NEW: SSE stream decoder (Anthropic/OpenAI)
    ndjson.dart               ← NEW: NDJSON stream decoder (Ollama)
    tool_schema.dart          ← NEW: per-provider tool schema encoders
    message_mapper.dart       ← NEW: Message → provider JSON mappers
    anthropic_client.dart     ← NEW: Anthropic Messages API streaming
    openai_client.dart        ← NEW: OpenAI Chat Completions streaming
    ollama_client.dart        ← NEW: Ollama local chat API streaming
    llm_factory.dart          ← NEW: creates LlmClient from config
  config/
    glue_config.dart          ← NEW: config loading & resolution
  tools/
    subagent_tools.dart       ← NEW: spawn_subagent + spawn_parallel tools
```

---

## Task 1: SSE Stream Decoder

**Files:**

- Create: `lib/src/llm/sse.dart`
- Test: `test/llm/sse_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/sse_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/llm/sse.dart';

void main() {
  group('SseDecoder', () {
    test('parses simple data-only events', () async {
      final input = 'data: {"text":"hello"}\n\ndata: {"text":"world"}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(2));
      expect(events[0].data, '{"text":"hello"}');
      expect(events[1].data, '{"text":"world"}');
    });

    test('parses events with event type', () async {
      final input = 'event: message_start\ndata: {"type":"message_start"}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].event, 'message_start');
      expect(events[0].data, '{"type":"message_start"}');
    });

    test('ignores comment lines', () async {
      final input = ': ping\ndata: {"ok":true}\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, '{"ok":true}');
    });

    test('handles data: [DONE] sentinel', () async {
      final input = 'data: {"text":"hi"}\n\ndata: [DONE]\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, '{"text":"hi"}');
    });

    test('handles multi-line data fields', () async {
      final input = 'data: line1\ndata: line2\n\n';
      final stream = Stream.value(utf8.encode(input));
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'line1\nline2');
    });

    test('handles chunked byte delivery', () async {
      final full = 'data: {"x":1}\n\ndata: {"x":2}\n\n';
      final bytes = utf8.encode(full);
      // Split into small chunks to simulate real network
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 5) {
        chunks.add(bytes.sublist(i, (i + 5).clamp(0, bytes.length)));
      }
      final stream = Stream.fromIterable(chunks);
      final events = await decodeSse(stream).toList();

      expect(events, hasLength(2));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/sse_test.dart`
Expected: FAIL — file not found

**Step 3: Write minimal implementation**

```dart
// lib/src/llm/sse.dart

import 'dart:async';
import 'dart:convert';

/// A single Server-Sent Event.
class SseEvent {
  final String? event;
  final String data;
  SseEvent({this.event, required this.data});

  @override
  String toString() => 'SseEvent(event: $event, data: $data)';
}

/// Decode a raw byte stream (from an HTTP response) into [SseEvent]s.
///
/// Follows the SSE specification:
/// - Events are separated by blank lines.
/// - Lines starting with `:` are comments (ignored).
/// - `data: [DONE]` is treated as end-of-stream (OpenAI convention).
/// - Multiple `data:` lines in one event are joined with newlines.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  String? currentEvent;
  final dataLines = <String>[];
  final buffer = StringBuffer();

  await for (final chunk in bytes) {
    buffer.write(utf8.decode(chunk));

    while (true) {
      final content = buffer.toString();
      final nlIndex = content.indexOf('\n');
      if (nlIndex == -1) break;

      final line = content.substring(0, nlIndex);
      // Remove the consumed line (including the \n).
      buffer
        ..clear()
        ..write(content.substring(nlIndex + 1));

      // Strip trailing \r for CRLF compatibility.
      final trimmed = line.endsWith('\r')
          ? line.substring(0, line.length - 1)
          : line;

      if (trimmed.isEmpty) {
        // Blank line = event boundary.
        if (dataLines.isNotEmpty) {
          final joined = dataLines.join('\n');
          if (joined == '[DONE]') {
            // OpenAI end sentinel — stop.
            return;
          }
          yield SseEvent(event: currentEvent, data: joined);
        }
        currentEvent = null;
        dataLines.clear();
        continue;
      }

      // Comment line.
      if (trimmed.startsWith(':')) continue;

      // Field parsing.
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;

      final field = trimmed.substring(0, colonIndex);
      // Value starts after `: ` (space is optional per spec).
      var value = trimmed.substring(colonIndex + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'event':
          currentEvent = value;
        case 'data':
          dataLines.add(value);
      }
    }
  }

  // Flush any remaining event (no trailing blank line).
  if (dataLines.isNotEmpty) {
    final joined = dataLines.join('\n');
    if (joined != '[DONE]') {
      yield SseEvent(event: currentEvent, data: joined);
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/sse_test.dart`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/sse.dart test/llm/sse_test.dart
git commit -m "feat: add SSE stream decoder for LLM provider streaming"
```

---

## Task 2: Tool Schema Translation

**Files:**

- Create: `lib/src/llm/tool_schema.dart`
- Test: `test/llm/tool_schema_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/tool_schema_test.dart
import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/tool_schema.dart';

void main() {
  final tool = ReadFileTool();

  group('AnthropicToolEncoder', () {
    test('produces Anthropic-native schema', () {
      final encoder = AnthropicToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['name'], 'read_file');
      expect(s['description'], isNotEmpty);
      expect(s, contains('input_schema'));
      expect(s['input_schema']['type'], 'object');
      expect(s['input_schema']['properties'], contains('path'));
    });
  });

  group('OpenAiToolEncoder', () {
    test('produces OpenAI function-calling schema', () {
      final encoder = OpenAiToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['type'], 'function');
      expect(s['function']['name'], 'read_file');
      expect(s['function']['description'], isNotEmpty);
      expect(s['function']['parameters']['type'], 'object');
      expect(s['function']['parameters']['properties'], contains('path'));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/tool_schema_test.dart`
Expected: FAIL — file not found

**Step 3: Write minimal implementation**

```dart
// lib/src/llm/tool_schema.dart

import '../agent/tools.dart';

/// Encodes [Tool] definitions into provider-specific JSON schemas.
sealed class ToolSchemaEncoder {
  const ToolSchemaEncoder();

  List<Map<String, dynamic>> encodeAll(List<Tool> tools);
}

/// Anthropic Messages API tool format.
///
/// Uses the existing `Tool.toSchema()` which already produces
/// `{name, description, input_schema: {type, properties, required}}`.
class AnthropicToolEncoder extends ToolSchemaEncoder {
  const AnthropicToolEncoder();

  @override
  List<Map<String, dynamic>> encodeAll(List<Tool> tools) =>
      [for (final t in tools) t.toSchema()];
}

/// OpenAI Chat Completions function-calling format.
///
/// Wraps each tool in `{type: "function", function: {name, description, parameters}}`.
class OpenAiToolEncoder extends ToolSchemaEncoder {
  const OpenAiToolEncoder();

  @override
  List<Map<String, dynamic>> encodeAll(List<Tool> tools) => [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': {
                'type': 'object',
                'properties': {
                  for (final p in t.parameters) p.name: p.toSchema(),
                },
                'required': [
                  for (final p in t.parameters)
                    if (p.required) p.name,
                ],
              },
            },
          }
      ];
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/tool_schema_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/tool_schema.dart test/llm/tool_schema_test.dart
git commit -m "feat: add per-provider tool schema encoders (Anthropic/OpenAI)"
```

---

## Task 3: Message Mapper & System Prompts

**Files:**

- Create: `lib/src/llm/message_mapper.dart`
- Create: `lib/src/agent/prompts.dart`
- Test: `test/llm/message_mapper_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/message_mapper_test.dart
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/message_mapper.dart';

void main() {
  final messages = [
    Message.user('hello'),
    Message.assistant(text: 'hi there', toolCalls: [
      ToolCall(id: 'tc1', name: 'read_file', arguments: {'path': 'f.txt'}),
    ]),
    Message.toolResult(callId: 'tc1', content: 'file contents'),
  ];

  group('AnthropicMessageMapper', () {
    test('maps user message', () {
      final mapper = AnthropicMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      // System prompt is returned separately.
      expect(result.systemPrompt, 'You are Glue.');
      expect(result.messages.first['role'], 'user');
    });

    test('maps tool result as user role', () {
      final mapper = AnthropicMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'user');
      expect(toolResultMsg['content'], isList);
      final block = (toolResultMsg['content'] as List).first as Map;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 'tc1');
    });
  });

  group('OpenAiMessageMapper', () {
    test('prepends system message', () {
      final mapper = OpenAiMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      expect(result.messages.first['role'], 'system');
      expect(result.messages.first['content'], 'You are Glue.');
    });

    test('maps tool result as tool role', () {
      final mapper = OpenAiMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'tool');
      expect(toolResultMsg['tool_call_id'], 'tc1');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/message_mapper_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/agent/prompts.dart

/// System prompt templates for the Glue agent.
class Prompts {
  Prompts._();

  static const String system = '''
You are Glue, an expert coding agent that helps developers with software engineering tasks.

You operate inside a terminal. You have access to tools for reading files, writing files,
running shell commands, searching code, and listing directories.

Guidelines:
- Be direct and technical. Respect the developer's expertise.
- Use tools proactively to gather context before answering.
- When modifying code, read the file first to understand conventions.
- Make the smallest reasonable change. Don't over-engineer.
- If a task requires multiple steps, work through them sequentially.
- Always verify your work by reading back files you've written.
''';

  /// Build a full system prompt, optionally appending project-specific context.
  static String build({String? projectContext}) {
    final buf = StringBuffer(system);
    if (projectContext != null && projectContext.isNotEmpty) {
      buf.write('\n\n## Project Context\n\n$projectContext');
    }
    return buf.toString();
  }
}
```

```dart
// lib/src/llm/message_mapper.dart

import '../agent/agent_core.dart';

/// Result of mapping Glue messages to a provider-specific format.
class MappedMessages {
  /// System prompt (Anthropic: separate field; OpenAI: prepended message).
  final String systemPrompt;

  /// Provider-formatted message list.
  final List<Map<String, dynamic>> messages;

  MappedMessages({required this.systemPrompt, required this.messages});
}

/// Maps Glue [Message] objects to provider-specific JSON payloads.
sealed class MessageMapper {
  const MessageMapper();

  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  });
}

/// Anthropic Messages API format.
///
/// - System prompt is a separate top-level field.
/// - Tool results are sent as `role: "user"` with `type: "tool_result"` blocks.
/// - Assistant tool calls are `type: "tool_use"` content blocks.
class AnthropicMessageMapper extends MessageMapper {
  const AnthropicMessageMapper();

  @override
  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  }) {
    final mapped = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          mapped.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': msg.text ?? ''}
            ],
          });
        case Role.assistant:
          final content = <Map<String, dynamic>>[];
          if (msg.text != null && msg.text!.isNotEmpty) {
            content.add({'type': 'text', 'text': msg.text});
          }
          for (final tc in msg.toolCalls) {
            content.add({
              'type': 'tool_use',
              'id': tc.id,
              'name': tc.name,
              'input': tc.arguments,
            });
          }
          mapped.add({'role': 'assistant', 'content': content});
        case Role.toolResult:
          mapped.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': msg.toolCallId,
                'content': msg.text ?? '',
              }
            ],
          });
      }
    }

    return MappedMessages(systemPrompt: systemPrompt, messages: mapped);
  }
}

/// OpenAI Chat Completions format.
///
/// - System prompt is a message with `role: "system"`.
/// - Tool results use `role: "tool"` with `tool_call_id`.
/// - Assistant tool calls are stored in `tool_calls` array.
class OpenAiMessageMapper extends MessageMapper {
  const OpenAiMessageMapper();

  @override
  MappedMessages mapMessages(
    List<Message> messages, {
    required String systemPrompt,
  }) {
    final mapped = <Map<String, dynamic>>[];

    // OpenAI: system prompt is a message.
    if (systemPrompt.isNotEmpty) {
      mapped.add({'role': 'system', 'content': systemPrompt});
    }

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          mapped.add({'role': 'user', 'content': msg.text ?? ''});
        case Role.assistant:
          final entry = <String, dynamic>{
            'role': 'assistant',
            'content': msg.text ?? '',
          };
          if (msg.toolCalls.isNotEmpty) {
            entry['tool_calls'] = [
              for (final tc in msg.toolCalls)
                {
                  'id': tc.id,
                  'type': 'function',
                  'function': {
                    'name': tc.name,
                    'arguments': tc.arguments.toString(),
                  },
                }
            ];
          }
          mapped.add(entry);
        case Role.toolResult:
          mapped.add({
            'role': 'tool',
            'tool_call_id': msg.toolCallId,
            'content': msg.text ?? '',
          });
      }
    }

    return MappedMessages(systemPrompt: systemPrompt, messages: mapped);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/message_mapper_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/agent/prompts.dart lib/src/llm/message_mapper.dart test/llm/message_mapper_test.dart
git commit -m "feat: add system prompts and per-provider message mappers"
```

---

## Task 4: Anthropic Client

**Files:**

- Create: `lib/src/llm/anthropic_client.dart`
- Test: `test/llm/anthropic_client_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/anthropic_client_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/anthropic_client.dart';

// A mock HTTP client is complex; test the SSE parsing logic directly.
void main() {
  group('AnthropicClient.parseStream', () {
    test('parses text deltas from SSE events', () async {
      final events = [
        _sseData({'type': 'message_start', 'message': {'id': 'm1', 'usage': {'input_tokens': 10, 'output_tokens': 0}}}),
        _sseData({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}}),
        _sseData({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'Hello '}}),
        _sseData({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'world'}}),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 5}}),
        _sseData({'type': 'message_stop'}),
      ];
      final chunks = await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final textDeltas = chunks.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.text).join(), 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, isNotEmpty);
    });

    test('parses tool use blocks', () async {
      final events = [
        _sseData({'type': 'message_start', 'message': {'id': 'm1', 'usage': {'input_tokens': 10, 'output_tokens': 0}}}),
        _sseData({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'tool_use', 'id': 'tc1', 'name': 'read_file'}}),
        _sseData({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'input_json_delta', 'partial_json': '{"path"'}}),
        _sseData({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'input_json_delta', 'partial_json': ': "main.dart"}'}}),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({'type': 'message_delta', 'delta': {'stop_reason': 'tool_use'}, 'usage': {'output_tokens': 15}}),
        _sseData({'type': 'message_stop'}),
      ];

      final chunks = await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });
}

Map<String, dynamic> _sseData(Map<String, dynamic> payload) => payload;
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/anthropic_client_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/llm/anthropic_client.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../agent/tools.dart';
import 'message_mapper.dart';
import 'sse.dart';
import 'tool_schema.dart';

/// LLM client for the Anthropic Messages API with streaming.
class AnthropicClient implements LlmClient {
  final http.Client _http;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _apiVersion = '2023-01-01';
  static const _defaultBaseUrl = 'https://api.anthropic.com';

  AnthropicClient({
    required http.Client httpClient,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
  })  : _http = httpClient,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
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

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'Anthropic API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    );
  }

  /// Parse Anthropic SSE event payloads into [LlmChunk]s.
  ///
  /// Exposed as static for testability (can feed synthetic events).
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    // Buffer for accumulating partial tool use input JSON.
    final toolBuffers = <int, _ToolUseBuffer>{};
    int inputTokens = 0;
    int outputTokens = 0;

    await for (final event in events) {
      final type = event['type'] as String?;

      switch (type) {
        case 'message_start':
          final usage = (event['message'] as Map?)?['usage'] as Map?;
          if (usage != null) {
            inputTokens = (usage['input_tokens'] as int?) ?? 0;
          }

        case 'content_block_start':
          final index = event['index'] as int;
          final block = event['content_block'] as Map<String, dynamic>;
          if (block['type'] == 'tool_use') {
            toolBuffers[index] = _ToolUseBuffer(
              id: block['id'] as String,
              name: block['name'] as String,
            );
          }

        case 'content_block_delta':
          final index = event['index'] as int;
          final delta = event['delta'] as Map<String, dynamic>;
          final deltaType = delta['type'] as String?;

          if (deltaType == 'text_delta') {
            yield TextDelta(delta['text'] as String);
          } else if (deltaType == 'input_json_delta') {
            toolBuffers[index]?.buffer.write(delta['partial_json'] as String);
          }

        case 'content_block_stop':
          final index = event['index'] as int;
          final buf = toolBuffers.remove(index);
          if (buf != null) {
            final argsJson = buf.buffer.toString();
            final args = argsJson.isNotEmpty
                ? (jsonDecode(argsJson) as Map<String, dynamic>)
                : <String, dynamic>{};
            yield ToolCallDelta(ToolCall(
              id: buf.id,
              name: buf.name,
              arguments: args,
            ));
          }

        case 'message_delta':
          final usage = event['usage'] as Map?;
          if (usage != null) {
            outputTokens = (usage['output_tokens'] as int?) ?? 0;
          }

        case 'message_stop':
          yield UsageInfo(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          );
      }
    }
  }
}

class _ToolUseBuffer {
  final String id;
  final String name;
  final StringBuffer buffer = StringBuffer();
  _ToolUseBuffer({required this.id, required this.name});
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/anthropic_client_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/anthropic_client.dart test/llm/anthropic_client_test.dart
git commit -m "feat: add Anthropic Messages API streaming client"
```

---

## Task 5: OpenAI Client

**Files:**

- Create: `lib/src/llm/openai_client.dart`
- Test: `test/llm/openai_client_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/openai_client_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/openai_client.dart';

void main() {
  group('OpenAiClient.parseStream', () {
    test('parses text deltas', () async {
      final events = [
        {'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': 'Hello '}}]},
        {'choices': [{'index': 0, 'delta': {'content': 'world'}}]},
        {'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 10, 'completion_tokens': 5}},
      ];
      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');
    });

    test('parses streaming tool calls', () async {
      final events = [
        {'choices': [{'index': 0, 'delta': {'role': 'assistant', 'tool_calls': [{'index': 0, 'id': 'tc1', 'type': 'function', 'function': {'name': 'read_file', 'arguments': ''}}]}}]},
        {'choices': [{'index': 0, 'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': '{"path":'}}]}}]},
        {'choices': [{'index': 0, 'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': ' "main.dart"}'}}]}}]},
        {'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}], 'usage': {'prompt_tokens': 10, 'completion_tokens': 15}},
      ];

      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/openai_client_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/llm/openai_client.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../agent/tools.dart';
import 'message_mapper.dart';
import 'sse.dart';
import 'tool_schema.dart';

/// LLM client for OpenAI Chat Completions API with streaming.
class OpenAiClient implements LlmClient {
  final http.Client _http;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _defaultBaseUrl = 'https://api.openai.com';

  OpenAiClient({
    required http.Client httpClient,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
  })  : _http = httpClient,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
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

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'OpenAI API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    );
  }

  /// Parse OpenAI streaming chunks into [LlmChunk]s.
  ///
  /// Exposed as static for testability.
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    // Accumulate streamed tool call arguments.
    final toolBuilders = <int, _ToolCallBuilder>{};

    await for (final event in events) {
      // Usage may come in a final chunk.
      final usage = event['usage'] as Map<String, dynamic>?;

      final choices = event['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        // Usage-only chunk (stream_options.include_usage).
        if (usage != null) {
          yield UsageInfo(
            inputTokens: (usage['prompt_tokens'] as int?) ?? 0,
            outputTokens: (usage['completion_tokens'] as int?) ?? 0,
          );
        }
        continue;
      }

      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>? ?? {};
      final finishReason = choice['finish_reason'] as String?;

      // Text content.
      final content = delta['content'] as String?;
      if (content != null && content.isNotEmpty) {
        yield TextDelta(content);
      }

      // Tool calls (streamed incrementally).
      final toolCalls = delta['tool_calls'] as List?;
      if (toolCalls != null) {
        for (final tc in toolCalls) {
          final tcMap = tc as Map<String, dynamic>;
          final index = tcMap['index'] as int;
          final fn = tcMap['function'] as Map<String, dynamic>?;

          if (!toolBuilders.containsKey(index)) {
            toolBuilders[index] = _ToolCallBuilder(
              id: (tcMap['id'] as String?) ?? 'call_$index',
              name: fn?['name'] as String? ?? '',
            );
          }

          final args = fn?['arguments'] as String?;
          if (args != null) {
            toolBuilders[index]!.argsBuffer.write(args);
          }
        }
      }

      // On finish, emit completed tool calls.
      if (finishReason != null && toolBuilders.isNotEmpty) {
        for (final builder in toolBuilders.values) {
          final argsStr = builder.argsBuffer.toString();
          final args = argsStr.isNotEmpty
              ? (jsonDecode(argsStr) as Map<String, dynamic>)
              : <String, dynamic>{};
          yield ToolCallDelta(ToolCall(
            id: builder.id,
            name: builder.name,
            arguments: args,
          ));
        }
        toolBuilders.clear();
      }

      // Usage in final chunk.
      if (usage != null) {
        yield UsageInfo(
          inputTokens: (usage['prompt_tokens'] as int?) ?? 0,
          outputTokens: (usage['completion_tokens'] as int?) ?? 0,
        );
      }
    }
  }
}

class _ToolCallBuilder {
  final String id;
  final String name;
  final StringBuffer argsBuffer = StringBuffer();
  _ToolCallBuilder({required this.id, required this.name});
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/openai_client_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/openai_client.dart test/llm/openai_client_test.dart
git commit -m "feat: add OpenAI Chat Completions streaming client"
```

---

## Task 6: NDJSON Decoder & Ollama Client

**Files:**

- Create: `lib/src/llm/ndjson.dart`
- Create: `lib/src/llm/ollama_client.dart`
- Test: `test/llm/ollama_client_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/ollama_client_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/ollama_client.dart';

void main() {
  group('OllamaClient.parseStream', () {
    test('parses text deltas from streaming JSON', () async {
      final events = [
        {'model': 'llama3.2', 'message': {'role': 'assistant', 'content': 'Hello '}, 'done': false},
        {'model': 'llama3.2', 'message': {'role': 'assistant', 'content': 'world'}, 'done': false},
        {'model': 'llama3.2', 'message': {'role': 'assistant', 'content': ''}, 'done': true,
         'prompt_eval_count': 26, 'eval_count': 10},
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, hasLength(1));
      expect(usage.first.inputTokens, 26);
      expect(usage.first.outputTokens, 10);
    });

    test('parses tool calls', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'main.dart'},
                }
              }
            ]
          },
          'done': false,
        },
        {'model': 'llama3.2', 'message': {'role': 'assistant', 'content': ''}, 'done': true,
         'prompt_eval_count': 20, 'eval_count': 15},
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/ollama_client_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/llm/ndjson.dart

import 'dart:async';
import 'dart:convert';

/// Decode a newline-delimited JSON stream (NDJSON) from raw bytes.
///
/// Ollama uses this format instead of SSE: each line is a complete
/// JSON object, streamed one per response chunk.
Stream<Map<String, dynamic>> decodeNdjson(Stream<List<int>> bytes) async* {
  final buffer = StringBuffer();

  await for (final chunk in bytes) {
    buffer.write(utf8.decode(chunk));

    while (true) {
      final content = buffer.toString();
      final nlIndex = content.indexOf('\n');
      if (nlIndex == -1) break;

      final line = content.substring(0, nlIndex).trim();
      buffer
        ..clear()
        ..write(content.substring(nlIndex + 1));

      if (line.isEmpty) continue;

      yield jsonDecode(line) as Map<String, dynamic>;
    }
  }

  // Flush remaining content.
  final remaining = buffer.toString().trim();
  if (remaining.isNotEmpty) {
    yield jsonDecode(remaining) as Map<String, dynamic>;
  }
}
```

```dart
// lib/src/llm/ollama_client.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../agent/tools.dart';
import 'ndjson.dart';
import 'tool_schema.dart';

/// LLM client for Ollama local API with streaming.
///
/// Ollama uses NDJSON streaming (not SSE) and its own message format.
/// Tool calling uses OpenAI-compatible tool schemas but returns
/// arguments as parsed objects (not JSON strings).
class OllamaClient implements LlmClient {
  final http.Client _http;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  OllamaClient({
    required http.Client httpClient,
    required this.model,
    required this.systemPrompt,
    String baseUrl = 'http://localhost:11434',
  })  : _http = httpClient,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final mappedMessages = <Map<String, dynamic>>[];

    // System prompt as first message.
    if (systemPrompt.isNotEmpty) {
      mappedMessages.add({'role': 'system', 'content': systemPrompt});
    }

    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          mappedMessages.add({'role': 'user', 'content': msg.text ?? ''});
        case Role.assistant:
          final entry = <String, dynamic>{
            'role': 'assistant',
            'content': msg.text ?? '',
          };
          if (msg.toolCalls.isNotEmpty) {
            entry['tool_calls'] = [
              for (final tc in msg.toolCalls)
                {
                  'function': {
                    'name': tc.name,
                    'arguments': tc.arguments,
                  },
                }
            ];
          }
          mappedMessages.add(entry);
        case Role.toolResult:
          mappedMessages.add({
            'role': 'tool',
            'content': msg.text ?? '',
            'tool_name': msg.toolCallId ?? '',
          });
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': mappedMessages,
      'stream': true,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
    }

    final request = http.Request(
      'POST',
      _baseUri.resolve('/api/chat'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'Ollama API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parseStreamEvents(decodeNdjson(response.stream));
  }

  /// Parse Ollama NDJSON streaming events into [LlmChunk]s.
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    int _toolCallCounter = 0;

    await for (final event in events) {
      final message = event['message'] as Map<String, dynamic>?;
      final done = event['done'] as bool? ?? false;

      if (message != null) {
        // Text content.
        final content = message['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield TextDelta(content);
        }

        // Tool calls — Ollama delivers them fully formed (not streamed incrementally).
        final toolCalls = message['tool_calls'] as List?;
        if (toolCalls != null) {
          for (final tc in toolCalls) {
            final fn = (tc as Map<String, dynamic>)['function'] as Map<String, dynamic>;
            _toolCallCounter++;
            yield ToolCallDelta(ToolCall(
              id: 'ollama_tc_$_toolCallCounter',
              name: fn['name'] as String,
              // Ollama returns arguments as a parsed Map, not a JSON string.
              arguments: Map<String, dynamic>.from(fn['arguments'] as Map),
            ));
          }
        }
      }

      // Final chunk contains token counts.
      if (done) {
        final promptTokens = event['prompt_eval_count'] as int? ?? 0;
        final evalTokens = event['eval_count'] as int? ?? 0;
        yield UsageInfo(inputTokens: promptTokens, outputTokens: evalTokens);
      }
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/ollama_client_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/ndjson.dart lib/src/llm/ollama_client.dart test/llm/ollama_client_test.dart
git commit -m "feat: add Ollama local LLM client with NDJSON streaming"
```

---

## Task 7: Configuration System

**Files:**

- Create: `lib/src/config/glue_config.dart`
- Test: `test/config/glue_config_test.dart`

**Step 1: Write the failing test**

```dart
// test/config/glue_config_test.dart
import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';

void main() {
  group('GlueConfig', () {
    test('resolves provider and model from explicit values', () {
      final config = GlueConfig(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        anthropicApiKey: 'sk-ant-test',
      );
      expect(config.provider, LlmProvider.anthropic);
      expect(config.model, 'claude-sonnet-4-6');
      expect(config.anthropicApiKey, 'sk-ant-test');
    });

    test('defaults to anthropic/claude-sonnet-4-6', () {
      final config = GlueConfig(anthropicApiKey: 'sk-ant-test');
      expect(config.provider, LlmProvider.anthropic);
      expect(config.model, 'claude-sonnet-4-6');
    });

    test('resolves openai provider', () {
      final config = GlueConfig(
        provider: LlmProvider.openai,
        model: 'gpt-4.1',
        openaiApiKey: 'sk-test',
      );
      expect(config.provider, LlmProvider.openai);
      expect(config.model, 'gpt-4.1');
    });

    test('resolves ollama provider (no API key needed)', () {
      final config = GlueConfig(
        provider: LlmProvider.ollama,
        model: 'qwen2.5-coder',
      );
      expect(config.provider, LlmProvider.ollama);
      expect(config.model, 'qwen2.5-coder');
      config.validate(); // Should not throw
    });

    test('validates API key presence', () {
      expect(
        () => GlueConfig(provider: LlmProvider.anthropic).validate(),
        throwsA(isA<ConfigError>()),
      );
    });

    test('profiles override defaults', () {
      final config = GlueConfig(
        anthropicApiKey: 'sk-ant',
        openaiApiKey: 'sk-oai',
        profiles: {
          'architect': AgentProfile(provider: LlmProvider.anthropic, model: 'claude-opus-4-6'),
          'editor': AgentProfile(provider: LlmProvider.openai, model: 'gpt-4.1-mini'),
          'local': AgentProfile(provider: LlmProvider.ollama, model: 'qwen2.5-coder'),
        },
      );
      expect(config.profiles['architect']!.model, 'claude-opus-4-6');
      expect(config.profiles['editor']!.provider, LlmProvider.openai);
      expect(config.profiles['local']!.provider, LlmProvider.ollama);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/config/glue_config_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/config/glue_config.dart

import 'dart:io';
import 'package:yaml/yaml.dart';

/// Supported LLM providers.
enum LlmProvider { anthropic, openai, ollama }

/// An agent profile specifying provider and model for a particular role.
class AgentProfile {
  final LlmProvider provider;
  final String model;

  const AgentProfile({required this.provider, required this.model});

  @override
  String toString() => 'AgentProfile($provider, $model)';
}

/// Error thrown when configuration is invalid.
class ConfigError implements Exception {
  final String message;
  ConfigError(this.message);

  @override
  String toString() => 'ConfigError: $message';
}

/// Glue application configuration.
///
/// Resolution order: CLI args → env vars → config file → defaults.
class GlueConfig {
  final LlmProvider provider;
  final String model;
  final String? anthropicApiKey;
  final String? openaiApiKey;
  final String ollamaBaseUrl;
  final Map<String, AgentProfile> profiles;
  final int maxSubagentDepth;

  GlueConfig({
    LlmProvider? provider,
    String? model,
    this.anthropicApiKey,
    this.openaiApiKey,
    this.ollamaBaseUrl = 'http://localhost:11434',
    this.profiles = const {},
    this.maxSubagentDepth = 2,
  })  : provider = provider ?? LlmProvider.anthropic,
        model = model ?? _defaultModel(provider ?? LlmProvider.anthropic);

  static String _defaultModel(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => 'claude-sonnet-4-6',
        LlmProvider.openai => 'gpt-4.1',
        LlmProvider.ollama => 'llama3.2',
      };

  /// Validate that required configuration is present.
  void validate() {
    // Ollama runs locally — no API key needed.
    if (provider == LlmProvider.ollama) return;

    final key = switch (provider) {
      LlmProvider.anthropic => anthropicApiKey,
      LlmProvider.openai => openaiApiKey,
      LlmProvider.ollama => '', // unreachable
    };
    if (key == null || key.isEmpty) {
      throw ConfigError(
        'Missing API key for provider ${provider.name}. '
        'Set ${provider == LlmProvider.anthropic ? "ANTHROPIC_API_KEY" : "OPENAI_API_KEY"} '
        'or add it to ~/.glue/config.yaml',
      );
    }
  }

  /// API key for the currently selected provider (empty for Ollama).
  String get apiKey {
    if (provider == LlmProvider.ollama) return '';
    validate();
    return switch (provider) {
      LlmProvider.anthropic => anthropicApiKey!,
      LlmProvider.openai => openaiApiKey!,
      LlmProvider.ollama => '',
    };
  }

  /// Load configuration from env vars, optional config file, and CLI overrides.
  factory GlueConfig.load({
    String? cliProvider,
    String? cliModel,
  }) {
    // 1. Load from config file.
    final configFile = File(
      '${Platform.environment['HOME'] ?? '.'}/.glue/config.yaml',
    );
    Map<String, dynamic>? fileConfig;
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        fileConfig = Map<String, dynamic>.from(yaml);
      }
    }

    // 2. Resolve values: CLI → env → file → defaults.
    final providerStr = cliProvider ??
        Platform.environment['GLUE_PROVIDER'] ??
        fileConfig?['provider'] as String?;

    final provider = providerStr != null
        ? LlmProvider.values.firstWhere(
            (p) => p.name == providerStr,
            orElse: () => LlmProvider.anthropic,
          )
        : LlmProvider.anthropic;

    final model = cliModel ??
        Platform.environment['GLUE_MODEL'] ??
        fileConfig?['model'] as String? ??
        _defaultModel(provider);

    final anthropicKey = Platform.environment['ANTHROPIC_API_KEY'] ??
        Platform.environment['GLUE_ANTHROPIC_API_KEY'] ??
        (fileConfig?['anthropic'] as Map?)?['api_key'] as String?;

    final openaiKey = Platform.environment['OPENAI_API_KEY'] ??
        Platform.environment['GLUE_OPENAI_API_KEY'] ??
        (fileConfig?['openai'] as Map?)?['api_key'] as String?;

    // 3. Parse profiles.
    final profiles = <String, AgentProfile>{};
    final profilesYaml = fileConfig?['profiles'] as Map?;
    if (profilesYaml != null) {
      for (final entry in profilesYaml.entries) {
        final name = entry.key as String;
        final val = entry.value as Map;
        profiles[name] = AgentProfile(
          provider: LlmProvider.values.firstWhere(
            (p) => p.name == (val['provider'] as String? ?? 'anthropic'),
          ),
          model: val['model'] as String? ?? _defaultModel(provider),
        );
      }
    }

    return GlueConfig(
      provider: provider,
      model: model,
      anthropicApiKey: anthropicKey,
      openaiApiKey: openaiKey,
      profiles: profiles,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/config/glue_config_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/config/glue_config.dart test/config/glue_config_test.dart
git commit -m "feat: add configuration system with multi-provider support"
```

---

## Task 8: LLM Client Factory

**Files:**

- Create: `lib/src/llm/llm_factory.dart`
- Test: `test/llm/llm_factory_test.dart`

**Step 1: Write the failing test**

```dart
// test/llm/llm_factory_test.dart
import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/llm/openai_client.dart';

void main() {
  group('LlmClientFactory', () {
    test('creates AnthropicClient for anthropic provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        apiKey: 'sk-test',
        systemPrompt: 'test',
      );
      expect(client, isA<AnthropicClient>());
    });

    test('creates OpenAiClient for openai provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.openai,
        model: 'gpt-4.1',
        apiKey: 'sk-test',
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiClient>());
    });

    test('creates OllamaClient for ollama provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.ollama,
        model: 'llama3.2',
        apiKey: '',
        systemPrompt: 'test',
      );
      expect(client, isA<OllamaClient>());
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/llm/llm_factory_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/llm/llm_factory.dart

import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../config/glue_config.dart';
import 'anthropic_client.dart';
import 'openai_client.dart';
import 'ollama_client.dart';

/// Creates [LlmClient] instances from configuration.
class LlmClientFactory {
  final http.Client _httpClient;

  LlmClientFactory({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Create an [LlmClient] for the given provider and model.
  LlmClient create({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
    String ollamaBaseUrl = 'http://localhost:11434',
  }) {
    return switch (provider) {
      LlmProvider.anthropic => AnthropicClient(
          httpClient: _httpClient,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
        ),
      LlmProvider.openai => OpenAiClient(
          httpClient: _httpClient,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
        ),
      LlmProvider.ollama => OllamaClient(
          httpClient: _httpClient,
          model: model,
          systemPrompt: systemPrompt,
          baseUrl: ollamaBaseUrl,
        ),
    };
  }

  /// Create an [LlmClient] from a [GlueConfig] using its defaults.
  LlmClient createFromConfig(GlueConfig config, {required String systemPrompt}) {
    return create(
      provider: config.provider,
      model: config.model,
      apiKey: config.apiKey,
      systemPrompt: systemPrompt,
    );
  }

  /// Create an [LlmClient] from an [AgentProfile] with keys from config.
  LlmClient createFromProfile(
    AgentProfile profile,
    GlueConfig config, {
    required String systemPrompt,
  }) {
    final apiKey = switch (profile.provider) {
      LlmProvider.anthropic => config.anthropicApiKey!,
      LlmProvider.openai => config.openaiApiKey!,
    };
    return create(
      provider: profile.provider,
      model: profile.model,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/llm/llm_factory_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/llm/llm_factory.dart test/llm/llm_factory_test.dart
git commit -m "feat: add LLM client factory for provider instantiation"
```

---

## Task 9: Agent Runner (Headless Execution)

**Files:**

- Create: `lib/src/agent/agent_runner.dart`
- Test: `test/agent/agent_runner_test.dart`

**Step 1: Write the failing test**

```dart
// test/agent/agent_runner_test.dart
import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/tools.dart';

/// Minimal LLM that returns text only (no tool calls).
class _TextOnlyLlm implements LlmClient {
  final String response;
  _TextOnlyLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    for (final word in response.split(' ')) {
      yield TextDelta('$word ');
    }
    yield UsageInfo(inputTokens: 10, outputTokens: 5);
  }
}

/// LLM that makes one tool call then responds.
class _ToolCallLlm implements LlmClient {
  int _callCount = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _callCount++;
    if (_callCount == 1) {
      yield TextDelta('Let me check. ');
      yield ToolCallDelta(ToolCall(
        id: 'tc1',
        name: 'list_directory',
        arguments: {'path': '.'},
      ));
      yield UsageInfo(inputTokens: 10, outputTokens: 10);
    } else {
      yield TextDelta('Found the files.');
      yield UsageInfo(inputTokens: 20, outputTokens: 10);
    }
  }
}

void main() {
  group('AgentRunner', () {
    test('runs text-only response to completion', () async {
      final core = AgentCore(
        llm: _TextOnlyLlm('Hello from the agent'),
        tools: {},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('Hi');
      expect(result, contains('Hello'));
    });

    test('auto-approves tool calls in headless mode', () async {
      final core = AgentCore(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('List files');
      expect(result, contains('Found the files'));
    });

    test('denies tool calls in denyAll mode', () async {
      final core = AgentCore(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.denyAll,
      );
      final result = await runner.runToCompletion('List files');
      // After denial, the LLM gets another turn and responds
      expect(result, contains('Found the files'));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/agent/agent_runner_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/agent/agent_runner.dart

import 'dart:async';
import 'agent_core.dart';

/// Policy for automatic tool approval in headless execution.
enum ToolApprovalPolicy {
  /// Automatically approve and execute all tool calls.
  autoApproveAll,

  /// Deny all tool calls.
  denyAll,

  /// Approve only tools in an allowlist.
  allowlist,
}

/// Runs an [AgentCore] to completion without interactive approval.
///
/// Used for subagent execution where the parent agent has already
/// decided the task and tools should run without human intervention.
class AgentRunner {
  final AgentCore core;
  final ToolApprovalPolicy policy;
  final Set<String> _allowedTools;

  AgentRunner({
    required this.core,
    required this.policy,
    Set<String>? allowedTools,
  }) : _allowedTools = allowedTools ?? const {};

  /// Run a [userMessage] through the agent loop until completion.
  ///
  /// Returns the concatenated assistant text output.
  Future<String> runToCompletion(String userMessage) async {
    final buf = StringBuffer();

    await for (final event in core.run(userMessage)) {
      switch (event) {
        case AgentTextDelta(:final delta):
          buf.write(delta);
        case AgentToolCall(:final call):
          final result = await _handleToolCall(call);
          core.completeToolCall(result);
        case AgentToolResult():
          break;
        case AgentDone():
          break;
        case AgentError(:final error):
          buf.write('\nError: $error');
      }
    }

    return buf.toString();
  }

  Future<ToolResult> _handleToolCall(ToolCall call) async {
    final approved = switch (policy) {
      ToolApprovalPolicy.autoApproveAll => true,
      ToolApprovalPolicy.denyAll => false,
      ToolApprovalPolicy.allowlist => _allowedTools.contains(call.name),
    };

    if (approved) {
      return core.executeTool(call);
    }
    return ToolResult.denied(call.id);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/agent/agent_runner_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/agent/agent_runner.dart test/agent/agent_runner_test.dart
git commit -m "feat: add headless AgentRunner with configurable approval policies"
```

---

## Task 10: Agent Manager (Subagent Orchestration)

**Files:**

- Create: `lib/src/agent/agent_manager.dart`
- Test: `test/agent/agent_manager_test.dart`

**Step 1: Write the failing test**

```dart
// test/agent/agent_manager_test.dart
import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';

class _EchoLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final lastMsg = messages.lastWhere((m) => m.role == Role.user);
    yield TextDelta('Processed: ${lastMsg.text}');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _TestLlmFactory extends LlmClientFactory {
  @override
  LlmClient create({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
  }) => _EchoLlm();
}

void main() {
  group('AgentManager', () {
    late AgentManager manager;

    setUp(() {
      manager = AgentManager(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _TestLlmFactory(),
        config: GlueConfig(anthropicApiKey: 'test'),
        systemPrompt: 'You are a test agent.',
      );
    });

    test('spawns a single subagent', () async {
      final result = await manager.spawnSubagent(task: 'Do something');
      expect(result, contains('Processed:'));
      expect(result, contains('Do something'));
    });

    test('spawns parallel subagents', () async {
      final results = await manager.spawnParallel(
        tasks: ['Task A', 'Task B', 'Task C'],
      );
      expect(results, hasLength(3));
      expect(results[0], contains('Task A'));
      expect(results[1], contains('Task B'));
      expect(results[2], contains('Task C'));
    });

    test('enforces max depth', () async {
      expect(
        () => manager.spawnSubagent(task: 'deep', currentDepth: 3),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/agent/agent_manager_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/agent/agent_manager.dart

import 'agent_core.dart';
import 'agent_runner.dart';
import 'tools.dart';
import '../config/glue_config.dart';
import '../llm/llm_factory.dart';

/// Orchestrates subagent spawning using the manager pattern.
///
/// Creates independent [AgentCore] instances with their own conversation
/// history but shared tool registry. Subagents run headlessly via
/// [AgentRunner] with auto-approve policy.
class AgentManager {
  final Map<String, Tool> tools;
  final LlmClientFactory llmFactory;
  final GlueConfig config;
  final String systemPrompt;

  AgentManager({
    required this.tools,
    required this.llmFactory,
    required this.config,
    required this.systemPrompt,
  });

  /// Spawn a single subagent to complete a [task].
  ///
  /// Optionally override [profile] for model/provider selection.
  /// [currentDepth] tracks recursion to prevent infinite nesting.
  Future<String> spawnSubagent({
    required String task,
    AgentProfile? profile,
    int currentDepth = 0,
  }) async {
    if (currentDepth >= config.maxSubagentDepth) {
      throw Exception(
        'Maximum subagent depth (${config.maxSubagentDepth}) exceeded. '
        'Cannot spawn deeper subagents.',
      );
    }

    final effectiveProfile = profile ??
        AgentProfile(provider: config.provider, model: config.model);

    final llm = llmFactory.create(
      provider: effectiveProfile.provider,
      model: effectiveProfile.model,
      apiKey: _apiKeyFor(effectiveProfile.provider),
      systemPrompt: systemPrompt,
    );

    // Subagents get all tools except subagent-spawning tools
    // to prevent infinite recursion at the tool level.
    final subagentTools = Map<String, Tool>.from(tools)
      ..removeWhere((name, _) =>
          name == 'spawn_subagent' || name == 'spawn_parallel_subagents');

    final core = AgentCore(
      llm: llm,
      tools: subagentTools,
      modelName: effectiveProfile.model,
    );

    final runner = AgentRunner(
      core: core,
      policy: ToolApprovalPolicy.autoApproveAll,
    );

    return runner.runToCompletion(task);
  }

  /// Spawn [tasks] in parallel, each as an independent subagent.
  ///
  /// All subagents run concurrently and results are returned in order.
  Future<List<String>> spawnParallel({
    required List<String> tasks,
    AgentProfile? profile,
    int currentDepth = 0,
  }) async {
    return Future.wait([
      for (final task in tasks)
        spawnSubagent(
          task: task,
          profile: profile,
          currentDepth: currentDepth,
        ),
    ]);
  }

  String _apiKeyFor(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => config.anthropicApiKey ?? '',
        LlmProvider.openai => config.openaiApiKey ?? '',
      };
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/agent/agent_manager_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/agent/agent_manager.dart test/agent/agent_manager_test.dart
git commit -m "feat: add AgentManager for subagent orchestration"
```

---

## Task 11: Subagent Tools

**Files:**

- Create: `lib/src/tools/subagent_tools.dart`
- Test: `test/tools/subagent_tools_test.dart`

**Step 1: Write the failing test**

```dart
// test/tools/subagent_tools_test.dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:glue/src/tools/subagent_tools.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';

class _EchoLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final last = messages.lastWhere((m) => m.role == Role.user);
    yield TextDelta('Done: ${last.text}');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _TestFactory extends LlmClientFactory {
  @override
  LlmClient create({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
  }) => _EchoLlm();
}

void main() {
  late AgentManager manager;

  setUp(() {
    manager = AgentManager(
      tools: {},
      llmFactory: _TestFactory(),
      config: GlueConfig(anthropicApiKey: 'test'),
      systemPrompt: 'test',
    );
  });

  group('SpawnSubagentTool', () {
    test('has correct schema', () {
      final tool = SpawnSubagentTool(manager);
      expect(tool.name, 'spawn_subagent');
      expect(tool.parameters.any((p) => p.name == 'task'), isTrue);
    });

    test('executes and returns result', () async {
      final tool = SpawnSubagentTool(manager);
      final result = await tool.execute({'task': 'Write tests'});
      expect(result, contains('Done: Write tests'));
    });
  });

  group('SpawnParallelSubagentsTool', () {
    test('has correct schema', () {
      final tool = SpawnParallelSubagentsTool(manager);
      expect(tool.name, 'spawn_parallel_subagents');
      expect(tool.parameters.any((p) => p.name == 'tasks'), isTrue);
    });

    test('executes parallel tasks', () async {
      final tool = SpawnParallelSubagentsTool(manager);
      final result = await tool.execute({
        'tasks': ['Task A', 'Task B'],
      });
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final results = decoded['results'] as List;
      expect(results, hasLength(2));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/tools/subagent_tools_test.dart`
Expected: FAIL — file not found

**Step 3: Write implementation**

```dart
// lib/src/tools/subagent_tools.dart

import 'dart:convert';
import '../agent/agent_manager.dart';
import '../agent/tools.dart';
import '../config/glue_config.dart';

/// Tool that spawns a single subagent to perform a focused task.
class SpawnSubagentTool extends Tool {
  final AgentManager _manager;

  SpawnSubagentTool(this._manager);

  @override
  String get name => 'spawn_subagent';

  @override
  String get description =>
      'Spawn a subagent to perform a focused task independently. '
      'The subagent has its own conversation and can use tools. '
      'Use this for tasks that benefit from a fresh context.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'task',
          type: 'string',
          description: 'The task description for the subagent.',
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description: 'LLM provider: "anthropic" or "openai". Defaults to current.',
          required: false,
        ),
        ToolParameter(
          name: 'model',
          type: 'string',
          description: 'Model name override (e.g. "claude-4-haiku", "codex-2").',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final task = args['task'] as String;
    final providerStr = args['provider'] as String?;
    final model = args['model'] as String?;

    AgentProfile? profile;
    if (providerStr != null || model != null) {
      final provider = providerStr != null
          ? LlmProvider.values.firstWhere(
              (p) => p.name == providerStr,
              orElse: () => _manager.config.provider,
            )
          : _manager.config.provider;
      profile = AgentProfile(
        provider: provider,
        model: model ?? GlueConfig(provider: provider).model,
      );
    }

    return _manager.spawnSubagent(task: task, profile: profile);
  }
}

/// Tool that spawns multiple subagents in parallel.
class SpawnParallelSubagentsTool extends Tool {
  final AgentManager _manager;

  SpawnParallelSubagentsTool(this._manager);

  @override
  String get name => 'spawn_parallel_subagents';

  @override
  String get description =>
      'Spawn multiple subagents to work on independent tasks in parallel. '
      'Each subagent has its own conversation and tools. '
      'Results are returned as a JSON array.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'tasks',
          type: 'array',
          description: 'List of task descriptions, one per subagent.',
        ),
        ToolParameter(
          name: 'provider',
          type: 'string',
          description: 'LLM provider for all subagents.',
          required: false,
        ),
        ToolParameter(
          name: 'model',
          type: 'string',
          description: 'Model name for all subagents.',
          required: false,
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final tasks = (args['tasks'] as List).cast<String>();
    final providerStr = args['provider'] as String?;
    final model = args['model'] as String?;

    AgentProfile? profile;
    if (providerStr != null || model != null) {
      final provider = providerStr != null
          ? LlmProvider.values.firstWhere(
              (p) => p.name == providerStr,
              orElse: () => _manager.config.provider,
            )
          : _manager.config.provider;
      profile = AgentProfile(
        provider: provider,
        model: model ?? GlueConfig(provider: provider).model,
      );
    }

    final results = await _manager.spawnParallel(tasks: tasks, profile: profile);

    return jsonEncode({
      'results': [
        for (var i = 0; i < tasks.length; i++)
          {'task': tasks[i], 'output': results[i]},
      ],
    });
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/tools/subagent_tools_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/tools/subagent_tools.dart test/tools/subagent_tools_test.dart
git commit -m "feat: add spawn_subagent and spawn_parallel_subagents tools"
```

---

## Task 12: Wire Everything Together in App

**Files:**

- Modify: `lib/src/app.dart` — replace `_FakeLlmClient` with real provider
- Modify: `lib/glue.dart` — export new types
- Modify: `bin/` entry point (if exists)

**Step 1: Update App.create() factory**

Replace the `_FakeLlmClient` in `App.create()` with a `GlueConfig.load()` → `LlmClientFactory` → real provider client.

Key changes to `app.dart`:

- Import config, factory, prompts, subagent tools, agent manager
- In `App.create()`: load config, create real LLM client, create agent manager, register subagent tools
- Remove `_FakeLlmClient` class and related code
- Update status bar to show real model name from config

**Step 2: Update `App.create()`**

```dart
factory App.create({String? provider, String? model}) {
  final config = GlueConfig.load(cliProvider: provider, cliModel: model);
  config.validate();

  final terminal = Terminal();
  final layout = Layout(terminal);
  final editor = LineEditor();

  final systemPrompt = Prompts.build();
  final factory = LlmClientFactory();
  final llm = factory.createFromConfig(config, systemPrompt: systemPrompt);

  final tools = <String, Tool>{
    'read_file': ReadFileTool(),
    'write_file': WriteFileTool(),
    'bash': BashTool(),
    'grep': GrepTool(),
    'list_directory': ListDirectoryTool(),
  };

  final agent = AgentCore(llm: llm, tools: tools, modelName: config.model);

  // Create agent manager and register subagent tools.
  final manager = AgentManager(
    tools: tools,
    llmFactory: factory,
    config: config,
    systemPrompt: systemPrompt,
  );
  tools['spawn_subagent'] = SpawnSubagentTool(manager);
  tools['spawn_parallel_subagents'] = SpawnParallelSubagentsTool(manager);

  return App(
    terminal: terminal,
    layout: layout,
    editor: editor,
    agent: agent,
    modelName: config.model,
  );
}
```

**Step 3: Remove `_FakeLlmClient`**

Delete the entire `_FakeLlmClient` class and the `_Scenario` enum from `app.dart`.

**Step 4: Update exports in `lib/glue.dart`**

Add exports for new public types:

```dart
export 'src/config/glue_config.dart' show GlueConfig, LlmProvider, AgentProfile, ConfigError;
export 'src/llm/llm_factory.dart' show LlmClientFactory;
export 'src/agent/agent_runner.dart' show AgentRunner, ToolApprovalPolicy;
export 'src/agent/agent_manager.dart' show AgentManager;
export 'src/agent/prompts.dart' show Prompts;
```

**Step 5: Verify compilation**

Run: `dart analyze lib/`
Expected: No issues found

**Step 6: Commit**

```bash
git add lib/src/app.dart lib/glue.dart
git commit -m "feat: wire real LLM providers and subagent system into App"
```

---

## Task 13: End-to-End Smoke Test

**Files:**

- Create: `test/integration/smoke_test.dart`

**Step 1: Write the test**

```dart
// test/integration/smoke_test.dart
import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';

/// Fake LLM that exercises the full stack without network calls.
class _MockLlm implements LlmClient {
  int _calls = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _calls++;
    final last = messages.lastWhere((m) => m.role == Role.user);
    final text = last.text ?? '';

    if (_calls == 1 && text.contains('read')) {
      yield TextDelta('I\'ll read that file. ');
      yield ToolCallDelta(ToolCall(
        id: 'tc_$_calls',
        name: 'read_file',
        arguments: {'path': 'pubspec.yaml'},
      ));
      yield UsageInfo(inputTokens: 20, outputTokens: 10);
    } else {
      yield TextDelta('Done with the task.');
      yield UsageInfo(inputTokens: 10, outputTokens: 5);
    }
  }
}

class _MockFactory extends LlmClientFactory {
  @override
  LlmClient create({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
  }) => _MockLlm();
}

void main() {
  group('End-to-end smoke', () {
    test('AgentRunner completes a tool-using conversation', () async {
      final core = AgentCore(
        llm: _MockLlm(),
        tools: {'read_file': ReadFileTool()},
        modelName: 'test-model',
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('Please read pubspec.yaml');
      expect(result, contains('Done with the task'));
      expect(core.tokenCount, greaterThan(0));
    });

    test('AgentManager spawns parallel subagents', () async {
      final manager = AgentManager(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _MockFactory(),
        config: GlueConfig(anthropicApiKey: 'test-key'),
        systemPrompt: 'test',
      );

      final results = await manager.spawnParallel(
        tasks: ['Task 1', 'Task 2', 'Task 3'],
      );
      expect(results, hasLength(3));
      for (final r in results) {
        expect(r, contains('Done'));
      }
    });
  });
}
```

**Step 2: Run all tests**

Run: `dart test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add test/integration/smoke_test.dart
git commit -m "test: add end-to-end smoke tests for agent runner and manager"
```

---

## Summary

| Task | Component   | What                                                                    | Files                                                           |
| ---- | ----------- | ----------------------------------------------------------------------- | --------------------------------------------------------------- |
| 1    | SSE Decoder | Shared SSE byte-stream parser                                           | `lib/src/llm/sse.dart`                                          |
| 2    | Tool Schema | Per-provider tool encoding                                              | `lib/src/llm/tool_schema.dart`                                  |
| 3    | Messages    | System prompts + message mapping                                        | `lib/src/agent/prompts.dart`, `lib/src/llm/message_mapper.dart` |
| 4    | Anthropic   | Streaming client (claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5) | `lib/src/llm/anthropic_client.dart`                             |
| 5    | OpenAI      | Streaming client (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano, o3, o4-mini)     | `lib/src/llm/openai_client.dart`                                |
| 6    | Ollama      | NDJSON streaming client (any local model)                               | `lib/src/llm/ndjson.dart`, `lib/src/llm/ollama_client.dart`     |
| 7    | Config      | Multi-provider config system                                            | `lib/src/config/glue_config.dart`                               |
| 8    | Factory     | Client instantiation (3 providers)                                      | `lib/src/llm/llm_factory.dart`                                  |
| 9    | Runner      | Headless agent execution                                                | `lib/src/agent/agent_runner.dart`                               |
| 10   | Manager     | Subagent orchestration                                                  | `lib/src/agent/agent_manager.dart`                              |
| 11   | Tools       | Subagent tool calls                                                     | `lib/src/tools/subagent_tools.dart`                             |
| 12   | Wiring      | Connect everything in App                                               | `lib/src/app.dart`, `lib/glue.dart`                             |
| 13   | Smoke       | Integration tests                                                       | `test/integration/smoke_test.dart`                              |

### Key Architectural Decisions

1. **AgentCore is untouched** — all provider logic lives in the `llm/` layer
2. **3 providers, 2 streaming formats** — SSE (Anthropic/OpenAI) and NDJSON (Ollama)
3. **Manager pattern** — `AgentManager` spawns child `AgentCore`s (hierarchical orchestration from research)
4. **Architect/Editor ready** — profiles allow expensive models (claude-opus-4-6) for planning, cheap (gpt-4.1-nano, Ollama local) for execution
5. **Ollama for local testing** — no API key needed, any pulled model works
6. **Depth-limited recursion** — prevents infinite subagent nesting
7. **Subagents strip spawning tools** — no recursive self-spawning at tool level
8. **SSE decoder is shared** — Anthropic and OpenAI use same byte-to-event parser; Ollama uses separate NDJSON decoder
9. **Tool schema translation is external** — `Tool` class unchanged, encoders handle provider differences (Ollama reuses OpenAI format)
