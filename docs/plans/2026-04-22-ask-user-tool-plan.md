# Ask User Tool Plan

> Status: design / planning only. No code changes in this plan.

## Goal

Add an `ask_user` tool to Glue as a first-class blocking clarification primitive in the agent loop.

Unlike a normal assistant message that asks a question in plain chat, `ask_user` should:

1. be exposed to the model as a normal tool
2. suspend autonomous execution when invoked
3. switch the app into a dedicated “waiting for structured user reply” state
4. collect the reply via the TUI
5. feed that reply back into the transcript as the tool result for that specific tool call
6. resume the same in-flight agent turn

This gives Glue the same basic control-flow shape as a synchronous human-input syscall inside the current turn.

## Why this is useful in Glue

Glue already has a strong tool-driven ReAct loop:

- model streams text and tool calls via `AgentCore`
- the app executes tools or asks for approval in `app/agent_orchestration.dart`
- tool results are injected back into the same conversation turn
- the loop resumes without starting a new top-level user turn

That architecture is already very close to what `ask_user` needs.

Today, when the model needs clarification, it has to fall back to one of two weaker patterns:

1. ask in plain assistant text and implicitly hope the user replies in a way that restarts the task correctly
2. guess and continue autonomously

Both are worse than a blocking tool because they lose explicit control-flow semantics.

`ask_user` would let the model pause mid-task for one missing decision without collapsing the current turn.

## User-facing behavior

The intended behavior is:

1. user starts a task
2. model begins working
3. model emits `ask_user({ question, choices?, allow_freeform? })`
4. Glue renders a structured prompt in the TUI
5. the current turn pauses
6. the user picks an option or enters text
7. Glue completes that tool call with the selected/typed answer as the tool result
8. the model resumes the same task

Conceptually:

```text
User: "ship the release"

Assistant -> tool call:
ask_user({
  question: "Which release action do you want?",
  choices: ["tag only", "tag and publish notes", "dry run"],
  allow_freeform: false,
})

Tool result:
"tag and publish notes"

Assistant:
"Got it — I’ll prepare the tag and release notes..."
```

## Proposed tool contract

The tool contract should match the shape described in the prompt, with one small Glue-specific clarification around result content.

### Input schema

```json
{
  "question": "string",
  "choices": ["string"],
  "allow_freeform": true
}
```

### Parameters

- `question: string` — required
  - one focused clarification question
- `choices?: string[]` — optional
  - quick-pick labels rendered by the UI
- `allow_freeform?: boolean` — optional, default `true`
  - when `true`, user may pick a choice or type another answer
  - when `false`, user must pick one of the provided choices

### Validation rules

Glue should enforce these invariants before presenting the prompt:

1. `question` must be non-empty after trim
2. `choices`, if present, must not be empty strings
3. if `allow_freeform == false`, then `choices` must be non-empty
4. optionally cap the number of choices shown in TUI, e.g. 2–9 for ergonomic key selection
5. optionally cap maximum question/choice length for rendering sanity

Invalid arguments should produce a normal failed tool result, not a runtime crash.

### Result payload

For the first iteration, the tool result returned to the model should be the final answer text only.

Examples:

- selected choice: `"tag and publish notes"`
- typed freeform answer: `"Use the existing changelog draft, but bump to v0.1.1"`

That fits Glue’s current `ToolResult.content: String` contract cleanly.

### Optional future structured result

A future version could return structured metadata in `ToolResult.metadata`, for example:

- `source: choice | freeform`
- `choice_index`
- `cancelled: true`

But the LLM-facing `content` should still stay simple text.

## Mental model

The cleanest mental model is:

```text
ask_user = blocking tool that obtains one human decision and resumes the same turn
```

It is not a slash command.
It is not a top-level CLI command.
It is not equivalent to the assistant emitting plain prose.

It is a tool-mediated pause inside the existing turn.

## How this fits Glue’s current architecture

Glue already has the right mechanical pieces.

### Existing loop

In `cli/lib/src/agent/agent_core.dart`:

1. `AgentCore.run()` sends conversation to the model
2. streamed tool calls yield `AgentToolCall`
3. app decides how to handle the tool call
4. app eventually calls `agent.completeToolCall(result)`
5. `AgentCore` appends a `Message.toolResult(...)`
6. loop continues

That is exactly the shape needed for `ask_user`.

### Key implication

`ask_user` does **not** require a special new transcript primitive.

At the conversation level it can remain:

1. assistant message with tool call
2. tool result message with answer text

The main work is in:

- tool definition
- agent/app suspension semantics
- TUI state/input routing
- headless/subagent policy
- session replay/rendering

## Proposed runtime state machine

Glue should model this explicitly.

```text
RUNNING
  -> model emits ask_user tool call
  -> app recognizes ask_user as interactive blocking tool

ASKING_USER
  -> render question + options UI
  -> stop spinner / mark turn paused

WAITING_FOR_REPLY
  -> user selects a choice or submits freeform text

RESUMING
  -> app constructs ToolResult(content: answer)
  -> app calls agent.completeToolCall(result)
  -> ask UI is dismissed

RUNNING
  -> same agent turn continues
```

### Cancel path

Cancel behavior should be specified explicitly because Glue already supports user cancellation during streaming/tool execution.

Recommended v1 behavior:

- `Esc` while the ask panel is active cancels the entire in-flight agent turn
- the pending `ask_user` tool call receives a synthetic failed result, e.g. `"[cancelled by user]"`
- app exits asking state and returns to idle

Alternative behavior would be “stay blocked until answered,” but that is awkward in a terminal app and inconsistent with existing cancel affordances.

## Proposed implementation shape

## 1. Add a real `AskUserTool`

Add a tool class alongside the built-in tools.

Likely file:

- `cli/lib/src/tools/ask_user_tool.dart`

It should:

- expose schema/name/description to the model
- **not** actually block inside `execute()` in the normal interactive app path

Important: Glue’s tool execution model currently assumes tools are callable through `agent.executeTool(call)`, but `ask_user` is different from filesystem/web/shell tools. It should be intercepted by orchestration before normal tool execution.

### Recommendation

Still define it as a normal `Tool` so it appears in provider tool schemas, but do not rely on its `execute()` implementation in the interactive TUI path.

A safe stub implementation could return an error like:

- `Error: ask_user must be handled by interactive orchestration`

That makes accidental misuse in unsupported contexts obvious.

## 2. Register the tool in `ServiceLocator`

In `cli/lib/src/core/service_locator.dart`, add:

- `'ask_user': AskUserTool()`

This makes it available to the main agent and, by default, subagents unless filtered later.

## 3. Add dedicated app mode for asking

Current `AppMode` values are:

- `idle`
- `streaming`
- `toolRunning`
- `confirming`
- `bashRunning`

Add:

- `askingUser`

This is important because `ask_user` is neither generic confirmation nor normal idle input.

It has different semantics:

- the turn is mid-flight
- only the answer UI should consume input
- the bottom editor should not accidentally submit a fresh top-level message

## 4. Add dedicated UI state for ask-user prompts

Add an app-owned state object for the active prompt.

Likely in `cli/lib/src/app/models.dart`:

```dart
class _AskUserUiState {
  final String callId;
  final String question;
  final List<String> choices;
  final bool allowFreeform;
  int selectedIndex;
  final TextAreaEditor freeformEditor;
}
```

A simpler version could reuse the main editor buffer, but a dedicated editor is cleaner because it avoids clobbering the user’s partially typed draft in the normal input area.

Recommendation: keep a dedicated temporary editor for the ask flow.

## 5. Intercept `ask_user` in `agent_orchestration.dart`

This is the main integration point.

In `_handleAgentEventImpl`, under `case AgentToolCall(:final call):`

before permission-gate logic, branch on:

- `call.name == 'ask_user'`

Then:

1. parse/validate arguments
2. create `_AskUserUiState`
3. set tool UI phase to a new waiting state
4. stop spinner
5. set `app._mode = AppMode.askingUser`
6. render dedicated prompt UI
7. return without calling `_approveTool`, `_denyTool`, or `_executeAndCompleteTool`

This preserves the existing pending `Completer<ToolResult>` inside `AgentCore` until the user replies.

### Why intercept here

This is where Glue already handles special tool-call control flow:

- permission-gated tools
- modal approvals
- execution dispatch

`ask_user` belongs in the same orchestration layer because it is a runtime/UI decision, not a pure tool execution detail.

## 6. Extend tool UI phases for blocking human input

Current `_ToolPhase` values are:

- `preparing`
- `awaitingApproval`
- `running`
- `done`
- `denied`
- `cancelled`
- `error`

Add something like:

- `awaitingUserInput`

This lets the transcript render clearly:

- `▶ Tool: ask_user (waiting for reply)`

This also keeps tool lifecycle semantics consistent with the rest of the UI.

Matching renderer updates are needed in:

- `cli/lib/src/app/models.dart`
- `cli/lib/src/rendering/block_renderer.dart`

## 7. Add ask-user input handling in terminal routing

`cli/lib/src/app/terminal_event_router.dart` currently routes input to:

- panel modal
- confirm modal
- docked panels
- streaming-input handler
- autocomplete/editor

Add an early branch for `AppMode.askingUser`.

Desired behavior:

- Up/Down: move selected choice if choices exist
- Enter:
  - if freeform buffer non-empty and freeform allowed, submit freeform text
  - else if choices exist, submit selected choice
- Tab: maybe switch between choice list and freeform input, if needed
- Esc: cancel ask flow / cancel turn
- typed chars: go to dedicated freeform editor when freeform is enabled

For a minimal v1 UI, we can avoid focus switching complexity:

### Simple ergonomic design

If `choices.isNotEmpty`:

- Up/Down choose highlighted option
- Enter submits highlighted option when freeform buffer is empty
- any typed character enters freeform mode when `allow_freeform == true`
- Enter submits freeform buffer if it contains text

If no choices:

- freeform-only prompt using the dedicated editor

This minimizes new UI machinery.

## 8. Render the ask-user prompt inline in the conversation area

Recommended v1 rendering approach:

- keep the normal transcript block for the tool call
- additionally render an active prompt panel near the input area or as a special inline block at the bottom

A minimal version could render an inline system block such as:

```text
? Clarification needed
  Which action did you mean?
  > tag only
    tag and publish notes
    dry run

  Or type your answer...
```

This can likely be done in `render_pipeline.dart` without introducing a brand-new modal type.

### Why not reuse `ConfirmModal`

`ConfirmModal` is too narrow:

- assumes fixed yes/no-ish choices
- no freeform editor
- conceptually tied to approval

`ask_user` needs dedicated semantics and rendering.

## 9. Complete the tool call when the user replies

Add a method in app orchestration, conceptually:

```dart
void _submitAskUserResponse(String answer)
```

It should:

1. mark the `ask_user` tool UI state as done
2. log a session event for the reply
3. call `agent.completeToolCall(ToolResult(callId: ..., content: answer))`
4. clear active ask state
5. switch mode back to `streaming`
6. restart spinner
7. re-render

That is the key resume step.

## 10. Handle cancellation explicitly

Add a companion method, conceptually:

```dart
void _cancelAskUser()
```

Recommended behavior for v1:

1. mark tool phase as cancelled
2. call `agent.completeToolCall(ToolResult(
  callId: ...,
  success: false,
  content: '[cancelled by user]',
))`
3. cancel the whole agent turn via existing `_cancelAgent()` or a narrower path

There are two plausible strategies.

### Strategy A: complete tool result, let model see cancellation

- tool gets a failed result
- model could theoretically respond to cancellation
- but UI semantics become odd because the user intended to abort

### Strategy B: treat Esc as turn abort

- complete the tool result so transcript remains structurally valid
- then cancel the stream and return to idle

Recommendation: use Strategy B for v1 because it matches Glue’s current cancel mental model better.

## Headless and subagent behavior

This needs an explicit policy.

## Main concern

`AgentRunner` and subagents are headless by design:

- no interactive TUI
- tool calls are either auto-approved or denied
- they run to completion autonomously

A blocking human-input tool cannot work unchanged there.

## Recommended policy for v1

### In headless `AgentRunner`

If the model calls `ask_user`:

- do **not** block forever
- return a denied/unsupported tool result, e.g.
  - `"ask_user is unavailable in headless mode; proceed without clarification"`
  - or `"User input is unavailable in this runtime"`

This should be implemented as a special case in `AgentRunner._handleToolCall()`.

### In subagents

Same policy initially:

- subagents should not pause the parent UI waiting on human input
- return a failed tool result saying interactive clarification is unavailable in subagents

This keeps execution predictable and avoids nested human-input control flow.

### Why not bubble subagent questions up to the parent UI in v1

That is possible eventually, but it adds substantial orchestration complexity:

- which agent owns the question?
- how is the parent transcript updated?
- how are concurrent subagent questions serialized?
- how is cancellation handled?

That is too much for the first iteration.

## Prompting / usage guidance for models

Adding the tool alone is not enough; the system prompt should teach the model when to use it.

Update the agent prompt instructions so models know:

- use `ask_user` when one missing decision blocks progress
- ask one focused question at a time
- prefer choices for bounded decisions
- set `allow_freeform: false` when the reply must be constrained
- avoid asking questions that can be answered by reading the repo/config
- do not use `ask_user` for ordinary narration or status updates

Likely file:

- `cli/lib/src/agent/prompts.dart`

### Suggested instruction shape

Something like:

```text
If you cannot continue safely or correctly because one specific user decision is missing,
use the ask_user tool instead of asking in plain assistant text. Ask one focused question.
Prefer choices when the decision is bounded. Do not use ask_user when the answer can be
found from files, tool output, or prior conversation context.
```

## Session persistence and replay

Glue already logs:

- `tool_call`
- `tool_result`

That is good news: `ask_user` mostly fits existing session machinery.

## What should be logged

When `ask_user` is invoked:

- existing `tool_call` event with question/choices/allow_freeform args

When answered:

- existing `tool_result` event with content set to the answer text

This may already work without session schema changes.

## Optional enhancement

If we want replay/UI fidelity later, add a dedicated session event type like:

- `ask_user_reply`

But this is not required for transcript correctness because replay already reconstructs tool call + tool result.

## Message mapping implications

No fundamental provider protocol changes should be required.

Glue already maps:

- assistant tool calls to provider-specific tool-use structures
- tool results back to provider-specific tool-result structures

Since `ask_user` is still “just a tool call plus tool result,” these files should require little or no logic change:

- `cli/lib/src/llm/message_mapper.dart`
- `cli/lib/src/llm/tool_schema.dart`

The only change is that the `ask_user` tool now appears in the advertised tool list.

## Suggested file-by-file changes

## Core tool definition

### New

- `cli/lib/src/tools/ask_user_tool.dart`

### Modified

- `cli/lib/src/core/service_locator.dart`
  - register `ask_user`

## App orchestration and state

### Modified

- `cli/lib/src/app.dart`
  - add `AppMode.askingUser`
  - add ask-user state fields and helper methods

- `cli/lib/src/app/models.dart`
  - add `_AskUserUiState`
  - add `_ToolPhase.awaitingUserInput`

- `cli/lib/src/app/agent_orchestration.dart`
  - intercept `ask_user`
  - start ask flow
  - submit answer / cancel

- `cli/lib/src/app/terminal_event_router.dart`
  - route keyboard input for ask-user mode

- `cli/lib/src/app/render_pipeline.dart`
  - render active ask-user prompt and current selection/editor

- `cli/lib/src/rendering/block_renderer.dart`
  - render tool phase label for awaiting user input

## Prompting

### Modified

- `cli/lib/src/agent/prompts.dart`
  - document when to use `ask_user`

## Headless runtime

### Modified

- `cli/lib/src/agent/agent_runner.dart`
  - special-case `ask_user` as unsupported in headless mode

Potentially also:

- `cli/lib/src/agent/agent_manager.dart`
- `cli/lib/src/tools/subagent_tools.dart`

if additional tool filtering or behavior guards are needed for subagents.

## Tests

### New/modified likely areas

- `cli/test/agent_core_test.dart`
- `cli/test/agent/agent_runner_test.dart`
- new app-level orchestration tests if present
- new terminal routing tests if present
- session replay tests if needed

## Detailed behavior recommendations

## Tool schema description

The tool description should be explicit that this is for clarification only.

Suggested description:

```text
Pause execution and ask the user one focused clarification question.
Use this when one missing decision blocks progress and cannot be inferred safely.
Optionally provide choices for quick selection.
```

## Choice handling

When choices are present and the user selects one:

- return the selected string label as `ToolResult.content`

Do not return an index in v1.

This aligns with the intended UX and is easier for the model to consume.

## Freeform handling

If `allow_freeform == true` and the user typed text:

- submit the exact typed text after trim
- if trimmed text is empty, fall back to selected choice if available
- if no choice and no text, keep waiting

If `allow_freeform == false`:

- typing should either be ignored or produce a subtle UI hint
- simplest v1 behavior: ignore character input and only allow choice navigation

## Approval interaction

`ask_user` should bypass the normal permission gate.

Reason:

- it is already a user-input tool
- asking permission to ask the user would be redundant and awkward
- it is not a filesystem/network/shell capability escalation

So in `agent_orchestration.dart`, handle it before calling `_permissionGate.resolve(call)`.

## Observability

Existing tool spans may be sufficient, but `ask_user` has a useful extra metric:

- human wait duration

Recommended enhancement:

- capture the timestamp when `ask_user` becomes active
- on submit/cancel, log metadata such as:
  - `ask_user.wait_ms`
  - `ask_user.choice_count`
  - `ask_user.allow_freeform`
  - `ask_user.answer_source`

This is optional for v1, but a good fit for Glue’s existing observability model.

## Risks and edge cases

## 1. Draft preservation

If the user already has text typed into the main editor while the agent is running or before the ask prompt appears, the ask flow must not overwrite that draft.

Mitigation:

- use a dedicated ask-user editor state, not `app.editor`

## 2. Multiple concurrent `ask_user` calls

The current loop can theoretically emit multiple tool calls in one assistant turn.

For `ask_user`, Glue should not attempt to present multiple simultaneous human prompts.

Recommendation:

- support only one active `ask_user` at a time
- if the model emits multiple `ask_user` tool calls in the same batch, process the first and fail the rest with a deterministic error result like:
  - `"Only one ask_user call may be pending at a time"`

This should also be documented in the prompt guidance.

## 3. Interaction with normal assistant text

A model may emit explanatory text and then `ask_user` in the same assistant response.

That should work naturally because Glue already flushes accumulated assistant text before rendering tool UI.

## 4. Resume/fork correctness

Because the transcript remains standard assistant tool call + tool result, resume/fork should remain structurally valid.

Need to ensure only that cancelled ask-user flows also leave behind matching tool results, as existing cancellation repair already does for generic tools.

## 5. Provider differences

No major provider-specific issues are expected as long as the tool schema stays simple JSON and tool result content is plain text.

## Suggested phased implementation

## Phase 1 — Interactive main-agent support

1. add `AskUserTool`
2. register it in `ServiceLocator`
3. add `AppMode.askingUser`
4. add `_AskUserUiState`
5. intercept `ask_user` in orchestration
6. implement minimal TUI for:
   - question
   - optional choice navigation
   - optional freeform input
   - submit/cancel
7. add tool phase rendering
8. update prompts to encourage use

### Acceptance criteria

- model can call `ask_user`
- TUI pauses current turn and shows question
- user can answer with choice or text as allowed
- answer is injected as tool result
- same turn resumes and completes

## Phase 2 — Headless and subagent policy hardening

1. make `AgentRunner` explicitly reject `ask_user`
2. verify subagents do not hang on it
3. document unsupported contexts

### Acceptance criteria

- headless runs never block forever on `ask_user`
- subagents receive deterministic failure behavior

## Phase 3 — UX refinement

1. improve rendering polish
2. add optional answer-source metadata / observability
3. add better cancel messaging
4. consider replay labels that distinguish ask-user replies from ordinary tool results

## Test plan

## Unit tests

### Tool schema tests

- `ask_user` schema includes required `question`
- `choices` is optional array
- `allow_freeform` is optional boolean

### Orchestration tests

- `AgentToolCall(name: ask_user)` enters asking state instead of permission flow
- answer submission calls `agent.completeToolCall(...)` with expected content
- cancellation marks tool as cancelled and exits cleanly

### AgentRunner tests

- headless runner returns unsupported result for `ask_user`
- runner does not hang waiting for human input

### Rendering/state tests

- tool call shows awaiting-user-input phase
- choice selection updates correctly
- freeform submission takes precedence over highlighted choice when non-empty

## Integration tests

Add at least one scripted app-level test covering:

1. model emits text + `ask_user`
2. user selects a choice
3. model receives tool result and continues
4. final transcript order is:
   - user
   - assistant text
   - assistant tool call
   - tool result
   - assistant continuation

## Open questions

1. **Should `ask_user` be available to subagents eventually?**
   - Recommendation: not in v1.

2. **Should cancel return a tool result to the model, or hard-abort without resume?**
   - Recommendation: create a matching tool result for transcript validity, then abort the turn.

3. **Should freeform input be allowed when choices exist by default?**
   - Recommendation: yes, controlled by `allow_freeform`.

4. **Should the result be plain text or JSON?**
   - Recommendation: plain text in `content`, optional metadata later.

5. **Should `ask_user` use modal UI or inline UI?**
   - Recommendation: inline or lightweight dedicated prompt region first; avoid modal complexity unless needed.

## Acceptance criteria summary

This plan is complete when:

1. `ask_user` is exposed as a built-in tool
2. the interactive TUI pauses and waits for a structured answer when it is called
3. the answer is returned as the tool result for that tool call
4. the same agent turn resumes afterward
5. `ask_user` bypasses normal permission approval flow
6. headless/subagent contexts fail deterministically instead of hanging
7. session transcripts remain structurally valid across submit, cancel, resume, and replay
