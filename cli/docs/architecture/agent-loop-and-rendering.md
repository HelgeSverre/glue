# Agent Loop & UI Rendering Architecture

This document describes how Glue's core agent loop and terminal UI rendering work together.

---

## 1. High-Level System Overview

The application is built around three independent subsystems that communicate through event streams:

```
┌─────────────┐    TerminalEvent     ┌─────────────┐     AgentEvent      ┌─────────────┐
│  Terminal    │ ──────────────────▶  │    App       │ ◀────────────────── │  AgentCore   │
│  (Raw I/O)  │                      │ (Controller) │ ──────────────────▶ │  (ReAct Loop)│
└─────────────┘                      └──────┬───────┘                     └──────────────┘
                                            │
                                     _render()
                                            │
                                     ┌──────▼───────┐
                                     │   Layout +   │
                                     │ BlockRenderer │
                                     └──────────────┘
```

- **Terminal** — owns raw stdin/stdout, parses bytes into `TerminalEvent`s (keys, chars, mouse, resize).
- **App** — the central controller. Subscribes to both terminal events and agent events, manages `AppMode` state transitions, and calls `_render()` after every state change.
- **AgentCore** — the LLM ↔ tool execution ReAct loop. Yields `AgentEvent`s as an `async*` stream.

---

## 2. Core Agent Loop (`AgentCore.run`)

The agent loop is a `while(true)` generator that implements the ReAct (Reasoning + Acting) pattern:

```
AgentCore.run(userMessage)
│
├─ 1. Add user message to conversation history
│
└─ while (true) ─────────────────────────────────────────────┐
   │                                                         │
   ├─ 2. Stream LLM response ──▶ llm.stream(messages, tools) │
   │   │                                                     │
   │   ├─ TextDelta ──────▶ yield AgentTextDelta(delta)      │
   │   ├─ ToolCallDelta ──▶ collect into toolCalls[]         │
   │   └─ UsageInfo ──────▶ accumulate token count           │
   │                                                         │
   ├─ 3. Add assistant message to history                    │
   │                                                         │
   ├─ 4. If no tool calls ──▶ break (turn complete)          │
   │                                                         │
   ├─ 5. Create Completers for each tool call                │
   │                                                         │
   ├─ 6. yield AgentToolCall(call) for each tool             │
   │      (App receives these, executes, calls               │
   │       completeToolCall() to resolve Completers)         │
   │                                                         │
   ├─ 7. await Future.wait(all tool futures)                 │
   │                                                         │
   ├─ 8. Add tool results to conversation history            │
   │                                                         │
   ├─ 9. yield AgentToolResult for each result               │
   │                                                         │
   └─ 10. Loop back to step 2 (send results to LLM) ────────┘

yield AgentDone()
```

### Key design decisions

- **Parallel tool execution** — Multiple tool calls from a single LLM turn create independent `Completer<ToolResult>`s that are awaited with `Future.wait`, allowing concurrent execution.
- **Decoupled approval** — The agent yields `AgentToolCall` and suspends. The App decides whether to auto-approve, show a modal, or deny. It calls `completeToolCall(result)` to resume the loop.
- **Generator-based** — The entire loop is an `async*` generator, so the App can cancel mid-stream by cancelling the `StreamSubscription`.

---

## 3. App State Machine

The App transitions between five modes that govern what input is accepted and what's shown in the status bar:

```
                    UserSubmit
         ┌──────────────────────────────┐
         ▼                              │
    ┌─────────┐   agent.run()    ┌──────┴────┐
    │  idle   │ ───────────────▶ │ streaming  │◀──────────────┐
    └────┬────┘                  └──┬──────┬──┘               │
         │                         │      │                   │
         │               AgentDone/│      │AgentToolCall      │
         │               AgentError│      │                   │
         │                         │      ▼                   │
         │                         │  ┌────────────┐   auto   │
         │                         │  │ confirming │──────────┤
         │                         │  └─────┬──────┘ approve  │
         │                         │        │                 │
         │                         │  Yes/  │  No             │
         │                         │ Always ▼  (denied)       │
         │                         │  ┌───────────┐           │
         │                         │  │toolRunning│───────────┘
         │                         │  └───────────┘ AgentToolResult
         │                         │
         │                         ▼
         │                    Back to idle
         │
         │   ! prefix (bash mode)
         ├──────────────────▶ ┌────────────┐
         │                   │ bashRunning │
         │                   └──────┬──────┘
         │                          │ process exits
         └──────────────────────────┘
```

### Mode behaviors

| Mode | Input handling | Status indicator |
|------|---------------|-----------------|
| `idle` | Full editor, slash commands, @file hints | `Ready` |
| `streaming` | Ctrl+C/Esc to cancel, pre-type buffer | `⠋ Generating` (spinner) |
| `toolRunning` | Ctrl+C/Esc to cancel | `⚙ Tool` |
| `confirming` | Modal captures Y/N/A keys | `? Approve` |
| `bashRunning` | Ctrl+C to kill process | `! Running` |

---

## 4. Event Flow: User Message to Rendered Output

Complete lifecycle of a user message through the system:

```
User types "explain this code" + Enter
│
├─ Terminal._parseInput(bytes)
│   └─ emit KeyEvent(Key.enter)
│
├─ App._handleTerminalEvent(KeyEvent.enter)
│   └─ editor.handle() → InputAction.submit
│       └─ _events.add(UserSubmit("explain this code"))
│
├─ App._handleAppEvent(UserSubmit)
│   └─ _startAgent("explain this code")
│       ├─ _blocks.add(ConversationEntry.user(...))
│       ├─ _mode = AppMode.streaming
│       ├─ _startSpinner()
│       └─ agent.run(message).listen(_handleAgentEvent)
│
├─ AgentCore.run("explain this code")  ← async* generator
│   ├─ LLM streams TextDelta chunks
│   │   └─ yield AgentTextDelta("Here is...")
│   │
│   └─ (if tool needed)
│       └─ yield AgentToolCall(readFile)
│
├─ App._handleAgentEvent(AgentTextDelta)
│   ├─ _streamingText += delta
│   └─ _render()  ← triggers UI update
│
├─ App._handleAgentEvent(AgentToolCall)
│   ├─ Flush _streamingText → _blocks
│   ├─ Auto-approved? → _executeAndCompleteTool()
│   │   └─ agent.completeToolCall(result) ← resumes generator
│   └─ Not auto? → show ConfirmModal
│       └─ user approves → _executeAndCompleteTool()
│
├─ App._handleAgentEvent(AgentDone)
│   ├─ Flush remaining _streamingText → _blocks
│   ├─ _stopSpinner()
│   ├─ _mode = AppMode.idle
│   └─ _render()
│
└─ Final render shows complete conversation
```

---

## 5. Terminal Layout System

The `Layout` class divides the terminal into four vertical zones using ANSI hardware scroll regions (`DECSTBM`):

```
Row 1    ┌──────────────────────────────────────────┐
         │                                          │
         │          Output Zone (scrollable)         │
         │     Conversation blocks rendered here     │
         │     Uses native terminal scrolling        │
         │                                          │
         ├──────────────────────────────────────────┤ ← outputBottom
         │       Overlay Zone (0–N lines)            │
         │   Autocomplete popup / @file hints        │
         ├──────────────────────────────────────────┤ ← statusRow
         │  Ready  claude-3.5  ~/project  tok 1234  │ ← Status Bar (1 line)
         ├──────────────────────────────────────────┤ ← inputTop
         │  ❯ _                                     │ ← Input Zone (1–N lines)
Row N    └──────────────────────────────────────────┘ ← inputBottom = terminal.rows
```

### Zone boundaries (1-indexed)

| Zone | Top | Bottom |
|------|-----|--------|
| Output | `1` | `rows - status - input - overlay` |
| Overlay | `outputBottom + 1` | `overlayTop + overlayHeight - 1` |
| Status | `rows - inputHeight` | same row |
| Input | `rows - inputHeight + 1` | `rows` |

The scroll region trick (`terminal.setScrollRegion(outputTop, outputBottom)`) lets the output zone scroll naturally while status bar and input stay pinned.

---

## 6. Render Pipeline (`_doRender`)

Every state change triggers `_render()`, which is throttled to ~60fps (16ms minimum interval):

```
_render()
│
├─ Throttle check (< 16ms since last?) → schedule deferred
│
└─ _doRender()
   │
   ├─ 1. Build output lines from _blocks[]
   │      for each ConversationEntry:
   │        switch (kind):
   │          user      → BlockRenderer.renderUser(text)
   │          assistant → BlockRenderer.renderAssistant(text)  ← includes Markdown
   │          toolCall  → BlockRenderer.renderToolCall(name, args)
   │          toolResult→ BlockRenderer.renderToolResult(content)
   │          error     → BlockRenderer.renderError(message)
   │          bash      → BlockRenderer.renderBash(command, output)
   │          subagent  → BlockRenderer.renderSubagent(text)
   │          system    → BlockRenderer.renderSystem(text)
   │
   ├─ 2. Append streaming text (if any)
   │      _streamingText → renderAssistant() → append to outputLines
   │
   ├─ 3. Append confirm modal (if active)
   │      _activeModal.render() → append to outputLines
   │
   ├─ 4. Panel modal check (takes over full viewport)
   │      if panelActive → render panel grid, return early
   │
   ├─ 5. Reserve overlay space
   │      layout.setOverlayHeight(autocomplete or @file height)
   │
   ├─ 6. Compute visible window (viewport + scroll offset)
   │      firstLine = totalLines - viewportHeight - scrollOffset
   │      visibleLines = outputLines[firstLine..endLine]
   │
   ├─ 7. Paint zones:
   │      layout.paintOutputViewport(visibleLines)   ← Output
   │      layout.paintOverlay(autocomplete/atHint)   ← Overlay
   │      layout.paintStatus(left, right)            ← Status bar
   │      layout.paintInput(prompt, text, cursor)    ← Input (LAST for cursor)
   │
   └─ Done — cursor lands in input area
```

### BlockRenderer

The `BlockRenderer` converts `_ConversationEntry` objects into ANSI-styled strings. It reserves a 1-character margin on each side and delegates markdown content to `MarkdownRenderer`:

```
BlockRenderer(terminalWidth)
│
├─ renderUser(text)      → "❯ You\n   wrapped text"
├─ renderAssistant(text) → "◆ Glue\n   markdown rendered"
├─ renderToolCall(name)  → "▶ Tool: name\n   args"
├─ renderToolResult()    → "✓ Tool result\n   truncated output"
├─ renderError(msg)      → "✗ Error\n   red message"
├─ renderBash(cmd, out)  → boxed output with ┌─command─┐ border
└─ renderSystem(text)    → dimmed gray text
```

---

## 7. Input Processing Pipeline

Keyboard input flows through a priority chain of interceptors before reaching the line editor:

```
Terminal.events (raw bytes → TerminalEvent)
│
└─ App._handleTerminalEvent
   │
   ├─ 1. PanelModal (full-screen overlay, e.g. /help, /resume)
   │      if active → panel.handleEvent() → consume or pass
   │
   ├─ 2. ConfirmModal (inline Y/N/A approval prompt)
   │      if active → modal.handleEvent() → consume or pass
   │
   ├─ 3. Scroll handling (PageUp/PageDown — always active)
   │
   ├─ 4. Bash mode toggle (! prefix at cursor 0)
   │
   ├─ 5. Streaming/running guard
   │      if streaming/toolRunning/bashRunning:
   │        Ctrl+C/Esc → cancel
   │        Enter → swallow
   │        other → buffer in editor (pre-typing)
   │
   ├─ 6. SlashAutocomplete (when "/" typed)
   │      Up/Down → navigate, Tab/Enter → accept, Esc → dismiss
   │
   ├─ 7. AtFileHint (when "@" typed)
   │      Up/Down → navigate, Tab/Enter → accept, Esc → dismiss
   │
   └─ 8. LineEditor (normal editing)
         handle(event) → InputAction
         │
         ├─ submit → UserSubmit(text) → agent or slash command
         ├─ interrupt → double Ctrl+C detection → exit
         ├─ changed → update autocomplete/atHint → _render()
         └─ none → no-op
```

---

## 8. LLM Client & Streaming Architecture

Three LLM providers implement the `LlmClient` interface, each with different streaming formats:

```
           LlmClient (abstract)
           Stream<LlmChunk> stream(messages, tools)
                    │
        ┌───────────┼───────────────┐
        ▼           ▼               ▼
  Anthropic      OpenAI          Ollama
  Client         Client          Client
    │               │               │
    ▼               ▼               ▼
  SSE decoder    SSE decoder    NDJSON decoder
    │               │               │
    ▼               ▼               ▼
  TextDelta      TextDelta      TextDelta
  ToolCallDelta  ToolCallDelta  ToolCallDelta
  UsageInfo      UsageInfo      UsageInfo
```

### Streaming decoders

- **SSE** (`sse.dart`) — Transforms `Stream<List<int>>` into Server-Sent Events. Handles multi-byte UTF-8 boundaries and `[DONE]` sentinels. Used by Anthropic and OpenAI.
- **NDJSON** (`ndjson.dart`) — Transforms `Stream<List<int>>` into line-delimited JSON objects. Used by Ollama.

### Chunk types (`LlmChunk`)

| Type | Purpose |
|------|---------|
| `TextDelta` | Incremental text from the model |
| `ToolCallDelta` | A complete tool call (id, name, arguments) |
| `UsageInfo` | Token usage statistics (input + output) |

---

## 9. Subagent System

The `AgentManager` orchestrates subagent execution. Each subagent gets its own `AgentCore` with independent conversation history but shared tools:

```
App (main agent)
│
├─ AgentCore (main)
│   └─ ToolCall: spawn_subagent(task)
│
├─ AgentManager.spawnSubagent(task)
│   │
│   ├─ Create new LlmClient (can use different model)
│   ├─ Create new AgentCore with shared tools
│   ├─ Wrap in AgentRunner (headless, allowlist policy)
│   │
│   └─ runner.runToCompletion(task)
│       │
│       ├─ AgentCore.run() loop (same as main)
│       │   ├─ TextDelta → buffer
│       │   ├─ ToolCall → auto-approve if in allowlist
│       │   └─ Done → return concatenated text
│       │
│       └─ onEvent callback → SubagentUpdate
│           └─ AgentManager._updateController
│               └─ App._handleSubagentUpdate()
│                   └─ Update _SubagentGroup in _blocks
│                       └─ _render() (collapsible UI group)
│
├─ Parallel subagents: Future.wait([
│     spawnSubagent(task1, index: 0),
│     spawnSubagent(task2, index: 1),
│     spawnSubagent(task3, index: 2),
│   ])
│
└─ Depth limiting: maxSubagentDepth prevents infinite recursion
```

### Subagent tool approval

| Policy | Behavior |
|--------|----------|
| `autoApproveAll` | All tools run without checking |
| `denyAll` | All tool calls are denied |
| `allowlist` | Only tools in `safeSubagentTools` run (`read_file`, `list_directory`, `grep`) |

---

## 10. Tool Approval Flow

When the agent requests a tool call, the App determines the approval path:

```
AgentToolCall received
│
├─ Tool in _autoApprovedTools?
│   ├─ YES → _executeAndCompleteTool(call)
│   │         └─ agent.executeTool(call) → ToolResult
│   │             └─ agent.completeToolCall(result)
│   │                 └─ Resumes AgentCore.run() generator
│   │
│   └─ NO → Show ConfirmModal
│            │
│            ├─ "Yes" (y) → execute tool, resume
│            ├─ "No" (n) → ToolResult.denied → resume
│            └─ "Always" (a) → add to _autoApprovedTools
│                               + persist to config
│                               → execute tool, resume
```

### Auto-approved tools (default)

- `read_file`, `list_directory`, `grep` — read-only operations
- `spawn_subagent`, `spawn_parallel_subagents` — delegated execution

---

## 11. Session Persistence

The `SessionStore` logs conversation events to disk for session resume:

```
~/.glue/sessions/<session-id>/
├── meta.json           ← SessionMeta (id, cwd, model, provider, startTime)
├── conversation.jsonl  ← Append-only event log
│     {"type": "user_message", "text": "..."}
│     {"type": "assistant_message", "text": "..."}
│     {"type": "tool_call", "name": "...", "arguments": {...}}
└── state.json          ← SessionState (docker mounts, etc.)
```

Resume flow: `/resume` → PanelModal listing → select session → `_resumeSession()` → replay events into `AgentCore._conversation` and `_blocks`.

---

## 12. Double-Buffer Rendering (ScreenBuffer)

The `ScreenBuffer` provides flicker-free rendering through a double-buffered virtual terminal grid:

```
Frame N                          Frame N+1

┌─────────────┐                 ┌─────────────┐
│ H e l l o   │  ← _previous   │ H e l l o   │  ← _current
│ W o r l d   │                 │ D a r t !   │
└─────────────┘                 └─────────────┘

flush():
  Compare cell-by-cell:
    Row 1: identical → skip
    Row 2: differs → emit ANSI move + write "Dart! "

  Swap buffers:
    _previous = _current (becomes reference)
    _current  = cleared  (ready for next frame)
```

Each `Cell` stores a character + optional `AnsiStyle`. Only changed cells produce ANSI output, eliminating flicker even at high refresh rates.
