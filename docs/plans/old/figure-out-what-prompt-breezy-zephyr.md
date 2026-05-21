# Combined plan: trim API-key paste, fix Gemini thought-signature, add `/copy debug`

## Context

Three actionable items surfaced after the paste-routing fix landed:

1. **Trim API-key paste.** Pre-existing LOW from the earlier code review: `api_key_prompt_panel.dart:80` writes pasted content verbatim into the masked buffer. A trailing `\n` from the clipboard becomes part of the key, gets sent to the provider as `sk-…\n`, and is rejected as malformed. Only visible to the user as `•` dots.
2. **Gemini API rejects tool-using turns with HTTP 400** complaining `Function call is missing a thought_signature in functionCall parts`. Reproduced on Gemini 3.1 Flash-Lite Preview after a successful `web_search` round. Glue is dropping the `thoughtSignature` field that Gemini emits on each `functionCall` part and is required to be echoed back on the next request.
3. **`/copy debug` mode.** Today plain `/copy` only finds the last assistant text block. When a turn errors out (like the Gemini case above), there's no assistant block, so the user sees `No assistant response to copy.` and can't even copy the error message they want to file. The user wants `/copy debug` to include errors, tool calls / args / results, and thinking blocks (when captured).

**Deferred:** PhpStorm raw-mode crash — already addressed by the inline error message + `glue doctor` Terminal section earlier in this branch.

---

## Item 1: Trim API-key paste — surgical one-liner

**File:** `cli/lib/src/providers/api_key_prompt_panel.dart:79-81`

```dart
case PasteEvent(:final content):
  _buffer.write(content.trim());        // ← was: _buffer.write(content);
  return true;
```

Use `.trim()` rather than `.trimRight()` — leading whitespace in an API key is also virtually always accidental, and stripping both sides is what users expect.

**Test:** `cli/test/providers/api_key_prompt_panel_test.dart` — add a case that pastes `"sk-token\n"` and asserts the submitted value is `"sk-token"`.

**Verification:** `dart test test/providers/api_key_prompt_panel_test.dart`.

---

## Item 2: Gemini `thoughtSignature` capture-and-replay

### Background
Per Google's docs (https://ai.google.dev/gemini-api/docs/thought-signatures), thinking-mode Gemini models emit an opaque `thoughtSignature` on each part (`text`, `functionCall`, sometimes `thought`). The client MUST echo this verbatim on the next request alongside the same part, or the API rejects with HTTP 400 / INVALID_ARGUMENT. Anthropic doesn't have an equivalent — `tool_use_id` is sufficient — so the existing Anthropic adapter is fine. Only Gemini needs this.

### Three-file fix

#### A. `cli/lib/src/agent/agent.dart` (lines 77-89) — add an optional field

```dart
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String description;
  final String? thoughtSignature;       // NEW; null for non-Gemini providers

  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.description = '',
    this.thoughtSignature,
  });
}
```

Backward-compatible: nullable field, default null. No other provider sets or reads it.

#### B. `cli/lib/src/providers/gemini_provider.dart` (lines 202-219) — capture on parse

In the `functionCall` branch of `parseStreamEvents()`, extract the signature alongside `name` and `args`:

```dart
final fc = part['functionCall'];
if (fc is Map) {
  final name = fc['name']?.toString() ?? '';
  final rawArgs = fc['args'];
  final args = rawArgs is Map<String, dynamic>
      ? rawArgs
      : (rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : <String, dynamic>{});
  final thoughtSig = fc['thoughtSignature']?.toString();   // NEW
  callCounter++;
  final id = 'gemini-call-$callCounter';
  yield ToolCallStart(id: id, name: name);
  yield ToolCallComplete(ToolCall(
    id: id,
    name: name,
    arguments: args,
    thoughtSignature: thoughtSig,                          // NEW
  ));
}
```

#### C. `cli/lib/src/llm/message_mapper.dart` (lines 164-171, in `GeminiMessageMapper`) — replay on next request

When mapping assistant messages back to the Gemini wire format:

```dart
for (final tc in msg.toolCalls) {
  final fc = <String, dynamic>{
    'name': tc.name,
    'args': tc.arguments,
  };
  if (tc.thoughtSignature != null) {
    fc['thoughtSignature'] = tc.thoughtSignature;
  }
  parts.add({'functionCall': fc});
}
```

### Tests

- `cli/test/providers/gemini_provider_test.dart` — add a test that feeds an SSE response containing `"thoughtSignature": "abc123"` and asserts the resulting `ToolCall.thoughtSignature == "abc123"`.
- `cli/test/llm/gemini_message_mapper_test.dart` — add a test that maps a `Message` whose `ToolCall` has `thoughtSignature: "xyz"` and asserts the rendered Gemini `parts[i].functionCall.thoughtSignature == "xyz"`.

### Open question (flag, don't fix yet)

Gemini may also emit `{"thought": "..."}` parts with their own `thoughtSignature`. Glue currently doesn't extract `thought` parts at all (see `gemini_provider.dart:197-200`). If a thinking turn produces a thought before the first `functionCall`, the missing-signature on the thought may also break replay. **Recommend landing the `functionCall` capture/replay first (this unblocks the user's reproducer), then in a follow-up: add `thought`-part extraction + signature replay.**

### Verification

1. Unit tests pass.
2. Manual reproduction from the screenshot scenario: `/provider gemini`, switch to `gemini-3.1-flash-lite-preview`, ask `who is Necati Özmen` (or anything that triggers a tool call), observe the second-round response succeeds instead of HTTP 400.

---

## Item 3: `/copy debug` — argument-aware copy with full turn context

### Current behavior

- `cli/lib/src/ui/actions/chat_actions.dart:78-109` — `copyLastResponse()` walks `transcript.blocks` backward, finds the latest `EntryKind.assistant`, copies `.text`. Empty state emits `transcript.system('No assistant response to copy.')` (line 88).
- `cli/lib/src/ui/slash/app_commands.dart:62-68` — `/copy` registered with no argument support: `execute: (_) { c.chat.copyLastResponse(); return null; }`.
- The transcript already stores everything we'd want: `error` blocks (`EntryKind.error`), tool calls (`EntryKind.toolCall` + `Transcript.toolUi` map of `ToolCallUiState` with phase/args), tool results (`EntryKind.toolResult`), system messages.
- Thinking blocks are NOT captured today — no `EntryKind.thinking`, no `AgentThinking` event. Out of scope for this PR.

### Three-part change

#### A. Argument-aware registration

`cli/lib/src/ui/slash/app_commands.dart` — change the `/copy` registration so it accepts an optional `debug` argument:

```dart
commands.register(SlashCommand(
  name: 'copy',
  description: 'Copy last response to clipboard. /copy debug for full turn context.',
  argCompleter: (partial) => [
    if ('debug'.startsWith(partial))
      SlashArgCandidate(
        value: 'debug',
        description: 'Include errors, tool calls/results, and system events',
      ),
  ],
  execute: (args) {
    final debug = args.trim().toLowerCase() == 'debug';
    c.chat.copyLastResponse(debug: debug);
    return null;
  },
));
```

Pattern is the same one `/share` uses for `html|md|gist` (`cli/lib/src/ui/actions/share_actions.dart`).

#### B. Extended `copyLastResponse(debug:)`

`cli/lib/src/ui/actions/chat_actions.dart` — overload the function:

- **Plain `/copy` (debug=false):** keep existing behavior. Walk back to last `EntryKind.assistant`, copy `.text`. If none found AND debug=false: keep the `No assistant response to copy.` message.
- **`/copy debug`:** walk back from the end of `transcript.blocks` until the previous user turn (or the start). For every block in that range, format as plain text (ANSI-stripped) and concatenate. Block formatters:

| Block kind | Format |
|---|---|
| `user` | `> You\n  <text>\n` |
| `assistant` | `<text>\n` |
| `toolCall` | `[tool] <name>(<args as JSON>)\n` |
| `toolResult` | `[result] <name>\n  <content>\n` |
| `error` | `[error] <message>\n` |
| `system` | (skip — usually UI noise) |
| `bash` | `[bash] <command>\n  <output>\n` |
| `subagent` / `subagentGroup` | `[subagent] <summary>\n` |
| `toolCallRef` | (skip — already covered by `toolCall`) |

Tool call args from `Transcript.toolUi[id].args` if available, else from the `ConversationEntry`. Phase suffix (`(running)`, `(error)`, `(denied)`, `(cancelled)`) appended where applicable.

The result goes through `stripAnsi()` (existing utility at `cli/lib/src/ui/rendering/ansi_utils.dart:60-66`) before the `copyToClipboard()` call. Tool args may contain hyperlink OSC sequences for file paths — strip those too.

Empty-state message in debug mode: `Nothing to copy from this turn.` (better than the current "no assistant response" since debug mode by definition wasn't looking only for assistant text).

#### C. Tests

- `cli/test/ui/actions/chat_actions_test.dart` (or wherever the existing `/copy` test lives) — add three cases:
  1. `/copy debug` after a user turn with a tool call and an error block → clipboard contains `> You`, `[tool] web_search(...)`, `[error] Gemini API error 400…`.
  2. `/copy debug` with no blocks since the last user turn → clipboard untouched, system message `Nothing to copy from this turn.`.
  3. Plain `/copy` continues to work — existing test stays green.

### What `/copy debug` does NOT do (out of scope)

- **Thinking blocks**: not captured by glue today. Adding them is a separate, larger piece of work (new event type, new entry kind, rendering, plus capture in Anthropic + Gemini adapters). Flag in the system message for now: append `(thinking blocks not yet captured — see issue #X)` or similar in the debug copy header.
- **Tool durations / approval state**: phase is captured (`ToolCallUiState.phase`), durations are not. Include phase, skip duration timing for now.

### Verification

1. Unit tests pass.
2. Manual: trigger the same Gemini error scenario as in item 2, run `/copy debug`, paste into a text editor, confirm the copy contains the user prompt, the tool call, the tool result, and the full error JSON.

---

## Suggested order

1. **Trim API-key paste** — 5 lines + 1 test, no risk. Can land first.
2. **Gemini `thoughtSignature`** — 3 files, 4 tests. Production-blocker for any Gemini user with thinking enabled. High priority.
3. **`/copy debug`** — most lines but lowest risk; UX-only. Useful for debugging the Gemini fix in progress (lets you copy the full failure context to share or reason about).

PhpStorm raw-mode crash stays deferred per your earlier call.

## Out of scope

- Capturing thinking blocks from any provider (deferred — would unlock real-time thought streaming and richer `/copy debug` output, but is a larger change touching the LLM client layer for both Anthropic and Gemini).
- Tracking tool call duration / timing in `ToolCallUiState`.
- Refactoring `share/` renderers to back `/copy debug` (current renderers don't include errors; converging them is a follow-up).
