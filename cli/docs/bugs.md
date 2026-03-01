# Bugs & Papercuts

Minor issues to batch-fix later.

---

### `/model` command doesn't update `_config`

**File:** `lib/src/app.dart` (line ~396)

`/model` swaps the `LlmClient` on `agent.llm` and updates the `_modelName` display string, but never updates `_config`. Anything that later reads `_config.model` will see the stale original model name. Low risk today since most display paths use `_modelName`, but will bite if `_config` gets used more broadly (e.g. session metadata, subagent spawning inheriting parent model).

**Fix:** Either update `_config` to a new `GlueConfig` with the new model, or derive `_modelName` from `_config` directly so there's a single source of truth.

---

### `/skills` command uses stale skills data

**File:** wherever `/skills` is handled (likely `lib/src/commands/` or `lib/src/app.dart`)

The `/skills` command displays the list of available skills, but the skills are loaded once at startup and not reloaded when the command is triggered. If the user adds, removes, or edits a skill file in `~/.glue/skills/` during a session, `/skills` will show stale data — missing new skills, showing deleted ones, or displaying outdated descriptions.

**Fix:** Re-scan the skills directory on every `/skills` invocation instead of reading from the cached in-memory list.

---

### Bash mode has no shell tab-completion

**File:** `lib/src/app.dart` (bash mode), `lib/src/input/line_editor.dart`

When in bash mode (`!` prefix), typing a command and pressing Tab does nothing useful — `LineEditor` emits `InputAction.requestCompletion` but the app only wires that to `SlashAutocomplete` / `AtFileHint`. The user's shell completions (commands, flags, paths, git branches, etc.) are completely unavailable because we own the input buffer — the command never passes through a real shell until submit.

This is noticeable for anyone used to shell autocomplete (i.e. everyone).

**Context — how shells expose completions:**

| Shell    | Mechanism                                                                                                                                                                                                                                                                                                                   | Difficulty                                                                                                                         |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **bash** | `compgen` builtin: `compgen -c "git"` (commands), `compgen -f "lib/"` (files), `compgen -d` (dirs). For command-specific completions, need to source `bash-completion` lib, set `COMP_WORDS`/`COMP_CWORD`/`COMP_LINE`/`COMP_POINT` env vars, invoke the registered completion function, read `COMPREPLY` array.             | Medium — works but command-specific completions (e.g. `git checkout <branch>`) require loading the full bash-completion framework. |
| **zsh**  | No simple one-shot API. Completions are deeply tied to the ZLE (Zsh Line Editor) widget system. Programmatic access requires `zpty` (pseudo-terminal module): spawn a `zsh -f -i`, send the partial line + `\t`, capture output. This is how `fzf-tab` and similar tools work. Complex, brittle, and zsh-version-sensitive. | Hard — the zpty approach works but is fragile.                                                                                     |
| **fish** | `complete -C "git sta"` — purpose-built API, returns completions with descriptions. By far the cleanest interface.                                                                                                                                                                                                          | Easy — one command, clean output.                                                                                                  |

**Current architecture relevant to a fix:**

- `ShellConfig` in `lib/src/shell/shell_config.dart` already knows the user's shell executable and mode (interactive/login/non-interactive). The `_baseName` getter can distinguish bash/zsh/fish/pwsh.
- `LineEditor` already emits `InputAction.requestCompletion` on Tab.
- The app already has the overlay pattern (`SlashAutocomplete`, `AtFileHint`) for showing completion candidates.

**Possible approaches:**

1. **Simple: file/command completion only** — Use `compgen -f` (files) and `compgen -c` (commands) via bash regardless of user shell. Covers ~70% of use cases. Doesn't handle command-specific completions (git branches, docker containers, etc.).

2. **Medium: shell-aware `compgen` bridge** — Detect shell from `ShellConfig`. For bash, use `compgen` + source bash-completion. For fish, use `complete -C`. For zsh, fall back to approach 1 (or attempt zpty). New `ShellCompleter` class that takes a partial line and returns candidates.

3. **Full: pseudo-terminal passthrough** — Spawn a persistent interactive shell via `zpty`/`pty`, send partial input + tab, parse the response. Most accurate but extremely complex — need to handle ANSI output parsing, timing, and shell-specific escape sequences.

**Recommended:** Start with approach 2 — a `ShellCompleter` that uses `fish complete -C` for fish users and `bash -c 'compgen ...'` for everyone else. Wire it into the existing overlay system. Accept that zsh-specific completions (custom `_git` etc.) won't work initially.

**Relevant files for implementation:**

- `lib/src/shell/shell_config.dart` — already has shell detection
- `lib/src/input/line_editor.dart` — emits Tab as `requestCompletion`
- `lib/src/app.dart` lines ~648–660 — bash mode input handling
- `lib/src/ui/slash_autocomplete.dart` — pattern to follow for the overlay

# Bug Tracker

## BUG-001: Tool confirmation happens after LLM generates full content (wasteful tokens)

**Severity:** Medium (cost/UX)
**Component:** Agent tool confirmation flow
**Status:** Open

### Description

When the agent wants to use a tool that requires user confirmation (`write_file`, `edit_file`, `bash`), the LLM streams the **entire tool arguments** — including potentially hundreds of lines of file content — before the user is ever asked for permission. If the user declines, all those output tokens were generated and billed for nothing.

The tool **name** is known early (at `content_block_start`), but the confirmation prompt only appears after the full arguments have finished streaming (at `content_block_stop`). There is no mechanism to pause or cancel the stream between these two points.

### Example scenario

1. User: "Write a 500-line test file to test_foo.dart"
2. LLM starts streaming `write_file` tool call
3. `ToolCallStart` fires immediately with `name: "write_file"` — UI shows "preparing..."
4. LLM streams ~500 lines of file content as `input_json_delta` chunks (silent accumulation)
5. `content_block_stop` fires — full `ToolCallDelta` emitted
6. **NOW** the confirmation modal appears: "Approve tool: write_file?"
7. User presses "n" → all generated content wasted

### Code path

#### 1. LLM streaming: tool name known early, args buffered silently

`lib/src/llm/anthropic_client.dart:98-137`

```dart
case 'content_block_start':                          // ← tool NAME known here
  final block = event['content_block'] as Map<String, dynamic>;
  if (block['type'] == 'tool_use') {
    final id = block['id'] as String;
    final name = block['name'] as String;
    toolBuffers[index] = _ToolUseBuffer(id: id, name: name);
    yield ToolCallStart(id: id, name: name);         // ← early signal, no args yet
  }

case 'content_block_delta':
  // ...
  } else if (deltaType == 'input_json_delta') {
    toolBuffers[index]?.buffer.write(delta['partial_json']); // ← silent accumulation
  }

case 'content_block_stop':                           // ← all args finally available
  final buf = toolBuffers.remove(index);
  if (buf != null) {
    // ...parse accumulated JSON...
    yield ToolCallDelta(ToolCall(                     // ← first time full call is emitted
      id: buf.id, name: buf.name, arguments: args,
    ));
  }
```

The `ToolCallStart` (name only) fires immediately. The full `ToolCallDelta` (with all arguments) fires only after the entire content block has streamed. OpenAI and Ollama clients behave identically.

#### 2. AgentCore: yields events but has no cancel/pause mechanism

`lib/src/agent/agent_core.dart:238-256`

```dart
await for (final chunk in llm.stream(_conversation, tools: tools.values.toList())) {
  switch (chunk) {
    case ToolCallStart(:final id, :final name):
      yield AgentToolCallPending(id: id, name: name);   // ← early hint (name only)
    case ToolCallDelta(:final toolCall):
      toolCalls.add(toolCall);
      final completer = Completer<ToolResult>();
      _pendingToolResults[toolCall.id] = completer;
      toolFutures.add(completer.future);
      yield AgentToolCall(toolCall);                     // ← full call, triggers confirmation
  }
}
```

The `await for` loop consumes the entire stream sequentially. There is no backpressure or ability to signal "stop generating this tool call's arguments."

#### 3. App: confirmation only triggers on AgentToolCall (too late)

`lib/src/app.dart:1310-1319` — `AgentToolCallPending` just updates the UI spinner:

```dart
case AgentToolCallPending(:final id, :final name):
  _toolUi[id] = _ToolCallUiState(id: id, name: name);
  _blocks.add(_ConversationEntry.toolCallRef(id));
  _render();                                          // ← no confirmation check here
```

`lib/src/app.dart:1344-1369` — `AgentToolCall` checks auto-approval, shows modal if needed:

```dart
if (_autoApprovedTools.contains(call.name)) {         // ← auto-approved: skip modal
  unawaited(_executeAndCompleteTool(call));
  return;
}

// Show confirmation modal (too late — content already generated)
_activeModal = ConfirmModal(
  title: 'Approve tool: ${call.name}',
  bodyLines: call.arguments.entries.map((e) => '${e.key}: ${e.value}').toList(),
  // ...
);
```

#### 4. Auto-approved vs confirmation-required tools

`lib/src/app.dart:162-172`

```dart
final Set<String> _autoApprovedTools = {
  'read_file', 'list_directory', 'grep',
  'spawn_subagent', 'spawn_parallel_subagents',
  'web_fetch', 'web_search', 'web_browser', 'skill',
};
```

Tools NOT in this set (`write_file`, `edit_file`, `bash`) require confirmation — and are exactly the ones most likely to have large argument payloads.

### Prior art: how other agents handle this

All three major open-source coding agents have the **same architecture** — permission is checked after the LLM fully generates tool arguments. None cancel the stream early. This is an industry-wide gap.

#### OpenCode (sst/opencode)

- **Timing:** Permission checked AFTER args generated. The Vercel AI SDK's `execute()` callback is called with complete arguments, and `ctx.ask()` blocks on a Promise inside the callback.
- **Categorization:** Rule-based permission system with `allow`/`ask`/`deny` actions per tool, configurable per agent type (e.g., the "explore" agent is restricted to read-only tools).
- **Early cancellation:** None. The stream runs to completion. When permission is rejected, a `blocked` flag ends the agent loop after the current step.
- **Streaming:** `tool-input-delta` events are explicitly ignored (no-op `break`). A "pending" UI placeholder is created on `tool-input-start`, but full arguments only surface at the `tool-call` event.
- **Notable:** Denied tools are removed from the tool list entirely before sending to the LLM via `PermissionNext.disabled()`, which prevents the LLM from even attempting to call them.

#### Claude Code (anthropic/claude-code)

- **Timing:** Permission checked AFTER args generated. The full `tool_use` content block (including all file content) streams to completion, then the permission pipeline evaluates.
- **Categorization:** Three risk tiers: read-only (auto-approved), bash commands (prompt, "always" persists per-project), file modifications (prompt, "always" persists per-session). Five permission modes: `default`, `acceptEdits`, `plan`, `dontAsk`, `bypassPermissions`.
- **Early cancellation:** None. `PreToolUse` hooks receive the complete `tool_input` object — confirming the full content block has already been received.
- **Streaming:** Standard Anthropic streaming protocol. Full `tool_use` block finishes, then hooks → rules → modes → `canUseTool` callback are evaluated.
- **Notable:** The Anthropic API's `eager_input_streaming` feature allows seeing parameters as they stream, but Claude Code's permission system still evaluates the completed tool call, not partial input.

#### Ampcode (sourcegraph/amp)

- **Timing:** Permission checked AFTER args generated, before execution. Permission rules explicitly match on tool argument values (e.g., `--cmd 'git push*'`), which requires the arguments to already exist.
- **Categorization:** Rule-based with four actions: `allow`, `ask`, `reject`, `delegate` (forwards to external program). Three evaluation layers: user rules → built-in rules → default fallback. Sub-agents are more restricted (rejected if no rule matches vs. asked in main thread).
- **Early cancellation:** None. Full response is received before permission evaluation.
- **Streaming:** Text streams for display, but tool execution is post-response. The `--stream-json` output format is designed to be compatible with Claude Code's format.

#### Summary

| Agent           | Permission timing   | Early cancel? | Stream handling                   |
| --------------- | ------------------- | ------------- | --------------------------------- |
| **OpenCode**    | After args complete | No            | Ignores `tool-input-delta`        |
| **Claude Code** | After args complete | No            | Full block before hooks/rules     |
| **Ampcode**     | After args complete | No            | Full response before execution    |
| **Glue (ours)** | After args complete | No            | Silent buffer in `_ToolUseBuffer` |

All four tools waste output tokens when the user declines a tool call. The `ToolCallStart` / `content_block_start` event — which provides the tool name before arguments stream — is an unexploited intervention point across the entire ecosystem.

### Proposed fix direction

The earliest intervention point is `AgentToolCallPending` / `ToolCallStart`, which fires **before** arguments stream. A fix could:

1. When `AgentToolCallPending` arrives for a tool not in `_autoApprovedTools`, show a lightweight pre-confirmation: _"The model wants to use write_file. Allow?"_
2. If user declines: cancel the LLM stream (abort the HTTP connection), send `ToolResult.denied`, and avoid generating argument tokens entirely.
3. If user approves: let streaming continue and auto-approve the subsequent `AgentToolCall` when it arrives (since the user already consented).

This requires:

- A way for the app to signal `AgentCore` to cancel the current LLM stream mid-flight (e.g., cancel the `StreamSubscription` on the HTTP response).
- Tracking which tool calls have been "pre-approved" so the full `AgentToolCall` event can skip the modal.
- Handling edge cases: multiple tool calls in one response, text interleaved with tool calls, etc.

## BUG-002: `--resume` creates an empty session immediately

**Severity:** Medium (UX)
**Component:** Session resume flow
**Status:** Open

### Description

When launching glue with `--resume`, a new empty session is created before the user selects which session to resume. If the user then quits the tool (or the resume dialog is dismissed without selecting a session), this empty session persists in the session store.

This causes a poor experience with `--continue`: since `--continue` picks up the most recent session, it will resume the empty session created by the aborted `--resume` flow instead of the user's actual last working session.

### Expected behavior

- `--resume` should **not** create a new session until the resume dialog is dismissed without a selection (i.e., the user chooses to start a new session).
- If the user selects an existing session from the dialog, that session should be resumed — no new session created.
- If the user quits/cancels during the resume dialog, no session should be created at all.

### Impact

1. User runs `glue --resume`, browses the session list, then quits.
2. An empty session is now the most recent session.
3. User later runs `glue --continue` expecting to pick up their last real conversation.
4. Instead they get the empty session — confusing and requires manual session selection to recover.
