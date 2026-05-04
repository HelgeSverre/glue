# Ask User Tool Plan

> Status: design / planning only. No code changes in this plan.
> Re-spec'd 2026-04-30 against the harness/strategies/core split.

## Goal

Add an `ask_user` tool to Glue as a first-class blocking clarification primitive in the agent loop.

Unlike a normal assistant message that asks a question in plain chat, `ask_user` should:

1. be exposed to the model as a normal tool
2. suspend autonomous execution when invoked
3. switch the surface into a dedicated "waiting for structured user reply" state
4. collect the reply via the surface (CLI inline, ACP `session/request_user_input`)
5. feed that reply back into the transcript as the tool result for that specific tool call
6. resume the same in-flight agent turn

This gives Glue the same basic control-flow shape as a synchronous human-input syscall inside the current turn.

## How this plan relates to the harness layers

`ask_user` looks like an interactive UI feature, but architecturally it's almost entirely a harness contract: the agent loop pauses on a typed event and waits for a typed command. That's exactly the same shape as `PermissionRequestedEvent` / `ResolvePermissionCommand`, which already landed in `glue_core/session_event.dart` and `session_command.dart`.

Layer placement:

- **`glue_core`**: two new typed types in `session_event.dart` /
  `session_command.dart`:
  - `UserInputRequestedEvent`
  - `ResolveUserInputCommand`
  Both keyed by `ToolCallId` (typed wrapper from `glue_core/ids.dart`).
- **`glue_harness`**:
  - the `AskUserTool` registration (it is a real `Tool` so the model sees a schema, but its `execute()` is intercepted before normal dispatch)
  - an `AskUserGate` (analogous to `PermissionGate`, ~50 lines) that
    converts the agent's tool call into a `UserInputRequestedEvent` and
    waits for `ResolveUserInputCommand` to complete the call.
  - special-casing in `AgentRunner` (headless) and the `AgentManager`
    subagent path to fail fast.
  - prompt guidance update (`prompts.dart`).
- **Surfaces** (`cli`, `glue_server`):
  - CLI shows an inline prompt panel and dispatches `ResolveUserInputCommand` on submit.
  - ACP server maps `UserInputRequestedEvent` → ACP `session/request_user_input` (mirroring how it already maps `PermissionRequestedEvent` → `session/request_permission`).

The bottom line: there is **one harness contract**, and surfaces implement
the UI in their own native idiom.

## Why this is useful in Glue

Glue already has a strong tool-driven ReAct loop:

- model streams text and tool calls via `AgentCore` (in `glue_harness`)
- the surface decides how to handle each tool call (gate via
  `PermissionGate`, then dispatch)
- tool results are injected back into the same conversation turn
- the loop resumes without starting a new top-level user turn

That architecture is already very close to what `ask_user` needs.

Today, when the model needs clarification, it has to fall back to:

1. ask in plain assistant text and implicitly hope the user replies in a way that restarts the task correctly
2. guess and continue autonomously

`ask_user` lets the model pause mid-task for one missing decision without collapsing the current turn — and works identically for CLI and ACP clients.

## User-facing behavior

The intended behavior, from the agent's perspective, is:

1. user starts a task
2. model begins working
3. model emits `ask_user({ question, choices?, allow_freeform? })`
4. harness emits a `UserInputRequestedEvent`
5. surface renders a structured prompt
6. surface dispatches `ResolveUserInputCommand` with the answer
7. harness completes the tool call with the answer as the tool result
8. the model resumes the same task

## Proposed tool contract

### Input schema

```json
{
  "question": "string",
  "choices": ["string"],
  "allow_freeform": true
}
```

### Parameters

- `question: string` — required, non-empty after trim
- `choices?: string[]` — optional quick-pick labels
- `allow_freeform?: boolean` — optional, default `true`

### Validation rules

Glue should enforce these invariants before presenting the prompt:

1. `question` must be non-empty after trim
2. `choices`, if present, must not be empty strings
3. if `allow_freeform == false`, then `choices` must be non-empty
4. cap the number of choices for ergonomic key selection (2–9)
5. cap maximum question/choice length for rendering sanity

Invalid arguments produce a normal failed `ToolResult`, not a runtime crash. Validation lives in the harness's `AskUserGate` so all surfaces share the contract.

### Result payload

For the first iteration, the tool result returned to the model is the final answer text only. Examples:

- selected choice: `"tag and publish notes"`
- typed freeform answer: `"Use the existing changelog draft, but bump to v0.1.1"`

That fits Glue's current `ToolResult.content: String` contract (`glue_core/tool.dart`) cleanly.

### Optional future structured result

A future version could attach metadata via `ToolResult.metadata`: `source: choice | freeform`, `choice_index`, `cancelled: true`. The LLM-facing `content` stays simple text.

## Mental model

```text
ask_user = blocking tool that obtains one human decision and resumes the same turn
```

It is not a slash command. It is not a top-level CLI command. It is not equivalent to the assistant emitting plain prose. It is a tool-mediated pause inside the existing turn, mediated by a typed harness contract.

## Harness contract — typed event + command

In `packages/glue_core/lib/src/session_event.dart`:

```dart
class UserInputRequestedEvent extends SessionEvent {
  final ToolCallId callId;
  final String question;
  final List<String> choices;
  final bool allowFreeform;
  // ... base fields: turnId, sequence, timestamp
  const UserInputRequestedEvent({...});
}
```

In `packages/glue_core/lib/src/session_command.dart`:

```dart
class ResolveUserInputCommand extends SessionCommand {
  final ToolCallId callId;
  final String? answer;          // null when cancelled
  final bool cancelled;
  const ResolveUserInputCommand({
    required this.callId,
    this.answer,
    this.cancelled = false,
  });
}
```

This mirrors the `PermissionRequestedEvent` / `ResolvePermissionCommand`
pair that already exists. Surfaces just need to listen and dispatch.

## How this fits Glue's current architecture

### Existing loop (in `packages/glue_harness/lib/src/agent/agent_core.dart`)

1. `AgentCore.run()` sends conversation to the model
2. streamed tool calls yield `AgentToolCall`
3. surface decides how to handle the tool call
4. surface eventually calls `agent.completeToolCall(result)`
5. `AgentCore` appends a `Message.toolResult(...)`
6. loop continues

That is exactly the shape needed for `ask_user`.

### Key implication

`ask_user` does **not** require a special new transcript primitive. At the
conversation level it remains:

1. assistant message with tool call
2. tool result message with answer text

The main work is in:

- tool definition (harness)
- `AskUserGate` to translate agent tool call ↔ surface event/command (harness)
- typed event/command pair (core)
- surface UI for collecting input (CLI + ACP server, independently)
- headless/subagent policy (harness)
- session replay/rendering (mostly free, since the underlying tool_call/tool_result is already persisted)

## Proposed runtime state machine

```text
RUNNING
  -> model emits ask_user tool call

ASKING_USER (harness state)
  -> AskUserGate validates args
  -> emit UserInputRequestedEvent on session.events()
  -> harness keeps the tool's Completer<ToolResult> open

WAITING_FOR_REPLY (surface state)
  -> CLI: render inline prompt panel, route input
  -> ACP: forward as session/request_user_input

RESUMING
  -> surface dispatches ResolveUserInputCommand
  -> AskUserGate completes the tool call with the answer
  -> harness resumes the streaming loop

RUNNING
  -> same agent turn continues
```

### Cancel path

`ResolveUserInputCommand(cancelled: true)`:

- harness completes the tool call with a synthetic failed `ToolResult` (`success: false`, `content: '[cancelled by user]'`) so the transcript stays structurally valid
- harness then cancels the in-flight turn (same path as today's `InterruptCommand`)
- surface returns to idle

This matches Glue's current cancel mental model. CLI binds Esc to dispatch `ResolveUserInputCommand(cancelled: true)`; ACP exposes the same as a documented response.

## Proposed implementation shape

### 1. Add a real `AskUserTool`

**File:** `packages/glue_harness/lib/src/tools/ask_user_tool.dart`

It should:

- expose schema/name/description to the model (so the model sees it like any other tool)
- **not** actually block inside `execute()` — that path is the safety net for misuse only

`execute()` returns an error like:

```
Error: ask_user must be handled by interactive orchestration
```

This makes accidental misuse in unsupported contexts obvious.

### 2. Register the tool

**File:** `packages/glue_harness/lib/src/core/service_locator.dart`

Add `'ask_user': AskUserTool()` to the registry.

### 3. Add `AskUserGate` in the harness

**File:** `packages/glue_harness/lib/src/orchestrator/ask_user_gate.dart` (new)

Sibling of `permission_gate.dart`. ~50 lines. Responsibilities:

- detect `call.name == 'ask_user'` before normal permission/dispatch
- validate arguments
- emit `UserInputRequestedEvent` on the harness's event sink
- park the tool's completer keyed by `ToolCallId`
- on `ResolveUserInputCommand`, complete the parked completer with a `ToolResult`

This is the only harness code that needs to know about ask-user semantics.
Everything else just observes events.

### 4. Update `AgentCore` to route ask-user calls through the gate

**File:** `packages/glue_harness/lib/src/agent/agent_core.dart`

Where `AgentToolCall` is currently dispatched, branch on `call.name == 'ask_user'` before the permission gate. Hand off to `AskUserGate.handle(call)`.

`ask_user` **bypasses** `PermissionGate` — it is itself a user-input mechanism, not a capability escalation.

### 5. Surface implementation — CLI

**Files:**

- `cli/lib/src/app/agent_orchestration.dart` — observe `UserInputRequestedEvent` from `session.events()`, switch to `AppMode.askingUser`, build `_AskUserUiState`
- `cli/lib/src/app.dart` — add `AppMode.askingUser`
- `cli/lib/src/app/models.dart` — add `_AskUserUiState`, add `_ToolPhase.awaitingUserInput`
- `cli/lib/src/app/terminal_event_router.dart` — route keyboard input for ask-user mode (Up/Down/Enter/Esc/typed chars)
- `cli/lib/src/app/render_pipeline.dart` — render active ask-user prompt
- `cli/lib/src/rendering/block_renderer.dart` — render tool phase label for awaiting user input

`_AskUserUiState`:

```dart
class _AskUserUiState {
  final ToolCallId callId;
  final String question;
  final List<String> choices;
  final bool allowFreeform;
  int selectedIndex;
  final TextAreaEditor freeformEditor;  // dedicated, not main editor
}
```

CLI dispatches `ResolveUserInputCommand` on submit/cancel. No CLI code calls `agent.completeToolCall` directly — that's the harness's job, triggered by the command.

Minimal v1 UI behavior:

- if `choices.isNotEmpty`:
  - Up/Down: choose highlighted option
  - Enter: submits highlighted option when freeform buffer is empty
  - any typed character: enters freeform mode when `allow_freeform == true`
  - Enter: submits freeform buffer if it contains text
- if no choices: freeform-only prompt using the dedicated editor
- Esc: dispatch `ResolveUserInputCommand(cancelled: true)`

### 6. Surface implementation — ACP server

**Files:**

- `packages/glue_server/lib/src/acp/event_mapper.dart` (or equivalent) — map `UserInputRequestedEvent` → ACP `session/request_user_input` notification
- `packages/glue_server/lib/src/acp/command_mapper.dart` — map ACP `session/respond_user_input` → `ResolveUserInputCommand`

The ACP-side schema mirrors the existing `session/request_permission` flow.

### 7. Render the ask-user prompt inline (CLI)

Recommended v1 rendering: keep the normal transcript block for the tool call; additionally render an active prompt panel near the input area as a special inline block:

```text
? Clarification needed
  Which action did you mean?
  > tag only
    tag and publish notes
    dry run

  Or type your answer...
```

Done in `cli/lib/src/app/render_pipeline.dart` without introducing a brand-new modal type. `ConfirmModal` is too narrow (assumes yes/no, no freeform editor).

## Headless and subagent behavior

`AgentRunner` and subagents are headless by design. A blocking human-input tool cannot work unchanged there.

### Headless `AgentRunner` (in `glue_harness`)

If the model calls `ask_user`:

- do **not** block forever
- return a denied/unsupported `ToolResult`:
  - `"ask_user is unavailable in headless mode; proceed without clarification"`

Implemented as a special case in `AgentRunner._handleToolCall()`.

### Subagents (in `glue_harness/lib/src/agent/agent_manager.dart`)

Same policy initially: return a failed `ToolResult` with content `"User input is unavailable in subagents"`.

Bubbling subagent questions up to the parent UI is possible eventually but adds substantial orchestration complexity. Phase 2.

## Prompting / usage guidance for models

Update `packages/glue_harness/lib/src/agent/prompts.dart` so the model knows:

- use `ask_user` when one missing decision blocks progress
- ask one focused question at a time
- prefer choices for bounded decisions
- set `allow_freeform: false` when the reply must be constrained
- avoid asking questions that can be answered by reading the repo/config
- do not use `ask_user` for ordinary narration or status updates
- only one `ask_user` call may be pending at a time

## Session persistence and replay

Glue already logs `tool_call` and `tool_result` as `SessionEvent` variants
in `glue_core`. `ask_user` mostly fits existing session machinery — the
extra `UserInputRequestedEvent` is just session state that surfaces
observe; it doesn't need to re-derive the answer on resume because the
final `ToolResult` already encodes it.

### Optional enhancement

For replay/UI fidelity, persist `UserInputRequestedEvent` and a future
`UserInputResolvedEvent` so the rendered transcript can distinguish
ask-user replies from other tool results visually. Not required for
transcript correctness.

## Message mapping implications

No fundamental provider protocol changes required. `glue_strategies/llm/message_mapper.dart` already maps assistant tool calls and tool results to provider-specific structures. The only change is that the `ask_user` tool now appears in the advertised tool list.

## Suggested file-by-file changes

### Core (`glue_core`)

#### New
- (extend existing files; no new files)

#### Modified
- `packages/glue_core/lib/src/session_event.dart` — add `UserInputRequestedEvent`
- `packages/glue_core/lib/src/session_command.dart` — add `ResolveUserInputCommand`

### Harness (`glue_harness`)

#### New
- `packages/glue_harness/lib/src/tools/ask_user_tool.dart`
- `packages/glue_harness/lib/src/orchestrator/ask_user_gate.dart`

#### Modified
- `packages/glue_harness/lib/src/core/service_locator.dart` — register tool + gate
- `packages/glue_harness/lib/src/agent/agent_core.dart` — route ask-user calls through gate before permission gate
- `packages/glue_harness/lib/src/agent/agent_runner.dart` — special-case `ask_user` as unsupported in headless mode
- `packages/glue_harness/lib/src/agent/agent_manager.dart` — same for subagents
- `packages/glue_harness/lib/src/agent/prompts.dart` — usage guidance
- `packages/glue_harness/lib/glue_harness.dart` — barrel exports for new types

### CLI surface (`cli/`)

#### Modified
- `cli/lib/src/app.dart` — add `AppMode.askingUser`
- `cli/lib/src/app/models.dart` — `_AskUserUiState`, `_ToolPhase.awaitingUserInput`
- `cli/lib/src/app/agent_orchestration.dart` — observe event, dispatch command
- `cli/lib/src/app/terminal_event_router.dart` — keyboard routing
- `cli/lib/src/app/render_pipeline.dart` — render prompt panel
- `cli/lib/src/rendering/block_renderer.dart` — tool phase label

### ACP server (`glue_server/`)

#### Modified
- `packages/glue_server/lib/src/acp/` — map event ↔ ACP request, document the schema; mirror existing `session/request_permission` plumbing

## Tests

### Core

- `packages/glue_core/test/session_event_test.dart` — `UserInputRequestedEvent` round-trips JSON
- `packages/glue_core/test/session_command_test.dart` — `ResolveUserInputCommand` shape

### Harness

- `packages/glue_harness/test/orchestrator/ask_user_gate_test.dart` —
  - emits `UserInputRequestedEvent` with correct fields
  - completes tool call on `ResolveUserInputCommand`
  - completes tool call as cancelled on `cancelled: true`
  - rejects malformed args with a failed `ToolResult`
  - rejects multiple concurrent ask-user calls deterministically
- `packages/glue_harness/test/agent/agent_core_test.dart` — `ask_user` bypasses `PermissionGate`
- `packages/glue_harness/test/agent/agent_runner_test.dart` — headless returns unsupported result, does not hang
- `packages/glue_harness/test/agent/agent_manager_test.dart` — subagent same policy

### CLI surface

- `cli/test/app/ask_user_orchestration_test.dart` — observes event → switches mode; dispatches command on submit/cancel
- `cli/test/app/terminal_event_router_test.dart` — keys behave per spec
- `cli/test/rendering/block_renderer_test.dart` — awaiting-user-input phase rendering

### ACP server

- `packages/glue_server/test/acp/user_input_mapping_test.dart` — event → ACP notification, ACP response → command

### Integration

At least one scripted CLI-level test covering:

1. model emits text + `ask_user`
2. user selects a choice
3. model receives tool result and continues
4. final transcript order: user → assistant text → assistant tool call → tool result → assistant continuation

## Detailed behavior recommendations

### Tool schema description

```text
Pause execution and ask the user one focused clarification question.
Use this when one missing decision blocks progress and cannot be inferred
safely. Optionally provide choices for quick selection.
```

### Choice handling

When choices are present and user selects one, return the selected string label as `ToolResult.content`. Do not return an index in v1.

### Freeform handling

If `allow_freeform == true` and user typed text:

- submit exact typed text after trim
- if trimmed text is empty, fall back to selected choice if available
- if no choice and no text, keep waiting

If `allow_freeform == false`: ignore character input; only allow choice navigation.

### Approval interaction

`ask_user` bypasses `PermissionGate`. It is itself a user-input mechanism; asking permission to ask the user would be redundant. Handle in the harness, before the permission gate.

### Observability

`AskUserGate` should emit a `tool.ask_user` span via `ObservabilityHub` capturing:

- `ask_user.wait_ms`
- `ask_user.choice_count`
- `ask_user.allow_freeform`
- `ask_user.answer_source` (choice / freeform / cancelled)

Optional for v1, fits Glue's existing observability model.

## Risks and edge cases

### 1. Draft preservation

Use a dedicated ask-user editor state, not `app.editor`. Don't clobber the user's main draft.

### 2. Multiple concurrent `ask_user` calls

Support only one active `ask_user` at a time. If the model emits multiple `ask_user` calls in the same batch, `AskUserGate` processes the first and fails the rest with `"Only one ask_user call may be pending at a time"`. Document in prompt guidance.

### 3. Interaction with normal assistant text

A model may emit explanatory text and then `ask_user` in the same assistant response. Works naturally because Glue already flushes accumulated assistant text before rendering tool UI.

### 4. Resume/fork correctness

Transcript remains standard assistant tool call + tool result; resume/fork stays structurally valid. Cancelled ask-user flows leave behind matching tool results (existing cancellation repair handles this).

### 5. Provider differences

No major provider-specific issues expected.

## Suggested phased implementation

### Phase 1 — Interactive main-agent support

1. Add typed `UserInputRequestedEvent` / `ResolveUserInputCommand` in `glue_core`.
2. Add `AskUserTool` and `AskUserGate` in `glue_harness`.
3. Route in `AgentCore`.
4. Implement CLI surface (mode, state, routing, rendering).
5. Update prompt guidance.

#### Acceptance criteria

- model can call `ask_user`
- CLI pauses current turn and shows question
- user can answer with choice or text as allowed
- answer is injected as tool result
- same turn resumes and completes

### Phase 2 — Headless, subagent, ACP

1. Make `AgentRunner` explicitly reject `ask_user`.
2. Make subagents reject `ask_user`.
3. Map `UserInputRequestedEvent` ↔ ACP in `glue_server`.

#### Acceptance criteria

- headless runs never block forever on `ask_user`
- subagents receive deterministic failure behavior
- ACP clients can drive ask-user flows end-to-end

### Phase 3 — UX refinement

1. Rendering polish.
2. Optional answer-source metadata / observability.
3. Better cancel messaging.
4. Distinguish ask-user replies from ordinary tool results in replay/transcript views.

## Open questions

1. **Should `ask_user` be available to subagents eventually?** — Recommendation: not in v1.
2. **Should cancel return a tool result to the model, or hard-abort without resume?** — Recommendation: create matching failed `ToolResult`, then abort the turn.
3. **Should freeform input be allowed when choices exist by default?** — Recommendation: yes, controlled by `allow_freeform`.
4. **Should the result be plain text or JSON?** — Recommendation: plain text in `content`, optional metadata later.
5. **Should `ask_user` use modal UI or inline UI?** — Recommendation: inline / lightweight dedicated prompt region first.

## Acceptance criteria summary

This plan is complete when:

1. `ask_user` is exposed as a built-in tool in `glue_harness`
2. `glue_core` defines typed `UserInputRequestedEvent` + `ResolveUserInputCommand`
3. CLI pauses and waits for a structured answer when `ask_user` is called
4. ACP clients see a `session/request_user_input` notification with the same shape
5. The answer is returned as the `ToolResult` for that tool call
6. The same agent turn resumes afterward
7. `ask_user` bypasses normal permission approval flow
8. Headless/subagent contexts fail deterministically instead of hanging
9. Session transcripts remain structurally valid across submit, cancel, resume, and replay
