# Coalesce subagent streaming deltas before persistence

## Context

Investigating session `1778140738915-hm` revealed the share HTML bloated to 1.2 MB with **9,880 separate "subagent message" entries** averaging 4 characters each (`'Below'`, `' is'`, `' a'`, `' practical'`...). Every streaming token from a subagent is being persisted as its own JSONL row with `inner.type = "assistant_message"`.

Root cause is in `packages/glue_harness/lib/src/agent/agent_manager.dart:173-184`. The `onEvent` callback wired into `AgentRunner` does two things:
1. Pushes a `SubagentUpdate` onto the live UI stream — correct behavior, must keep per-event.
2. Calls `onPersistEvent` directly, which routes every `AgentTextDelta` through `serializeAgentEvent` → `{type: 'assistant_message', text: <one token>}`.

The main-agent path at `cli/lib/src/app/agent_orchestration.dart:80-95` already does the right thing: deltas accumulate in `app._streamingText` and only get persisted as one `assistant_message` row when a tool call begins or the turn ends. The subagent path skipped this step.

The downstream renderer (`share_transcript_builder.dart:82-101`) and normalizer (`session_event_normalizer.dart:139-142`) faithfully render whatever they're given — they're not the bug, and don't need changes.

Outcome: subagent transcripts persist one `assistant_message` row per **completed** message, not per token. Existing on-disk sessions stay broken (no migration in scope), but newly recorded sessions will be ~28× smaller and render correctly.

## Files to touch

**Modify:**
- `packages/glue_harness/lib/src/agent/agent_manager.dart` — buffer text/thinking deltas inside the `spawnSubagent` `onEvent` closure; flush on non-delta events and on subagent termination.

**Add:**
- `cli/test/agent/agent_manager_test.dart` — extend with a coalescing test (file already exists with fake `_EchoLlm` infrastructure — reuse it).

**Unchanged:**
- `serializeAgentEvent` (still handles `AgentTextDelta` / `AgentThinkingDelta` cases as a defensive fallback; deltas just never reach it for subagents now).
- The `_updateController.add(SubagentUpdate(...))` live UI feed continues to fire per-event.
- Renderer / normalizer / share builder — nothing to do.
- Main-agent path — already correct.

## Implementation

In `agent_manager.dart`, restructure the `onEvent` closure inside `spawnSubagent` (currently lines 169-185) and the surrounding try/catch (lines 187-203):

1. **Allocate per-spawn buffers** before constructing the `AgentRunner`:
   ```dart
   final textBuf = StringBuffer();
   final thinkingBuf = StringBuffer();
   ```

2. **Add a local `flushPendingMessages()` closure** that emits one persisted row per non-empty buffer, then clears them. Emits the same shape `serializeAgentEvent` would have produced for a single delta, just with the concatenated text:
   ```dart
   void flushPendingMessages() {
     if (textBuf.isNotEmpty) {
       onPersistEvent?.call('subagent_event', {
         'subagent_id': subagentId.value,
         'inner': {'type': 'assistant_message', 'text': textBuf.toString()},
       });
       textBuf.clear();
     }
     if (thinkingBuf.isNotEmpty) {
       onPersistEvent?.call('subagent_event', {
         'subagent_id': subagentId.value,
         'inner': {'type': 'assistant_thinking', 'text': thinkingBuf.toString()},
       });
       thinkingBuf.clear();
     }
   }
   ```

3. **Rewrite the runner's `onEvent` closure** to keep the live UI feed unchanged while routing persistence through the buffers:
   ```dart
   onEvent: (event) {
     // Live UI feed — unchanged.
     _updateController.add(SubagentUpdate(
       task: task, index: index, total: total, event: event,
     ));
     // Persistence: buffer streaming deltas, flush on any other event.
     switch (event) {
       case AgentTextDelta(:final delta):
         textBuf.write(delta);
       case AgentThinkingDelta(:final delta):
         thinkingBuf.write(delta);
       default:
         flushPendingMessages();
         onPersistEvent?.call('subagent_event', {
           'subagent_id': subagentId.value,
           'inner': serializeAgentEvent(event),
         });
     }
   },
   ```

4. **Final flush in both terminal paths** — before the `subagent_completed` calls at lines 190 (success) and 197 (catch), call `flushPendingMessages()` so any tail text/thinking after the last tool call (or in an error path) is preserved.

The `_finaliseSubagentUsage` path (which fires before `subagent_completed`) is untouched; usage events arrive through the runner's `AgentUsage` event and already trigger a flush via the `default` branch.

## Tests

Extend `cli/test/agent/agent_manager_test.dart`:

1. **Add a multi-delta fake LLM** (separate fixture class alongside `_EchoLlm` at line 7). It yields, in order, several `TextDelta` chunks, an `AssistantMessage` with a `ToolCall`, a tool result, several more `TextDelta` chunks, then `UsageInfo` and finishes. (Inspect `LlmChunk` / `Message` shapes via `package:glue_core/glue_core.dart` — already imported in the test file at line 2 — and mirror what `_EchoLlm` does at lines 9-14.)

2. **Add a coalescing test** that captures `onPersistEvent` calls (same harness already used at lines 62-86 for the existing persistence test) and asserts:
   - Exactly **two** `subagent_event` rows with `inner.type == 'assistant_message'` are persisted (the chunks before and after the tool call), not one per chunk.
   - Each persisted text equals the concatenation of its source deltas.
   - The `tool_call_pending` / `tool_call` / `tool_result` rows still appear in the expected order, between/around the two `assistant_message` rows.

3. **Existing tests must keep passing unchanged.** The `_EchoLlm` emits a single `TextDelta` per turn — the new code still produces one `assistant_message` row per spawn for that fixture, so the existing assertion at lines 80-85 (innerEvents non-empty, all carrying `subagent_id`) still holds.

## Verification

1. **Unit tests**: from repo root run `just cli::test` — both the new coalescing test and all existing `agent_manager_test.dart` cases pass.
2. **Quality gate**: `just check` — formatting, analyze (no warnings, per the zero-warning policy), and full test suite green across cli + glue_harness.
3. **End-to-end smoke** (manual, optional but recommended given the bug bit a real session):
   - `dart compile exe bin/glue.dart -o /tmp/glue-test` from `cli/`.
   - From a scratch dir, run `/tmp/glue-test` and trigger a prompt that spawns a subagent (e.g., something that uses `subagent_tools` parallel spawn).
   - After the session ends, inspect `~/.glue/sessions/<new-id>/conversation.jsonl`:
     ```sh
     python3 -c "
     import json
     from collections import Counter
     c = Counter()
     for line in open('<path>'):
         e = json.loads(line)
         if e['type'] == 'subagent_event':
             c[(e.get('inner') or {}).get('type','?')] += 1
     print(c)
     "
     ```
     Expect a small handful of `assistant_message` entries (matching the number of distinct subagent turns), not thousands.
4. **Render the new session** with the `/share` slash command to confirm the HTML transcript shows one bubble per subagent message rather than thousands of token fragments.

Out of scope: migrating existing chunked sessions on disk. Old sessions like `1778140738915-hm` will keep rendering as fragments until either re-recorded or a future migration coalesces consecutive `subagent_event/assistant_message` rows per `subagent_id`.
