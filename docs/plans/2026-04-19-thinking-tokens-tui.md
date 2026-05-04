# Thinking Tokens in the TUI — Implementation Plan

> **Status:** proposed (re-spec'd 2026-04-30 against the harness/strategies/core split)
> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface streaming reasoning/"thinking" traces from reasoning-capable models (Claude extended thinking, OpenAI gpt-5/o-series, DeepSeek R1 via Ollama) in the Glue TUI as a distinct, visually muted block inline with the conversation.

**Architecture:** Add a `ThinkingDelta` variant to the existing sealed `LlmChunk` union in `glue_core`, flow it through `AgentCore` (in `glue_harness`) as an `AgentThinkingDelta` event, render it in a dedicated conversation block kind in the CLI surface using dim/italic ANSI styling. Parser changes are additive and provider-specific (Anthropic `thinking_delta`, OpenAI `delta.reasoning`, Ollama `message.thinking`) and live in `glue_strategies/llm/`. Enablement on the request side (Anthropic's `thinking: {budget_tokens}`, OpenAI's `reasoning_effort`) is phase 2 — phase 1 only surfaces what providers already emit.

**Tech Stack:** Dart, existing SSE/NDJSON parsers in `glue_strategies`, sealed `LlmChunk`/`AgentEvent` unions in `glue_core`, existing `BlockRenderer` + 60fps coalesced render loop in `cli/`.

---

## Layer placement at a glance

| Concern | Layer | Package |
|---|---|---|
| `ThinkingDelta` chunk variant | core | `glue_core/lib/src/message.dart` |
| `AgentThinkingDelta` event variant | core | `glue_core/lib/src/agent_event.dart` |
| Provider parsers (Anthropic/OpenAI/Ollama) | strategies | `glue_strategies/lib/src/llm/*` |
| `AgentCore` chunk→event routing | harness | `glue_harness/lib/src/agent/agent_core.dart` |
| `AgentRunner` headless noop | harness | `glue_harness/lib/src/agent/agent_runner.dart` |
| Conversation entry kind | surface | `cli/lib/src/app/models.dart` |
| Streaming buffer + flush | surface | `cli/lib/src/app/agent_orchestration.dart` |
| Block renderer | surface | `cli/lib/src/rendering/block_renderer.dart` |
| Keybinding | surface | `cli/lib/src/app/terminal_event_router.dart` |
| `showReasoning` config | harness | `glue_harness/lib/src/config/glue_config.dart` |

The cross-package wiring forces a clean order of operations: core changes
must land first because every other layer imports from them.

---

## Context

Reasoning-capable models (Claude 4.x with extended thinking, GPT-5/o-series, DeepSeek R1, QwQ, etc.) emit a structured "thinking" stream alongside or before their final answer. Today Glue silently drops these tokens at every provider parser — `glue_strategies/llm/anthropic_client.dart` ignores `thinking_delta`, `glue_strategies/llm/openai_client.dart` ignores `delta.reasoning`, `glue_strategies/llm/ollama_client.dart` ignores `message.thinking`. The model catalog already tags these models with the `reasoning` capability (`glue_core/lib/src/model_catalog.dart`), so the UX gap is visible.

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
- ACP/WebUI surfaces — `docs/plans/2026-02-27-acp-webui.md` already references `agent_thought_chunk`; this plan keeps the TUI path clean so the ACP server (`packages/glue_server/`) can mirror it later by translating `AgentThinkingDelta` to ACP `agent_thought_chunk` notifications.

## File Structure

**Modify:**

- `packages/glue_core/lib/src/message.dart` — add `ThinkingDelta` to the sealed `LlmChunk` union (alongside `TextDelta`, `UsageInfo`).
- `packages/glue_core/lib/src/agent_event.dart` — add `AgentThinkingDelta` to the sealed `AgentEvent` union (alongside `AgentTextDelta`, `AgentToolCallPending`, `AgentDone`).
- `packages/glue_harness/lib/src/agent/agent_core.dart` — route `ThinkingDelta` → `AgentThinkingDelta` in `run()`'s `switch (chunk)` block.
- `packages/glue_harness/lib/src/agent/agent_runner.dart` — noop-handle `AgentThinkingDelta` (headless discards).
- `packages/glue_strategies/lib/src/llm/anthropic_client.dart` — parse `content_block_start` with `type: thinking` and `content_block_delta` with `delta.type: thinking_delta`.
- `packages/glue_strategies/lib/src/llm/openai_client.dart` — parse `delta.reasoning` and `delta.reasoning_content` fallbacks.
- `packages/glue_strategies/lib/src/llm/ollama_client.dart` — parse `message.thinking`.
- `cli/lib/src/app/models.dart` — add `_EntryKind.thinking` and `_ConversationEntry.thinking(text)`.
- `cli/lib/src/app.dart` — add `_streamingThinking` buffer alongside `_streamingText`.
- `cli/lib/src/app/agent_orchestration.dart` — handle `AgentThinkingDelta`, flush thinking on transition to text/tool/done.
- `cli/lib/src/app/render_pipeline.dart` — render `_streamingThinking` in output zone, render `_EntryKind.thinking` blocks.
- `cli/lib/src/rendering/block_renderer.dart` — add `renderThinking(String text)`.
- `cli/lib/src/app/terminal_event_router.dart` — add keybinding for toggle (proposed: `Ctrl+T`).
- `packages/glue_harness/lib/src/config/glue_config.dart` — add `showReasoning` bool (default `true`), resolve from CLI arg → env `GLUE_SHOW_REASONING` → config file.

**Create tests:**

- `packages/glue_core/test/message_test.dart` — pattern-match exhaustiveness for `LlmChunk`.
- `packages/glue_strategies/test/llm/anthropic_client_test.dart` — add thinking-delta case.
- `packages/glue_strategies/test/llm/openai_client_test.dart` — add reasoning case.
- `packages/glue_strategies/test/llm/ollama_client_test.dart` — add thinking case.
- `packages/glue_harness/test/agent/agent_core_test.dart` — add chunk→event routing case.
- `cli/test/rendering/block_renderer_test.dart` — add `renderThinking` case.
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

Anthropic also emits `redacted_thinking` blocks (base64 signed payloads for safety-sensitive reasoning). **Ignore these in phase 1** — they carry no human-readable content. The relevant hook is the `content_block_delta` switch in `glue_strategies/lib/src/llm/anthropic_client.dart`.

### OpenAI Chat Completions (SSE, `choices[0].delta`)

```json
{"choices":[{"delta":{"reasoning":"Thinking about the constraints..."}}]}
{"choices":[{"delta":{"reasoning":" tool choice should be X"}}]}
{"choices":[{"delta":{"content":"Here's the answer..."}}]}
```

Some gateways/proxies use `reasoning_content` instead of `reasoning` (DeepSeek-style). Handle both. The hook is the delta-dispatch block in `glue_strategies/lib/src/llm/openai_client.dart`.

### Ollama (NDJSON)

```json
{"model":"deepseek-r1","message":{"role":"assistant","thinking":"Step 1: understand..."},"done":false}
{"model":"deepseek-r1","message":{"role":"assistant","content":"Here's the answer..."},"done":false}
```

Field is `message.thinking`. Hook is the message-handling block in `glue_strategies/lib/src/llm/ollama_client.dart`.

---

## Task Breakdown

### Task 1: Add `ThinkingDelta` to the sealed `LlmChunk` in glue_core

**Files:**

- Modify: `packages/glue_core/lib/src/message.dart`

- [ ] **Step 1: Write the failing test**

In `packages/glue_core/test/message_test.dart`:

```dart
test('ThinkingDelta is a distinct LlmChunk variant', () {
  const chunk = ThinkingDelta('reasoning...');
  expect(chunk, isA<LlmChunk>());
  expect(chunk.text, 'reasoning...');
});
```

- [ ] **Step 2: Verify RED**

`(cd packages/glue_core && dart test --name "ThinkingDelta is a distinct")` — should FAIL with "Undefined name 'ThinkingDelta'".

- [ ] **Step 3: Implement**

Add to `packages/glue_core/lib/src/message.dart`, immediately after `TextDelta`:

```dart
/// A delta of streaming reasoning / "thinking" content. Distinct from
/// [TextDelta] so renderers can style it as non-final, deliberative output.
/// Not every provider emits this — only reasoning-capable models.
class ThinkingDelta extends LlmChunk {
  final String text;
  const ThinkingDelta(this.text);
}
```

- [ ] **Step 4: Verify GREEN** + run downstream analyze to surface any non-exhaustive switch sites:

```sh
cd packages/glue_core && dart test
cd ../glue_strategies && dart analyze --fatal-infos
cd ../glue_harness && dart analyze --fatal-infos
cd ../../cli && dart analyze --fatal-infos
```

Pattern-matching warnings here will tell you exactly which switches need updating in later tasks.

- [ ] **Step 5: Commit**

```bash
git add packages/glue_core
git commit -m "feat(core): add ThinkingDelta LlmChunk variant"
```

---

### Task 2: Add `AgentThinkingDelta` and route in `AgentCore`

**Files:**

- Modify: `packages/glue_core/lib/src/agent_event.dart` (AgentEvent union)
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart` (`run()` switch)
- Modify: `packages/glue_harness/lib/src/agent/agent_runner.dart` (headless switch)

- [ ] **Step 1: Write failing test**

In `packages/glue_harness/test/agent/agent_core_test.dart`:

```dart
test('AgentCore forwards ThinkingDelta as AgentThinkingDelta', () async {
  final llm = _StubLlm(chunks: [const ThinkingDelta('reasoning...'), const TextDelta('answer')]);
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

`_StubLlm` should already exist in the file — copy from existing test patterns if not.

- [ ] **Step 2: Verify RED**

`(cd packages/glue_harness && dart test --name "forwards ThinkingDelta")` — FAIL with "Undefined name 'AgentThinkingDelta'".

- [ ] **Step 3: Add AgentThinkingDelta to glue_core**

In `packages/glue_core/lib/src/agent_event.dart`, after `AgentTextDelta`:

```dart
/// A delta of streaming reasoning/thinking content forwarded to the UI.
/// Renderers should style this distinctly from [AgentTextDelta].
class AgentThinkingDelta extends AgentEvent {
  final String delta;
  const AgentThinkingDelta(this.delta);
}
```

- [ ] **Step 4: Route in `AgentCore.run()`**

In the `switch (chunk)` block, add a case above `TextDelta`:

```dart
case ThinkingDelta(:final text):
  yield AgentThinkingDelta(text);
```

Do **not** append to `assistantText` — thinking does not go into the assistant message that gets sent back to the model on the next turn (that would pollute context and, for Anthropic, is explicitly forbidden without the right block structure).

- [ ] **Step 5: Handle in AgentRunner**

In `agent_runner.dart`'s switch, add a no-op case:

```dart
case AgentThinkingDelta():
  break; // headless mode discards reasoning traces
```

- [ ] **Step 6: Verify GREEN + existing tests**

```sh
cd packages/glue_harness && dart test
```

- [ ] **Step 7: Commit**

```bash
git add packages/glue_core packages/glue_harness
git commit -m "feat(harness): forward ThinkingDelta as AgentThinkingDelta event"
```

---

### Task 3: Anthropic parser — emit `ThinkingDelta`

**Files:**

- Modify: `packages/glue_strategies/lib/src/llm/anthropic_client.dart`
- Modify: `packages/glue_strategies/test/llm/anthropic_client_test.dart`

- [ ] **Step 1: Write failing test**

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

- [ ] **Step 3: Implement**

In `anthropic_client.dart`, inside the `content_block_delta` branch, extend the switch on `deltaType`:

```dart
} else if (deltaType == 'thinking_delta') {
  final thinking = delta['thinking'];
  if (thinking is String && thinking.isNotEmpty) {
    yield ThinkingDelta(thinking);
  }
}
```

(Do not handle `redacted_thinking` — base64 `data` field, not human-readable.)

- [ ] **Step 4: Verify GREEN**

- [ ] **Step 5: Commit**

```bash
git add packages/glue_strategies
git commit -m "feat(strategies/llm/anthropic): emit ThinkingDelta for extended-thinking blocks"
```

---

### Task 4: OpenAI parser — emit `ThinkingDelta`

**Files:**

- Modify: `packages/glue_strategies/lib/src/llm/openai_client.dart`
- Modify: `packages/glue_strategies/test/llm/openai_client_test.dart`

- [ ] **Step 1: Write failing test**

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

- [ ] **Step 3: Implement**

In `openai_client.dart`, inside the delta handling block, before the `content` check:

```dart
final reasoning = delta['reasoning'] ?? delta['reasoning_content'];
if (reasoning is String && reasoning.isNotEmpty) {
  yield ThinkingDelta(reasoning);
}
```

Keep existing `content` handling intact — a single delta object may contain both.

- [ ] **Step 4: Verify GREEN**

- [ ] **Step 5: Commit**

```bash
git add packages/glue_strategies
git commit -m "feat(strategies/llm/openai): emit ThinkingDelta for reasoning deltas"
```

---

### Task 5: Ollama parser — emit `ThinkingDelta`

**Files:**

- Modify: `packages/glue_strategies/lib/src/llm/ollama_client.dart`
- Modify: `packages/glue_strategies/test/llm/ollama_client_test.dart`

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

- [ ] **Step 3: Implement**

In `ollama_client.dart`, before the existing `content` check inside message handling:

```dart
final thinking = message['thinking'];
if (thinking is String && thinking.isNotEmpty) {
  yield ThinkingDelta(thinking);
}
```

- [ ] **Step 4: Verify GREEN**

- [ ] **Step 5: Commit**

```bash
git add packages/glue_strategies
git commit -m "feat(strategies/llm/ollama): emit ThinkingDelta for message.thinking"
```


---

### Task 6: `renderThinking` on BlockRenderer (CLI surface)

**Files:**

- Modify: `cli/lib/src/rendering/block_renderer.dart`
- Modify: `cli/test/rendering/block_renderer_test.dart`

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

- [ ] **Step 3: Implement**

In `block_renderer.dart`, near `renderAssistant`:

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

Style choice: dim + italic on body reads as "aside/annotation" without being hard to read; gray header with `▸` visually subordinates the block to user/assistant headers (which use `❯`/`◆`).

- [ ] **Step 4: Verify GREEN**

- [ ] **Step 5: Commit**

```bash
git add cli/lib/src/rendering cli/test/rendering
git commit -m "feat(cli/rendering): add renderThinking for reasoning traces"
```

---

### Task 7: Conversation entry kind + App buffer

**Files:**

- Modify: `cli/lib/src/app/models.dart`
- Modify: `cli/lib/src/app.dart`

- [ ] **Step 1: Add entry kind**

In `cli/lib/src/app/models.dart`:

```dart
enum _EntryKind {
  user,
  assistant,
  thinking,        // ← new
  toolCallRef,
  toolResult,
  error,
  system,
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
git commit -m "refactor(cli/app): add thinking entry kind and streaming buffer"
```

---

### Task 8: Handle `AgentThinkingDelta` in orchestration

**Files:**

- Modify: `cli/lib/src/app/agent_orchestration.dart`

- [ ] **Step 1: Add case in `_handleAgentEventImpl` switch**

```dart
case AgentThinkingDelta(:final delta):
  if (!app._config.showReasoning) {
    return;
  }
  app._streamingThinking += delta;
  app._render();
```

- [ ] **Step 2: Flush thinking on transitions**

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
git commit -m "feat(cli/app): flush thinking buffer on transitions, respect toggle"
```

---

### Task 9: Render streaming + finalized thinking blocks

**Files:**

- Modify: `cli/lib/src/app/render_pipeline.dart`

- [ ] **Step 1: Render finalized blocks**

In the block iteration, add a case:

```dart
case _EntryKind.thinking:
  outputLines.addAll(renderer.renderThinking(entry.text).split('\n'));
```

- [ ] **Step 2: Render streaming thinking buffer**

Near the `_streamingText` render, before it:

```dart
if (app._streamingThinking.isNotEmpty) {
  outputLines
      .addAll(renderer.renderThinking(app._streamingThinking).split('\n'));
}
```

Ordering rationale: thinking appears _before_ streaming assistant text in the output buffer so when both are active (rare — Anthropic interleaves text and thinking in edge cases), the user sees reasoning "above" the conclusion.

- [ ] **Step 3: Commit**

```bash
git add cli/lib/src/app/render_pipeline.dart
git commit -m "feat(cli/app): render streaming and finalized thinking blocks"
```

---

### Task 10: Config + runtime toggle

**Files:**

- Modify: `packages/glue_harness/lib/src/config/glue_config.dart`
- Modify: `cli/lib/src/app/terminal_event_router.dart`

- [ ] **Step 1: Write failing config test**

In `packages/glue_harness/test/config/glue_config_test.dart`:

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

- [ ] **Step 3: Add field + resolver**

In `GlueConfig`:

```dart
final bool showReasoning;
```

Resolve following the `titleGenerationEnabled` pattern:

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

Store `_showReasoningOverride` on App as nullable bool; `agent_orchestration.dart` then reads `app._showReasoningOverride ?? app._config.showReasoning` instead of `app._config.showReasoning` directly. Update Task 8's read accordingly.

- [ ] **Step 5: Verify GREEN**

- [ ] **Step 6: Commit**

```bash
git add packages/glue_harness cli/lib/src/app
git commit -m "feat(cli/app): add show_reasoning config + Ctrl+T runtime toggle"
```

---

### Task 11: End-to-end manual verification

- [ ] **Step 1: Ollama DeepSeek R1** (fastest path — emits thinking by default, no wire config needed)

```bash
ollama pull deepseek-r1:8b
cd cli && dart run bin/glue.dart --model ollama/deepseek-r1:8b
# Prompt: "What's 17 * 23? Think step by step."
# Expect: dim italic "▸ Thinking" block with reasoning, then final answer.
```

- [ ] **Step 2: OpenAI gpt-5 reasoning** (emits `delta.reasoning` by default on reasoning-eligible models)

```bash
cd cli && dart run bin/glue.dart --model openai/gpt-5.4-mini
# Prompt: any non-trivial reasoning question
# Expect: same as above
```

- [ ] **Step 3: Toggle** — press `Ctrl+T`, verify thinking stops appearing on next turn.

- [ ] **Step 4: Full quality gate (monorepo)**

```bash
just check
```

All packages should pass formatting, analyze, and tests.

---

## Phase 2 (Follow-up, not in this plan's task list)

These are deliberately deferred to keep phase 1 shippable:

1. **Anthropic request-side enablement** — Anthropic emits no thinking tokens unless `thinking: {type: 'enabled', budget_tokens: N}` is in the request body. Requires plumbing a per-model thinking budget through `ProviderAdapter.createClient()` (in `glue_strategies/providers/`), extending `ResolvedModel` or `GlueConfig`. Catalog already flags eligible models with the `reasoning` capability.

2. **OpenAI `reasoning_effort`** — `low | medium | high` knob for gpt-5/o-series. Same plumbing path as Anthropic's budget.

3. **Redacted thinking** — Anthropic's `redacted_thinking` blocks contain base64 `data`. Render as a placeholder (`[redacted reasoning]`) rather than nothing, so users know content was suppressed.

4. **Thinking tokens in `UsageInfo`** — Anthropic returns a `thinking_tokens` field in final usage; billed separately. Extend `UsageInfo` (in `glue_core/message.dart`) with an optional `thinkingTokens` field and surface in the status bar.

5. **ACP/WebUI parity** — `docs/plans/2026-02-27-acp-webui.md` anticipates `agent_thought_chunk`. Once phase 1 lands, port the same convention by translating `AgentThinkingDelta` → ACP notification in `glue_server`'s update mapper.

6. **Session resume** — Ensure `_ConversationEntry.thinking` blocks persist via `SessionStore` (`glue_harness/storage/`) and rehydrate on `/resume`. The cleanest path is a new `AssistantThinkingEvent` in `glue_core/session_event.dart`, but that's phase 2 once the live UX is settled.

## Open Questions

- **Collapsible by default?** Claude Code and Cursor show thinking inline by default; other tools collapse. This plan ships inline-visible; collapse-on-complete is a follow-up if users ask.
- **Should thinking be persisted to the on-disk transcript?** Cheaper to yes than to find out we needed it later — Task 7's `_ConversationEntry.thinking` naturally feeds the existing storage path. Verify in Phase 2.5 when session resume gets attention.

## Verification Commands

```bash
# Focused (fastest feedback loop while implementing):
cd packages/glue_core && dart test
cd packages/glue_strategies && dart test test/llm/
cd packages/glue_harness && dart test test/agent/
cd cli && dart test test/rendering test/app/

# Before PR (monorepo gate):
just check

# End-to-end with a reasoning model:
cd cli && dart run bin/glue.dart --model ollama/deepseek-r1:8b
```

## Files Summary

| Concern          | File                                                                | Nature                                 |
| ---------------- | ------------------------------------------------------------------- | -------------------------------------- |
| Chunk union      | `packages/glue_core/lib/src/message.dart`                           | add `ThinkingDelta`                    |
| Event union      | `packages/glue_core/lib/src/agent_event.dart`                       | add `AgentThinkingDelta`               |
| Chunk→Event      | `packages/glue_harness/lib/src/agent/agent_core.dart` `run()`       | new switch case                        |
| Headless         | `packages/glue_harness/lib/src/agent/agent_runner.dart`             | noop case                              |
| Anthropic parser | `packages/glue_strategies/lib/src/llm/anthropic_client.dart`        | handle `thinking_delta`                |
| OpenAI parser    | `packages/glue_strategies/lib/src/llm/openai_client.dart`           | handle `reasoning`/`reasoning_content` |
| Ollama parser    | `packages/glue_strategies/lib/src/llm/ollama_client.dart`           | handle `message.thinking`              |
| Entry kind       | `cli/lib/src/app/models.dart`                                       | `_EntryKind.thinking`                  |
| App buffer       | `cli/lib/src/app.dart`                                              | `_streamingThinking`                   |
| Orchestration    | `cli/lib/src/app/agent_orchestration.dart`                          | handle event + flush                   |
| Render pipeline  | `cli/lib/src/app/render_pipeline.dart`                              | emit thinking lines                    |
| Block renderer   | `cli/lib/src/rendering/block_renderer.dart`                         | `renderThinking`                       |
| Keybinding       | `cli/lib/src/app/terminal_event_router.dart`                        | Ctrl+T toggle                          |
| Config           | `packages/glue_harness/lib/src/config/glue_config.dart`             | `showReasoning`                        |
