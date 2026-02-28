# Multimodal Tool Results Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Send images (e.g. browser screenshots) as native image content blocks to LLM APIs instead of base64 text, fixing token count blowups.

**Architecture:** Introduce a `ContentPart` sealed class (text + image) used by `Message` and `ToolResult`. Each `MessageMapper` emits the correct provider-native format. Tools continue returning `Future<String>` but gain an optional `Future<List<ContentPart>>` override so only the web_browser tool needs to change initially.

**Tech Stack:** Dart 3.4+, Anthropic Messages API, OpenAI Chat Completions API, Ollama `/api/chat`

---

## Problem

The `web_browser` screenshot action returns a ~638KB base64 string as plain text in the tool result. This gets counted as ~738K text tokens by the API, exceeding the 200K context limit. All three providers have native image block formats that use efficient vision tokenization (~1,600 tokens for a 1568px image) instead.

## Provider Image Formats

### Anthropic (tool_result supports inline images)
```json
{
  "role": "user",
  "content": [{
    "type": "tool_result",
    "tool_use_id": "call-id",
    "content": [
      {"type": "text", "text": "Screenshot captured (12345 bytes)."},
      {"type": "image", "source": {
        "type": "base64",
        "media_type": "image/png",
        "data": "<RAW_BASE64>"
      }}
    ]
  }]
}
```

### OpenAI (tool results are text-only; images go in follow-up user message)
```json
// 1. Required tool result (text only)
{"role": "tool", "tool_call_id": "call-id", "content": "Screenshot captured (12345 bytes). See attached image."}
// 2. Follow-up user message with image
{"role": "user", "content": [
  {"type": "text", "text": "[Screenshot from web_browser tool]"},
  {"type": "image_url", "image_url": {"url": "data:image/png;base64,<BASE64>"}}
]}
```

### Ollama (images are a separate `images` array on messages)
```json
// 1. Required tool result (text only)
{"role": "tool", "content": "Screenshot captured (12345 bytes). See attached image.", "tool_name": "web_browser"}
// 2. Follow-up user message with images array
{"role": "user", "content": "[Screenshot from web_browser tool]", "images": ["<RAW_BASE64>"]}
```

---

### Task 1: Add `ContentPart` sealed class

**Files:**
- Create: `lib/src/agent/content_part.dart`
- Modify: `lib/glue.dart` (add export)
- Test: `test/content_part_test.dart`

**Step 1: Write the failing test**

```dart
// test/content_part_test.dart
import 'package:glue/src/agent/content_part.dart';
import 'package:test/test.dart';

void main() {
  group('ContentPart', () {
    test('TextPart stores text', () {
      final part = TextPart('hello');
      expect(part.text, 'hello');
    });

    test('ImagePart stores bytes and mimeType', () {
      final part = ImagePart(bytes: [1, 2, 3], mimeType: 'image/png');
      expect(part.bytes, [1, 2, 3]);
      expect(part.mimeType, 'image/png');
    });

    test('ContentPart.textOnly concatenates text parts', () {
      final parts = [
        TextPart('hello '),
        ImagePart(bytes: [1], mimeType: 'image/png'),
        TextPart('world'),
      ];
      expect(ContentPart.textOnly(parts), 'hello world');
    });

    test('ContentPart.hasImages detects image parts', () {
      expect(ContentPart.hasImages([TextPart('x')]), isFalse);
      expect(ContentPart.hasImages([ImagePart(bytes: [1], mimeType: 'image/png')]), isTrue);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/content_part_test.dart`
Expected: FAIL — file not found

**Step 3: Write minimal implementation**

```dart
// lib/src/agent/content_part.dart
import 'dart:convert';

/// A part of a message's content — either text or an image.
sealed class ContentPart {
  const ContentPart();

  /// Extracts only the text from a list of parts, ignoring images.
  static String textOnly(List<ContentPart> parts) {
    return parts.whereType<TextPart>().map((p) => p.text).join();
  }

  /// Returns true if the list contains any image parts.
  static bool hasImages(List<ContentPart> parts) {
    return parts.any((p) => p is ImagePart);
  }
}

/// A text content part.
class TextPart extends ContentPart {
  final String text;
  const TextPart(this.text);
}

/// An image content part (raw bytes + MIME type).
class ImagePart extends ContentPart {
  final List<int> bytes;
  final String mimeType;
  const ImagePart({required this.bytes, required this.mimeType});

  /// Returns the raw base64-encoded data (no data URI prefix).
  String toBase64() => base64Encode(bytes);
}
```

**Step 4: Add export to barrel file**

Add `export 'src/agent/content_part.dart';` to `lib/glue.dart`.

**Step 5: Run test to verify it passes**

Run: `dart test test/content_part_test.dart`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/src/agent/content_part.dart lib/glue.dart test/content_part_test.dart
git commit -m "feat: add ContentPart sealed class for multimodal content"
```

---

### Task 2: Update `ToolResult` and `Message` to support content parts

**Files:**
- Modify: `lib/src/agent/agent_core.dart`
- Test: `test/agent_core_test.dart` (extend existing tests)

**Step 1: Write the failing test**

```dart
// Add to test/agent_core_test.dart or a new test file
test('ToolResult with content parts', () {
  final result = ToolResult(
    callId: 'c1',
    content: 'text fallback',
    contentParts: [
      TextPart('Screenshot captured.'),
      ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
    ],
  );
  expect(result.contentParts, isNotNull);
  expect(result.contentParts!.length, 2);
  expect(result.content, 'text fallback');
});

test('Message.toolResult with content parts', () {
  final msg = Message.toolResult(
    callId: 'c1',
    content: 'text fallback',
    toolName: 'web_browser',
    contentParts: [
      TextPart('Screenshot captured.'),
      ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
    ],
  );
  expect(msg.contentParts, isNotNull);
  expect(msg.contentParts!.length, 2);
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/agent_core_test.dart`
Expected: FAIL — `contentParts` not a recognized parameter

**Step 3: Update `ToolResult` in `agent_core.dart`**

Add an optional `contentParts` field to `ToolResult`:

```dart
class ToolResult {
  final String callId;
  final String content;
  final List<ContentPart>? contentParts;
  final bool success;

  ToolResult({
    required this.callId,
    required this.content,
    this.contentParts,
    this.success = true,
  });

  factory ToolResult.denied(String callId) => ToolResult(
        callId: callId,
        content: 'User denied tool execution',
        success: false,
      );
}
```

**Step 4: Update `Message` in `agent_core.dart`**

Add an optional `contentParts` field to `Message`:

```dart
class Message {
  final Role role;
  final String? text;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final List<ContentPart>? contentParts;

  const Message._({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.contentParts,
  });

  // ... existing factories unchanged ...

  factory Message.toolResult({
    required String callId,
    required String content,
    String? toolName,
    List<ContentPart>? contentParts,
  }) =>
      Message._(
          role: Role.toolResult,
          text: content,
          toolCallId: callId,
          toolName: toolName,
          contentParts: contentParts);
}
```

**Step 5: Update `AgentCore.run()` to pass content parts through**

In the tool results loop (~line 274), pass `contentParts`:

```dart
_conversation.add(Message.toolResult(
  callId: toolCalls[i].id,
  content: results[i].content,
  toolName: toolCalls[i].name,
  contentParts: results[i].contentParts,
));
```

**Step 6: Run tests**

Run: `dart test`
Expected: All tests PASS (existing behavior unchanged, new fields are optional)

**Step 7: Commit**

```bash
git add lib/src/agent/agent_core.dart test/agent_core_test.dart
git commit -m "feat: add contentParts to ToolResult and Message"
```

---

### Task 3: Update `AnthropicMessageMapper` for image support

**Files:**
- Modify: `lib/src/llm/message_mapper.dart`
- Test: `test/message_mapper_test.dart`

**Step 1: Write the failing test**

```dart
test('Anthropic mapper emits image blocks in tool_result', () {
  final mapper = AnthropicMessageMapper();
  final messages = [
    Message.user('hi'),
    Message.assistant(toolCalls: [
      ToolCall(id: 'tc1', name: 'web_browser', arguments: {}),
    ]),
    Message.toolResult(
      callId: 'tc1',
      content: 'Screenshot captured.',
      toolName: 'web_browser',
      contentParts: [
        TextPart('Screenshot captured.'),
        ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
      ],
    ),
  ];
  final result = mapper.mapMessages(messages, systemPrompt: '');
  final toolResultMsg = result.messages[2];
  final toolResultContent = toolResultMsg['content'][0]['content'];
  expect(toolResultContent, isList);
  expect(toolResultContent.length, 2);
  expect(toolResultContent[0]['type'], 'text');
  expect(toolResultContent[1]['type'], 'image');
  expect(toolResultContent[1]['source']['type'], 'base64');
  expect(toolResultContent[1]['source']['media_type'], 'image/png');
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/message_mapper_test.dart`
Expected: FAIL — tool_result content is still a flat string

**Step 3: Update `AnthropicMessageMapper`**

In the `Role.toolResult` case, check for `contentParts`:

```dart
case Role.toolResult:
  final dynamic content;
  if (msg.contentParts != null && ContentPart.hasImages(msg.contentParts!)) {
    content = [
      for (final part in msg.contentParts!)
        if (part is TextPart)
          {'type': 'text', 'text': part.text}
        else if (part is ImagePart)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': part.mimeType,
              'data': part.toBase64(),
            }
          }
    ];
  } else {
    content = msg.text ?? '';
  }
  mapped.add({
    'role': 'user',
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': msg.toolCallId,
        'content': content,
      }
    ],
  });
```

**Step 4: Run tests**

Run: `dart test test/message_mapper_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/llm/message_mapper.dart test/message_mapper_test.dart
git commit -m "feat: Anthropic mapper emits native image blocks in tool_result"
```

---

### Task 4: Update `OpenAiMessageMapper` for image support

**Files:**
- Modify: `lib/src/llm/message_mapper.dart`
- Test: `test/message_mapper_test.dart`

**Step 1: Write the failing test**

```dart
test('OpenAI mapper emits text-only tool result + follow-up user image message', () {
  final mapper = OpenAiMessageMapper();
  final messages = [
    Message.user('hi'),
    Message.assistant(toolCalls: [
      ToolCall(id: 'tc1', name: 'web_browser', arguments: {}),
    ]),
    Message.toolResult(
      callId: 'tc1',
      content: 'Screenshot captured.',
      toolName: 'web_browser',
      contentParts: [
        TextPart('Screenshot captured.'),
        ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
      ],
    ),
  ];
  final result = mapper.mapMessages(messages, systemPrompt: '');
  // system + user + assistant + tool_result + follow-up user image = 5
  expect(result.messages.length, 5);
  // Tool result is text-only
  final toolMsg = result.messages[3];
  expect(toolMsg['role'], 'tool');
  expect(toolMsg['content'], 'Screenshot captured.');
  // Follow-up user message has image
  final imageMsg = result.messages[4];
  expect(imageMsg['role'], 'user');
  expect(imageMsg['content'], isList);
  final parts = imageMsg['content'] as List;
  expect(parts[0]['type'], 'text');
  expect(parts[1]['type'], 'image_url');
  expect((parts[1]['image_url']['url'] as String).startsWith('data:image/png;base64,'), isTrue);
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/message_mapper_test.dart`
Expected: FAIL

**Step 3: Update `OpenAiMessageMapper`**

In the `Role.toolResult` case, emit the text-only tool message, then if images are present, also emit a follow-up user message:

```dart
case Role.toolResult:
  // Tool result is always text-only for OpenAI
  mapped.add({
    'role': 'tool',
    'tool_call_id': msg.toolCallId,
    'content': ContentPart.textOnly(msg.contentParts ?? []) .isEmpty
        ? (msg.text ?? '')
        : ContentPart.textOnly(msg.contentParts!),
  });
  // If images present, add follow-up user message
  if (msg.contentParts != null && ContentPart.hasImages(msg.contentParts!)) {
    final imageParts = msg.contentParts!.whereType<ImagePart>();
    mapped.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': '[Screenshot from ${msg.toolName ?? "tool"}]'},
        for (final img in imageParts)
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:${img.mimeType};base64,${img.toBase64()}',
            }
          }
      ],
    });
  }
```

**Step 4: Run tests**

Run: `dart test test/message_mapper_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/llm/message_mapper.dart test/message_mapper_test.dart
git commit -m "feat: OpenAI mapper emits follow-up user message for tool images"
```

---

### Task 5: Update `OllamaClient` message mapping for image support

**Files:**
- Modify: `lib/src/llm/ollama_client.dart`
- Test: `test/ollama_client_test.dart`

**Step 1: Write the failing test**

```dart
test('Ollama mapping emits text-only tool result + follow-up user with images array', () {
  // Test the message mapping logic within OllamaClient
  // This may require extracting the mapping or testing via integration
  // At minimum, verify the mapped messages structure
});
```

**Step 2: Update `OllamaClient` message mapping**

In the `Role.toolResult` case, emit text-only tool message, then follow-up user message with `images` array:

```dart
case Role.toolResult:
  mappedMessages.add({
    'role': 'tool',
    'content': ContentPart.textOnly(msg.contentParts ?? []).isEmpty
        ? (msg.text ?? '')
        : ContentPart.textOnly(msg.contentParts!),
    'tool_name': msg.toolName ?? '',
  });
  if (msg.contentParts != null && ContentPart.hasImages(msg.contentParts!)) {
    final images = msg.contentParts!
        .whereType<ImagePart>()
        .map((img) => img.toBase64())
        .toList();
    mappedMessages.add({
      'role': 'user',
      'content': '[Screenshot from ${msg.toolName ?? "tool"}]',
      'images': images,
    });
  }
```

**Step 3: Run tests**

Run: `dart test`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/src/llm/ollama_client.dart test/ollama_client_test.dart
git commit -m "feat: Ollama mapping emits follow-up user message with images array"
```

---

### Task 6: Update `web_browser` screenshot to return `ContentPart`s

**Files:**
- Modify: `lib/src/tools/web_browser_tool.dart`
- Modify: `lib/src/agent/tools.dart` (or wherever tool execution is wired)
- Test: `test/web_browser_tool_test.dart`

**Step 1: Add `executeWithParts` to `Tool` base class**

In `lib/src/agent/tools.dart`, add an optional override that tools can implement to return structured content:

```dart
abstract class Tool {
  // ... existing members ...

  /// Override to return structured content parts (text + images).
  /// Default implementation wraps [execute] result in a single [TextPart].
  Future<List<ContentPart>> executeWithParts(Map<String, dynamic> args) async {
    final text = await execute(args);
    return [TextPart(text)];
  }
}
```

**Step 2: Update `AgentCore` and `AgentRunner` to use `executeWithParts`**

Where tool execution happens, call `executeWithParts` instead of `execute`, and populate `ToolResult.contentParts`:

```dart
final parts = await tool.executeWithParts(args);
final textContent = ContentPart.textOnly(parts);
final result = ToolResult(
  callId: callId,
  content: textContent,
  contentParts: ContentPart.hasImages(parts) ? parts : null,
);
```

**Step 3: Override `executeWithParts` in `WebBrowserTool._screenshot`**

Update the screenshot action to return image bytes as an `ImagePart`:

```dart
// In WebBrowserTool, override executeWithParts for screenshot action
@override
Future<List<ContentPart>> executeWithParts(Map<String, dynamic> args) async {
  final action = args['action'] as String?;
  if (action == 'screenshot') {
    return _screenshotParts(args);
  }
  // All other actions return text
  final text = await execute(args);
  return [TextPart(text)];
}

Future<List<ContentPart>> _screenshotParts(Map<String, dynamic> args) async {
  final page = await _ensurePage();
  final selector = args['selector'] as String?;

  List<int> bytes;
  if (selector != null && selector.isNotEmpty) {
    final element = await page.$(selector);
    bytes = await element.screenshot();
  } else {
    bytes = await page.screenshot();
  }

  return [
    TextPart('Screenshot captured (${bytes.length} bytes).'),
    ImagePart(bytes: bytes, mimeType: 'image/png'),
  ];
}
```

**Step 4: Keep `_screenshot` as fallback for `execute()`**

The existing `_screenshot` method stays unchanged so `execute()` still works for non-image-aware callers.

**Step 5: Run tests**

Run: `dart test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add lib/src/agent/tools.dart lib/src/tools/web_browser_tool.dart lib/src/agent/agent_core.dart lib/src/agent/agent_runner.dart
git commit -m "feat: web_browser screenshot returns native ImagePart content"
```

---

### Task 7: Wire `executeWithParts` in `AgentRunner` (headless mode)

**Files:**
- Modify: `lib/src/agent/agent_runner.dart`
- Test: `test/agent_runner_test.dart`

**Step 1: Update `AgentRunner` tool execution**

Where the runner calls `tool.execute(args)`, change to `tool.executeWithParts(args)` and build the `ToolResult` with `contentParts`:

```dart
final parts = await tool.executeWithParts(tc.arguments);
final textContent = ContentPart.textOnly(parts);
core.completeToolCall(ToolResult(
  callId: tc.id,
  content: textContent,
  contentParts: ContentPart.hasImages(parts) ? parts : null,
));
```

**Step 2: Run tests**

Run: `dart test`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/src/agent/agent_runner.dart
git commit -m "feat: AgentRunner uses executeWithParts for multimodal tool results"
```

---

### Task 8: Wire in `App` (TUI mode tool execution)

**Files:**
- Modify: `lib/src/app.dart` (or wherever the TUI calls tool.execute)

**Step 1: Find where `App` executes tools**

Look for where the TUI handles `AgentToolCall` events and calls `tool.execute()`. Update to use `executeWithParts()` and pass `contentParts` through to `ToolResult`.

**Step 2: Update to use `executeWithParts`**

Same pattern as AgentRunner:

```dart
final parts = await tool.executeWithParts(tc.arguments);
final textContent = ContentPart.textOnly(parts);
core.completeToolCall(ToolResult(
  callId: tc.id,
  content: textContent,
  contentParts: ContentPart.hasImages(parts) ? parts : null,
));
```

**Step 3: Run tests**

Run: `dart test`
Expected: PASS

**Step 4: Manual test**

Run: `dart run bin/glue.dart`
Navigate to a website, take a screenshot. Verify no token overflow error.

**Step 5: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: TUI app uses executeWithParts for multimodal tool results"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `lib/src/agent/content_part.dart` | **New** — `ContentPart`, `TextPart`, `ImagePart` sealed classes |
| `lib/src/agent/agent_core.dart` | Add `contentParts` to `ToolResult` and `Message`, pass through in agent loop |
| `lib/src/agent/tools.dart` | Add `executeWithParts()` default method to `Tool` base class |
| `lib/src/llm/message_mapper.dart` | Anthropic: inline image blocks in `tool_result.content`. OpenAI: text-only tool result + follow-up user image message |
| `lib/src/llm/ollama_client.dart` | Text-only tool result + follow-up user message with `images` array |
| `lib/src/tools/web_browser_tool.dart` | Override `executeWithParts` for screenshot action, return `ImagePart` |
| `lib/src/agent/agent_runner.dart` | Use `executeWithParts` instead of `execute` |
| `lib/src/app.dart` | Use `executeWithParts` instead of `execute` |

## Key Design Decisions

1. **Additive, not breaking** — `contentParts` is optional on both `ToolResult` and `Message`. All existing tools keep working via the default `executeWithParts` which wraps `execute()` in a `[TextPart(...)]`.

2. **Provider-specific image handling** — Anthropic natively supports images in `tool_result` content blocks. OpenAI and Ollama don't, so we emit a text-only tool result + a follow-up `user` message with the image. This is a well-known pattern.

3. **No tool signature change** — Existing tools don't need modification. Only tools that produce images (currently just `web_browser`) override `executeWithParts`.

4. **Token savings** — A 1568px screenshot goes from ~738K text tokens to ~1,600 vision tokens. This is a ~460x reduction.
