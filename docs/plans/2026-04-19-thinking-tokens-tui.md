# Thinking Tokens in the TUI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface streaming reasoning/"thinking" traces from reasoning-capable models (Claude extended thinking, OpenAI gpt-5/o-series, DeepSeek R1 via Ollama) in the Glue TUI as a distinct, visually muted block inline with the conversation.

**Architecture:** Add a `ThinkingDelta` variant to the existing `LlmChunk` sealed union, flow it through `AgentCore` as an `AgentThinkingDelta` event, render it in a dedicated conversation block kind using dim/italic ANSI styling. Parser changes are additive and provider-specific (Anthropic `thinking_delta`, OpenAI `delta.reasoning`, Ollama `message.thinking`). Enablement on the request side (Anthropic's `thinking: {budget_tokens}`, OpenAI's `reasoning_effort`) is phase 2 — phase 1 only surfaces what providers already emit.

**Tech Stack:** Dart, existing SSE/NDJSON parsers, existing sealed `LlmChunk`/`AgentEvent` unions, existing `BlockRenderer` + 60fps coalesced render loop.

---

## Context

Reasoning-capable models (Claude 4.x with extended thinking, GPT-5/o-series, DeepSeek R1, QwQ, etc.) emit a structured "thinking" stream alongside or before their final answer. Today Glue silently drops these tokens at every provider parser — `anthropic_client.dart:120-124` ignores `thinking_delta`, `openai_client.dart:128-131` ignores `delta.reasoning`, `ollama_client.dart:134-140` ignores `message.thinking`. The model catalog already tags these models with the `reasoning` capability (`model_catalog.dart:21`), so the UX gap is visible.

Users want to see the reasoning trace for three reasons: debugging prompts, trusting tool choices (especially destructive ones), and general transparency. Showing it dim + italic inline keeps the signal (final answer stands out) while making the reasoning legible if the user cares.

## Goals

- Stream thinking tokens to the TUI in real time as a visually distinct block.
- Preserve correct block ordering: thinking → (optional) tool calls → final text → next round.
- Add zero overhead for models that don't emit thinking (parsers skip unknown fields).
- Round-trip thinking metadata into the conversation store so session resume shows it.
- Runtime toggle to hide/show thinking (keybinding + config).

## Non-Goals (explicit)

- **Enabling** thinking on providers that require opt-in (Anthropic extended thinking, OpenAI `reasoning_effort`) — tracked in Phase 2 below, out of scope for this plan's task list.
- Redacted-thinking handling for Anthropic (signed, encrypted blocks) — phase 2.
- Thinking token counting in `UsageInfo` (separate billing concern) — phase 2.
- ACP/WebUI surfaces — `docs/plans/2026-02-27-acp-webui.md` already references `agent_thought_chunk`; this plan keeps the TUI path clean so ACP can mirror it later.

## File Structure

**Modify:**

- `cli/lib/src/agent/agent_core.dart` — add `ThinkingDelta` to `LlmChunk`, add `AgentThinkingDelta` to `AgentEvent`, route in `run()` switch.
- `cli/lib/src/agent/agent_runner.dart` — noop-handle `AgentThinkingDelta` (headless discards).
- `cli/lib/src/llm/anthropic_client.dart` — parse `content_block_start` with `type: thinking` and `content_block_delta` with `delta.type: thinking_delta`.
- `cli/lib/src/llm/openai_client.dart` — parse `delta.reasoning` and `delta.reasoning_content` fallbacks.
- `cli/lib/src/llm/ollama_client.dart` — parse `message.thinking`.
- `cli/lib/src/app/models.dart` (or wherever `_EntryKind`/`_ConversationEntry` lives — see `render_pipeline.dart:49-86` imports) — add `_EntryKind.thinking` and `_ConversationEntry.thinking(text)`.
- `cli/lib/src/app.dart` — add `_streamingThinking` buffer alongside `_streamingText`.
- `cli/lib/src/app/agent_orchestration.dart` — handle `AgentThinkingDelta`, flush thinking on transition to text/tool/done.
- `cli/lib/src/app/render_pipeline.dart` — render `_streamingThinking` in output zone, render `_EntryKind.thinking` blocks.
- `cli/lib/src/rendering/block_renderer.dart` — add `renderThinking(String text)`.
- `cli/lib/src/app/terminal_event_router.dart` — add keybinding for toggle (proposed: `Ctrl+T`).
- `cli/lib/src/config/glue_config.dart` — add `showReasoning` bool (default `true`), resolve from CLI arg → env `GLUE_SHOW_REASONING` → config file.

**Create tests:**

- `cli/test/llm/anthropic_client_test.dart` — add thinking-delta case (modify existing file).
- `cli/test/llm/openai_client_test.dart` — add reasoning case (modify existing file).
- `cli/test/llm/ollama_client_test.dart` — add thinking case (modify existing file).
- `cli/test/agent_core_test.dart` — add chunk→event routing case.
- `cli/test/block_renderer_test.dart` — add `renderThinking` case.
- `cli/test/app/` — (optional) integration test for flush ordering.

## Wire Format Reference

Keep this in front of you when implementing parsers — no guessing, these are the shapes the providers emit today.

### Anthropic (SSE, `content_block_*` events)

```json
{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}
{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me consider..."}}
{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" the options."}}
{"type":"content_block_stop","index":0}
{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"The answer is..."}}
```

Anthropic also emits `redacted_thinking` blocks (base64 signed payloads for safety-sensitive reasoning). **Ignore these in phase 1** — they carry no human-readable content. The relevant hook is `anthropic_client.dart:115-124` (the `content_block_delta` switch).

### OpenAI Chat Completions (SSE, `choices[0].delta`)

```json
{"choices":[{"delta":{"reasoning":"Thinking about the constraints..."}}]}
{"choices":[{"delta":{"reasoning":" tool choice should be X"}}]}
{"choices":[{"delta":{"content":"Here's the answer..."}}]}
```

Some gateways/proxies use `reasoning_content` instead of `reasoning` (DeepSeek-style). Handle both. The hook is `openai_client.dart:128-153` (the delta-dispatch block).

### Ollama (NDJSON)

```json
{"model":"deepseek-r1","message":{"role":"assistant","thinking":"Step 1: understand..."},"done":false}
{"model":"deepseek-r1","message":{"role":"assistant","content":"Here's the answer..."},"done":false}
```

Field is `message.thinking`. Hook is `ollama_client.dart:134-140`.

---

## Task Breakdown

### Task 1: Add `ThinkingDelta` to `LlmChunk`

**Files:**

- Modify: `cli/lib/src/agent/agent_core.dart:60-95`

- [ ] **Step 1: Write the failing test**

Open `cli/test/agent_core_test.dart` and add:

```dart
test('ThinkingDelta is a distinct LlmChunk variant', () {
  const chunk = ThinkingDelta('reasoning...');
  expect(chunk, isA<LlmChunk>());
  expect(chunk.text, 'reasoning...');
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/agent_core_test.dart --name "ThinkingDelta is a distinct"`
Expected: FAIL — "Undefined name 'ThinkingDelta'".

- [ ] **Step 3: Implement**

Add to `cli/lib/src/agent/agent_core.dart` immediately after the `TextDelta` class (~line 68):

```dart
/// A delta of streaming reasoning / "thinking" content. Distinct from
/// [TextDelta] so renderers can style it as non-final, deliberative output.
/// Not every provider emits this — only reasoning-capable models.
class ThinkingDelta extends LlmChunk {
  final String text;
  ThinkingDelta(this.text);
}
```

- [ ] **Step 4: Verify GREEN**

Run: `dart test test/agent_core_test.dart --name "ThinkingDelta is a distinct"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/agent/agent_core.dart cli/test/agent_core_test.dart
git commit -m "feat(agent): add ThinkingDelta LlmChunk variant"
```

---

### Task 2: Route `ThinkingDelta` → `AgentThinkingDelta`

**Files:**

- Modify: `cli/lib/src/agent/agent_core.dart:139-174` (AgentEvent union)
- Modify: `cli/lib/src/agent/agent_core.dart:235-254` (run() switch)
- Modify: `cli/lib/src/agent/agent_runner.dart:42-65` (headless switch)

- [ ] **Step 1: Write failing test**

In `cli/test/agent_core_test.dart`:

```dart
test('AgentCore forwards ThinkingDelta as AgentThinkingDelta', () async {
  final llm = _StubLlm(chunks: [ThinkingDelta('reasoning...'), TextDelta('answer')]);
  final core = AgentCore(llm: llm, tools: const {});
  final events = await core.run('hi').toList();
  expect(
    events.whereType<AgentThinkingDelta>().map((e) => e.delta),
    ['reasoning...'],
  );
  expect(
    events.whereType<AgentTextDelta>().map((e) => e.delta),
    ['answer'],
  );
});
```

(`_StubLlm` exists in the file already — if not, copy the pattern from the EchoLlm stub in `test/tools/subagent_tools_test.dart`.)

- [ ] **Step 2: Verify RED**

Run: `dart test test/agent_core_test.dart --name "forwards ThinkingDelta"`
Expected: FAIL — "Undefined name 'AgentThinkingDelta'".

- [ ] **Step 3: Add AgentThinkingDelta**

In `cli/lib/src/agent/agent_core.dart` after `AgentTextDelta` (~line 143):

```dart
/// A delta of streaming reasoning/thinking content forwarded to the UI.
/// Renderers should style this distinctly from [AgentTextDelta].
class AgentThinkingDelta extends AgentEvent {
  final String delta;
  AgentThinkingDelta(this.delta);
}
```

- [ ] **Step 4: Route in `run()`**

In the `switch (chunk)` block in `AgentCore.run()` (~line 240), add a case above `TextDelta`:

```dart
case ThinkingDelta(:final text):
  yield AgentThinkingDelta(text);
```

Do **not** append to `assistantText` — thinking does not go into the assistant message that gets sent back to the model on the next turn (that would pollute context and, for Anthropic, is explicitly forbidden without the right block structure).

- [ ] **Step 5: Handle in AgentRunner**

In `cli/lib/src/agent/agent_runner.dart` runToCompletion switch (~line 50), add a no-op case:

```dart
case AgentThinkingDelta():
  break; // headless mode discards reasoning traces
```

- [ ] **Step 6: Verify GREEN + existing tests**

Run: `dart test test/agent_core_test.dart test/agent`
Expected: PASS (all).

- [ ] **Step 7: Commit**

```bash
git add cli/lib/src/agent cli/test/agent_core_test.dart
git commit -m "feat(agent): forward ThinkingDelta as AgentThinkingDelta event"
```

---

### Task 3: Anthropic parser — emit `ThinkingDelta`

**Files:**

- Modify: `cli/lib/src/llm/anthropic_client.dart:115-124`
- Modify: `cli/test/llm/anthropic_client_test.dart`

- [ ] **Step 1: Write failing test**

Add to `cli/test/llm/anthropic_client_test.dart`:

```dart
test('emits ThinkingDelta for thinking_delta events', () async {
  final events = Stream.fromIterable([
    {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'thinking'}},
    {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': 'reasoning...'}},
    {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': ' more.'}},
    {'type': 'content_block_stop', 'index': 0},
    {'type': 'content_block_start', 'index': 1, 'content_block': {'type': 'text'}},
    {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'text_delta', 'text': 'answer'}},
  ]);
  final chunks = await AnthropicClient.parseStreamEvents(events).toList();
  final thinking = chunks.whereType<ThinkingDelta>().map((c) => c.text).toList();
  final text = chunks.whereType<TextDelta>().map((c) => c.text).toList();
  expect(thinking, ['reasoning...', ' more.']);
  expect(text, ['answer']);
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/llm/anthropic_client_test.dart --name "thinking_delta"`
Expected: FAIL — thinking list empty.

- [ ] **Step 3: Implement**

In `cli/lib/src/llm/anthropic_client.dart`, inside the `content_block_delta` branch (~line 115-124), extend the switch on `deltaType`:

```dart
} else if (deltaType == 'thinking_delta') {
  final thinking = delta['thinking'];
  if (thinking is String && thinking.isNotEmpty) {
    yield ThinkingDelta(thinking);
  }
}
```

(Do not handle `redacted_thinking` — it carries a base64 `data` field, not human-readable content.)

- [ ] **Step 4: Verify GREEN**

Run: `dart test test/llm/anthropic_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/llm/anthropic_client.dart cli/test/llm/anthropic_client_test.dart
git commit -m "feat(llm/anthropic): emit ThinkingDelta for extended-thinking blocks"
```

---

### Task 4: OpenAI parser — emit `ThinkingDelta`

**Files:**

- Modify: `cli/lib/src/llm/openai_client.dart:128-153`
- Modify: `cli/test/llm/openai_client_test.dart`

- [ ] **Step 1: Write failing test**

Add two cases — one for `reasoning`, one for `reasoning_content` (gateway variant):

```dart
test('emits ThinkingDelta for delta.reasoning', () async {
  final events = Stream.fromIterable([
    {'choices': [{'delta': {'reasoning': 'thinking...'}}]},
    {'choices': [{'delta': {'reasoning': ' more.'}}]},
    {'choices': [{'delta': {'content': 'answer'}}]},
  ]);
  final chunks = await OpenAiClient.parseStreamEvents(events).toList();
  expect(
    chunks.whereType<ThinkingDelta>().map((c) => c.text),
    ['thinking...', ' more.'],
  );
  expect(chunks.whereType<TextDelta>().map((c) => c.text), ['answer']);
});

test('emits ThinkingDelta for delta.reasoning_content (proxy variant)', () async {
  final events = Stream.fromIterable([
    {'choices': [{'delta': {'reasoning_content': 'hmm'}}]},
  ]);
  final chunks = await OpenAiClient.parseStreamEvents(events).toList();
  expect(chunks.whereType<ThinkingDelta>().map((c) => c.text), ['hmm']);
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/llm/openai_client_test.dart --name "reasoning"`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `cli/lib/src/llm/openai_client.dart`, inside the delta handling block (~line 128), before the `content` check, add:

```dart
final reasoning = delta['reasoning'] ?? delta['reasoning_content'];
if (reasoning is String && reasoning.isNotEmpty) {
  yield ThinkingDelta(reasoning);
}
```

Keep the existing `content` handling intact — a single delta object may contain both.

- [ ] **Step 4: Verify GREEN**

Run: `dart test test/llm/openai_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/llm/openai_client.dart cli/test/llm/openai_client_test.dart
git commit -m "feat(llm/openai): emit ThinkingDelta for reasoning deltas"
```

---

### Task 5: Ollama parser — emit `ThinkingDelta`

**Files:**

- Modify: `cli/lib/src/llm/ollama_client.dart:134-140`
- Modify: `cli/test/llm/ollama_client_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('emits ThinkingDelta for message.thinking', () async {
  final events = Stream.fromIterable([
    {'message': {'role': 'assistant', 'thinking': 'step 1'}, 'done': false},
    {'message': {'role': 'assistant', 'thinking': ' step 2'}, 'done': false},
    {'message': {'role': 'assistant', 'content': 'done'}, 'done': true},
  ]);
  final chunks = await OllamaClient.parseStreamEvents(events).toList();
  expect(
    chunks.whereType<ThinkingDelta>().map((c) => c.text),
    ['step 1', ' step 2'],
  );
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/llm/ollama_client_test.dart --name "thinking"`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `cli/lib/src/llm/ollama_client.dart` (~line 134), before the existing `content` check inside the message handling:

```dart
final thinking = message['thinking'];
if (thinking is String && thinking.isNotEmpty) {
  yield ThinkingDelta(thinking);
}
```

- [ ] **Step 4: Verify GREEN**

Run: `dart test test/llm/ollama_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/llm/ollama_client.dart cli/test/llm/ollama_client_test.dart
git commit -m "feat(llm/ollama): emit ThinkingDelta for message.thinking"
```

---

### Task 6: `renderThinking` on BlockRenderer

**Files:**

- Modify: `cli/lib/src/rendering/block_renderer.dart`
- Modify: `cli/test/block_renderer_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('renderThinking renders with dim+italic style and distinct header', () {
  final renderer = BlockRenderer(width: 80);
  final output = renderer.renderThinking('considering options...');
  expect(output, contains('Thinking'));
  expect(output, contains('\x1b[2m'), reason: 'dim ANSI');
  expect(output, contains('\x1b[3m'), reason: 'italic ANSI');
  expect(output, contains('considering options'));
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/block_renderer_test.dart --name "renderThinking"`
Expected: FAIL — method doesn't exist.

- [ ] **Step 3: Implement**

In `cli/lib/src/rendering/block_renderer.dart`, near `renderAssistant`:

```dart
String renderThinking(String text) {
  final header = ' ${'▸ Thinking'.styled.dim.gray}';
  final md = MarkdownRenderer(_inner - 2);
  final body = md.render(text);
  final indented = body
      .split('\n')
      .map((l) => '   ${l.styled.dim.italic}')
      .join('\n');
  return '$header\n$indented';
}
```

Rationale for style choice: dim + italic on the body reads as "aside/annotation" without being hard to read; gray header with `▸` visually subordinates the block to user/assistant headers (which use `❯`/`◆`).

- [ ] **Step 4: Verify GREEN**

Run: `dart test test/block_renderer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/rendering/block_renderer.dart cli/test/block_renderer_test.dart
git commit -m "feat(rendering): add renderThinking for reasoning traces"
```

---

### Task 7: Conversation entry kind + App buffer

**Files:**

- Modify: `cli/lib/src/app/models.dart` (or the file that defines `_EntryKind` — search for `enum _EntryKind`)
- Modify: `cli/lib/src/app.dart` (add `_streamingThinking` field)

- [ ] **Step 1: Add entry kind**

Locate the enum (likely `cli/lib/src/app/models.dart`). Add:

```dart
enum _EntryKind {
  user,
  assistant,
  thinking,        // ← new
  toolCallRef,
  toolResult,
  error,
  system,
  // ... existing variants preserved
}
```

Add a factory on `_ConversationEntry`:

```dart
factory _ConversationEntry.thinking(String text) =>
    _ConversationEntry._(kind: _EntryKind.thinking, text: text);
```

- [ ] **Step 2: Add App buffer**

In `cli/lib/src/app.dart`, near `_streamingText`:

```dart
String _streamingThinking = '';
```

- [ ] **Step 3: Commit (wiring only, no behavior change yet)**

```bash
git add cli/lib/src/app
git commit -m "refactor(app): add thinking entry kind and streaming buffer"
```

---

### Task 8: Handle `AgentThinkingDelta` in orchestration

**Files:**

- Modify: `cli/lib/src/app/agent_orchestration.dart:56-193`

- [ ] **Step 1: Add case in `_handleAgentEventImpl` switch**

```dart
case AgentThinkingDelta(:final delta):
  if (!app._config.showReasoning) {
    return; // respect toggle, don't even buffer
  }
  app._streamingThinking += delta;
  app._render();
```

- [ ] **Step 2: Flush thinking on transitions**

Add a helper at the top of the file or inline:

```dart
void _flushThinking(App app) {
  if (app._streamingThinking.isNotEmpty) {
    app._blocks.add(_ConversationEntry.thinking(app._streamingThinking));
    app._streamingThinking = '';
  }
}
```

Call `_flushThinking(app)` at the top of:

- `case AgentTextDelta` (before buffering text — thinking has ended, assistant has started)
- `case AgentToolCallPending` (alongside the existing assistant-text flush)
- `case AgentDone` (in case thinking was the last thing streamed)

- [ ] **Step 3: Commit**

```bash
git add cli/lib/src/app/agent_orchestration.dart
git commit -m "feat(app): flush thinking buffer on transitions, respect toggle"
```

---

### Task 9: Render streaming + finalized thinking blocks

**Files:**

- Modify: `cli/lib/src/app/render_pipeline.dart:49-86`

- [ ] **Step 1: Render finalized blocks**

In the block iteration (~line 49-86), add a case:

```dart
case _EntryKind.thinking:
  outputLines.addAll(renderer.renderThinking(entry.text).split('\n'));
```

- [ ] **Step 2: Render streaming thinking buffer**

Near the `_streamingText` render (~line 83-86), before it:

```dart
if (app._streamingThinking.isNotEmpty) {
  outputLines
      .addAll(renderer.renderThinking(app._streamingThinking).split('\n'));
}
```

Rationale for ordering: thinking appears _before_ streaming assistant text in the output buffer so that when both are active (rare — thinking has usually finished before text arrives, but Anthropic interleaves text and thinking in edge cases), the user sees the reasoning "above" the conclusion.

- [ ] **Step 3: Commit**

```bash
git add cli/lib/src/app/render_pipeline.dart
git commit -m "feat(app): render streaming and finalized thinking blocks"
```

---

### Task 10: Config + runtime toggle

**Files:**

- Modify: `cli/lib/src/config/glue_config.dart:61-530`
- Modify: `cli/lib/src/app/terminal_event_router.dart`

- [ ] **Step 1: Write failing config test**

Extend an existing glue_config test file:

```dart
test('showReasoning defaults to true and reads GLUE_SHOW_REASONING', () {
  final c1 = GlueConfig.resolve(env: {}, fileConfig: null);
  expect(c1.showReasoning, isTrue);

  final c2 = GlueConfig.resolve(env: {'GLUE_SHOW_REASONING': 'false'}, fileConfig: null);
  expect(c2.showReasoning, isFalse);

  final c3 = GlueConfig.resolve(env: {}, fileConfig: {'show_reasoning': false});
  expect(c3.showReasoning, isFalse);
});
```

- [ ] **Step 2: Verify RED**

Run: `dart test test/config/glue_config_test.dart --name "showReasoning"`
Expected: FAIL — field doesn't exist.

- [ ] **Step 3: Add field + resolver**

In `GlueConfig`:

```dart
final bool showReasoning;
```

Add to constructor, add to resolver (model the resolution after `titleGenerationEnabled` which has an identical shape):

```dart
final showReasoningStr =
    env['GLUE_SHOW_REASONING'] ?? fileConfig?['show_reasoning']?.toString();
final showReasoning = showReasoningStr == null
    ? true
    : showReasoningStr.toLowerCase() != 'false';
```

- [ ] **Step 4: Runtime toggle keybinding**

In `cli/lib/src/app/terminal_event_router.dart`, near the Shift+Tab approval toggle:

```dart
if (event case KeyEvent(key: Key.t, ctrl: true)) {
  app._showReasoningOverride = !(app._showReasoningOverride ?? app._config.showReasoning);
  app._render();
  return;
}
```

Store `_showReasoningOverride` on App as nullable bool; `agent_orchestration.dart` then reads `app._showReasoningOverride ?? app._config.showReasoning` instead of `app._config.showReasoning` directly. Update the read in Task 8 accordingly if implementing this task.

- [ ] **Step 5: Verify GREEN**

Run: `dart test test/config/glue_config_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add cli/lib/src/config/glue_config.dart cli/lib/src/app/terminal_event_router.dart cli/lib/src/app.dart cli/test/config
git commit -m "feat(app): add show_reasoning config + Ctrl+T runtime toggle"
```

---

### Task 11: End-to-end manual verification

- [ ] **Step 1: Ollama DeepSeek R1** (fastest path — emits thinking by default, no wire config needed)

```bash
ollama pull deepseek-r1:8b
dart run bin/glue.dart --model ollama/deepseek-r1:8b
# Prompt: "What's 17 * 23? Think step by step."
# Expect: dim italic "▸ Thinking" block with reasoning, then final answer.
```

- [ ] **Step 2: OpenAI gpt-5 reasoning** (emits `delta.reasoning` by default on reasoning-eligible models)

```bash
dart run bin/glue.dart --model openai/gpt-5.4-mini
# Prompt: any non-trivial reasoning question
# Expect: same as above
```

- [ ] **Step 3: Toggle** — press `Ctrl+T`, verify the thinking block stops appearing on the next turn.

- [ ] **Step 4: Full quality gate**

```bash
cd cli && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
```

All should pass.

---

## Phase 2 (Follow-up, not in this plan's task list)

These are deliberately deferred to keep phase 1 shippable:

1. **Anthropic request-side enablement** — Anthropic emits no thinking tokens unless you send `thinking: {type: 'enabled', budget_tokens: N}` in the request body. Requires: plumbing a per-model thinking budget through `ProviderAdapter.createClient()`, extending `ResolvedModel` or `GlueConfig`. Catalog already flags eligible models with the `reasoning` capability (`model_catalog.dart:21`).

2. **OpenAI `reasoning_effort`** — `low | medium | high` knob for gpt-5/o-series. Same plumbing path as Anthropic's budget.

3. **Redacted thinking** — Anthropic's `redacted_thinking` blocks contain base64-encoded `data`. Render as a placeholder (`[redacted reasoning]`) rather than nothing, so users know content was suppressed.

4. **Thinking tokens in `UsageInfo`** — Anthropic returns a `thinking_tokens` field in final usage; billed separately. Extend `UsageInfo` with an optional `thinkingTokens` field and surface in the status bar.

5. **ACP/WebUI parity** — `docs/plans/2026-02-27-acp-webui.md` already anticipates `agent_thought_chunk`. Once phase 1 lands, port the same rendering convention to ACP.

6. **Session resume** — Ensure `_ConversationEntry.thinking` blocks serialize into the session JSONL and rehydrate on `/resume`. Check `cli/lib/src/storage/` conventions.

## Open Questions

- **Collapsible by default?** Claude Code and Cursor show thinking inline by default; other tools collapse. This plan ships inline-visible; we can add collapse-on-complete as a follow-up if users ask.
- **Should thinking be persisted to the on-disk transcript?** Cheaper to yes than to find out we needed it later — Task 7's `_ConversationEntry.thinking` naturally feeds the existing storage path. Verify in Phase 2.5 when session resume gets attention.

## Verification Commands

```bash
# Focused (fastest feedback loop while implementing):
cd cli && dart test test/llm/ test/agent_core_test.dart test/block_renderer_test.dart

# Before PR:
cd cli && dart format --set-exit-if-changed .
cd cli && dart analyze --fatal-infos
cd cli && dart test

# End-to-end with a reasoning model:
cd cli && dart run bin/glue.dart --model ollama/deepseek-r1:8b
```

## Files Summary

| Concern          | File                                         | Nature                                 |
| ---------------- | -------------------------------------------- | -------------------------------------- |
| Chunk union      | `cli/lib/src/agent/agent_core.dart`          | add `ThinkingDelta`                    |
| Event union      | `cli/lib/src/agent/agent_core.dart`          | add `AgentThinkingDelta`               |
| Chunk→Event      | `cli/lib/src/agent/agent_core.dart` run()    | new switch case                        |
| Headless         | `cli/lib/src/agent/agent_runner.dart`        | noop case                              |
| Anthropic parser | `cli/lib/src/llm/anthropic_client.dart`      | handle `thinking_delta`                |
| OpenAI parser    | `cli/lib/src/llm/openai_client.dart`         | handle `reasoning`/`reasoning_content` |
| Ollama parser    | `cli/lib/src/llm/ollama_client.dart`         | handle `message.thinking`              |
| Entry kind       | `cli/lib/src/app/models.dart`                | `_EntryKind.thinking`                  |
| App buffer       | `cli/lib/src/app.dart`                       | `_streamingThinking`                   |
| Orchestration    | `cli/lib/src/app/agent_orchestration.dart`   | handle event + flush                   |
| Render pipeline  | `cli/lib/src/app/render_pipeline.dart`       | emit thinking lines                    |
| Block renderer   | `cli/lib/src/rendering/block_renderer.dart`  | `renderThinking`                       |
| Keybinding       | `cli/lib/src/app/terminal_event_router.dart` | Ctrl+T toggle                          |
| Config           | `cli/lib/src/config/glue_config.dart`        | `showReasoning`                        |
