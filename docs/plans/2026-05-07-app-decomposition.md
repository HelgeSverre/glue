# App Decomposition — Phase 1: extract `Turn`

**Status:** 📋 Planned
**Date:** 2026-05-13 (rewritten from 2026-05-07 draft after swarm review)
**Prereq:** `d2cba58` (class-based slash commands + thin services); WS1+WS2 of the loose-ends pass (`PanelController` → `ModalSurface` rename, `*Impl` → extension methods on App).

## What changed from the previous draft

The earlier draft proposed four "peers" (`Turn`, `TranscriptStore`, `ToolApprovals`, `BashRuntime`) and a six-phase rollout. Swarm review (7 lenses, 2026-05-13) found three load-bearing problems:

1. **The peers weren't peers.** `TranscriptStore` is a shared substrate that the other three write into. Calling it a peer hides the real shape.
2. **The five design rules leaked.** "No back-callbacks" + "modes are derived" + "events as the seam" can't all hold simultaneously without an underlying reducer pattern.
3. **The plan was implicitly MVU.** Several lenses arrived independently at the conclusion that the plan was incremental MVU adoption disguised as type extraction.

The user picked **cut-by-lifetime over MVU** and **one phase then reassess** over a full multi-phase plan. The rest of this document reflects that.

## Why lifetime over MVU

The two candidate cuts compared against the actual fields in `cli/lib/src/app.dart`:

**Cut by feature (the prior plan, MVU-shaped):**
- Names: `Turn`, `TranscriptStore`, `ToolApprovals`, `BashRuntime`
- Implies a `Msg`/`reduce`/`Effect` triple at each peer
- Requires committing to MVU vocabulary across the codebase
- Real cost: every peer needs an effect runner; 90% of mutations are local and don't benefit from the ceremony

**Cut by lifetime (this plan):**
- Three tiers: **App-lifetime** (services + transcript), **Turn-lifetime** (one user message → resolution), **Frame-lifetime** (one render)
- Maps cleanly onto the existing field clusters
- Mode derivation is structurally free (one active turn ⇒ one mode source)
- Tool approval state is *visibly* turn-scoped — its lifetime is the same as the streaming buffers, so it lives inside `Turn`
- No MVU vocabulary required; if MVU emerges as the natural shape after Phase 1, Phase 2 can adopt it

The lifetime cut is honest about what's actually different between fields. The feature cut imposed a uniform shape on three things with very different lifetimes.

## The lifetime tiers (mapped against current App fields)

### App-lifetime — born at startup, dies on exit
- Services: `_commands`, `_environment`, `_cwd`, `_modelId`, `_config`, `_executor`, `_jobManager`, `_sessionManager`, `_conversation`, `_skillRuntime`, `_obs`, `_debugController`
- Transcript: `_blocks`, `_toolUi`, `_subagentGroups`, `_outputLineGroups` (persist across turns; cleared on resume/fork as a deliberate App-tier action)
- UI surfaces: `_panelStack`, `_panels`, `_dockManager`, `_autocomplete`, `_atHint`, `_shellComplete`
- Permissions: `_autoApprovedTools`, `_approvalMode`
- Subscriptions: `_subagentSub`

### Turn-lifetime — born on user-message submission, dies on AgentDone/cancel/error
- Streaming: `_streamingText`, `_streamingThinking`
- Agent wire: `_agentSub`
- Observability: `_turnSpan`
- Tool approval: `_earlyApprovedIds`, `_activeModal` *(when open for tool confirm)*
- Derived: `_mode` becomes a getter, not a field

### Frame-lifetime — born on a render tick, dies at end of that render
- `_lastRender`, render throttle state
- `_spinnerTimer` (App-lifetime today, but the visible spinner output is frame-driven)

Out of scope for Phase 1: `_bashRunProcess` / `_bashSpan` (separate short-lifetime concern, only used by the `!cmd` slash path).

## Phase 1: extract `Turn`

Why Turn first: turn-scoped fields are the source of every "is it safe to clear this?", "what mode are we in?", and "did this leak across turns?" question in the codebase. Pulling them into one type with one lifecycle resolves the cluster.

### `Turn`'s public surface

```dart
class Turn {
  Turn({
    required Agent agent,
    required String userMessage,
    required String expandedMessage,
    required TranscriptSink transcript,
    required PermissionGate permissions,
    required ModalSurface modals,
    required ApprovalPolicy approvalPolicy, // trusted-tools + approval-mode
    Observability? observability,
    String? sessionId,
    String? modelId,
  });

  Stream<TurnOutcome> outcome;   // emits exactly once, then closes
  TurnPhase get phase;            // streaming | confirming | toolRunning | done
  void cancel();
}

enum TurnPhase { streaming, confirming, toolRunning, done }

sealed class TurnOutcome {
  const factory TurnOutcome.completed({String? assistantText}) = TurnCompleted;
  const factory TurnOutcome.cancelled() = TurnCancelled;
  const factory TurnOutcome.failed(Object error) = TurnFailed;
}
```

**Design Rule (from pre-mortem lens):** `TurnOutcome` is capped at exactly three terminal variants. In-flight inspection goes through `Turn.phase` (a getter), never through new outcome variants. This prevents `TurnOutcome` from mutating into an `AgentEvent` mirror over the project's lifetime.

### The `TranscriptSink` port

`Turn` does not touch App fields. It writes through one narrow interface:

```dart
abstract class TranscriptSink {
  void addAssistantText(String text);
  void addThinking(String text);
  void addError(String message);
  void addToolCallRef(ToolCallId id);
  void addToolResult(String summaryOrContent);
  void updateToolUi(ToolCallId id, ToolUiUpdate update);
  void logSessionEvent(String kind, Map<String, dynamic> body);
  void recordUsage(LlmUsage usage);
}
```

`App` implements `TranscriptSink` against its existing `_blocks` / `_toolUi` / `_sessionManager` fields via a private adapter (`_AppTranscriptSink`). No back-callback table on the slash context. No `void Function()` plumbing. One cohesive port.

### What moves into `Turn`

From `cli/lib/src/app/agent_orchestration.dart`:
- `_startAgent` body (the spawn-and-listen part)
- `_handleAgentEvent` in its entirety, including:
  - Thinking-flush logic
  - Streaming text accumulation
  - Tool-call pending vs full-args handling
  - Early-approval flow (`_earlyApprovedIds`)
  - Permission gate resolution
  - Modal opening on `Ask` decision
  - Tool execution and completion
- `_cancelAgent` body
- `_endTurnSpan`, `_flushThinking`
- `_approveTool`, `_denyTool`, `_showToolConfirmModal`, `_traceToolApproval`
- `_executeAndCompleteTool`

From `cli/lib/src/app.dart`:
- Fields: `_streamingText`, `_streamingThinking`, `_agentSub`, `_turnSpan`, `_earlyApprovedIds`, `_activeModal` (when held for a turn confirm)

### What stays on App

App keeps:
- All services, config, transcript (`_blocks`/`_toolUi`/etc.), session manager, panels, render loop
- A single new field: `Turn? _activeTurn`
- A new computed getter: `AppMode get _mode => ...derive from _activeTurn...`
- A small `_AppTranscriptSink` adapter implementing the port against App fields

App's `_startAgent` becomes a shell:

```dart
void _startAgent(String displayMessage, {String? expandedMessage}) {
  _blocks.add(ConversationEntry.user(displayMessage, expandedText: expandedMessage));
  _startSpinner();
  _render();

  _activeTurn = Turn(
    agent: agent,
    userMessage: displayMessage,
    expandedMessage: expandedMessage ?? displayMessage,
    transcript: _AppTranscriptSink(this),
    permissions: _permissionGate,
    modals: _panels,
    approvalPolicy: _approvalPolicy(),
    observability: _obs,
    sessionId: _sessionManager.currentSessionId,
    modelId: _modelId,
  );
  _activeTurn!.outcome.first.then(_onTurnOutcome);
}

void _onTurnOutcome(TurnOutcome outcome) {
  _activeTurn = null;
  _stopSpinner();
  switch (outcome) {
    case TurnCompleted():
      _reevaluateTitle();
    case TurnCancelled():
      // sink already folded the cancelled state into the transcript
    case TurnFailed(:final error):
      _blocks.add(ConversationEntry.error(error.toString()));
  }
  _render();
}
```

### Mode derivation falls out

```dart
AppMode get _mode {
  if (_activeModal != null && _activeTurn == null) return AppMode.confirming;
  final turn = _activeTurn;
  if (turn == null) return AppMode.idle;
  return switch (turn.phase) {
    TurnPhase.confirming  => AppMode.confirming,
    TurnPhase.toolRunning => AppMode.toolRunning,
    TurnPhase.streaming   => AppMode.streaming,
    TurnPhase.done        => AppMode.idle,
  };
}
```

One source. No setter calls scattered across the codebase. No illegal state combinations because the source itself can't represent them.

## What this phase explicitly does NOT do

- **No MVU vocabulary.** No `Msg`, no `reduce`, no `Effect`. If MVU emerges as the natural shape after Phase 1 (signals: `Turn` internally develops a clear msg/state/effect split), Phase 2 can adopt it.
- **No `Transcript` extraction.** The transcript is a tangle of `_blocks` / `_toolUi` / `_subagentGroups` / `_outputLineGroups`. Untangling it is its own design problem; deferred.
- **No `RenderPipeline` extraction.** Render state is small enough to wait.
- **No `BashRuntime`.** Out of scope; the shell layer is already its own concern.
- **No cosmetic renames.** `command_helpers.dart` cleanup and the `/history` + `/resume` decomposition (the old WS3/WS4) are *separate* small follow-ups and not part of this phase.

## Done criteria

1. New file `cli/lib/src/turn/turn.dart` defines `Turn`, `TurnPhase`, `TurnOutcome`, `TranscriptSink`, `ApprovalPolicy`.
2. New file `cli/lib/src/turn/_app_transcript_sink.dart` (or inline in `app.dart`) implements the port.
3. `cli/lib/src/app/agent_orchestration.dart` is deleted or shrunk to <50 lines (just orchestration glue if any remains).
4. App has `Turn? _activeTurn`; the six turn-scoped fields listed above are gone from `App`.
5. `AppMode` is a computed getter, not a stored field. The `_mode = AppMode.X` assignment sites are gone.
6. New test file `cli/test/turn/turn_test.dart` drives `Turn` against a fake `Agent` and a fake `TranscriptSink`. At minimum: happy-path text streaming, tool-call approve/deny/always, early-approval flow, cancel mid-stream, agent error.
7. `dart format`, `dart analyze --fatal-infos`, `dart test`, `just check` all green.

## Reassessment checkpoint

After Phase 1 lands, answer with code in hand:

1. **Is the `TranscriptSink` interface honest?** Did it stay at ~8 methods, or grow past 15? If past 15, the transcript needs its own type (Phase 2 candidate).
2. **Did `Turn` need back-channels beyond the sink?** Count: how many non-sink calls into App does `Turn` make? Target: 0. If >2, the lifetime cut is wrong here and we should reach for MVU.
3. **Did `_doRender` become turn-driven?** If most of the render reads off `_activeTurn`, `RenderPipeline` extraction becomes worth it.
4. **Did `Turn` internally develop a Msg/State/Effect shape?** If yes, name it (Phase 2 = adopt MVU vocabulary inside `Turn`, not across App).

If none of those bite, **stop after Phase 1**. The minimalist read may be right.

## Abort conditions

- `Turn` requires more than 2 non-sink back-channels into App → abort, evaluate MVU instead.
- `TurnOutcome` accumulates a fourth terminal variant during implementation → stop and decide whether it's actually a phase (visible via `Turn.phase`) or a real outcome. Variant accretion is a red flag.
- `_AppTranscriptSink` grows real logic (anything beyond field assignments and one-line forwards) → the transcript is hiding its own type and needs extracting before `Turn` lands.
- Test setup for `Turn` requires faking more than the `Agent` + `TranscriptSink` + `ModalSurface` triple → the port shape is wrong.

## Out of scope (separate work items)

- **WS3** (ConversationView absorbs replay; drop `forkSession`/`resumeFromMeta` from ctx) — independent of Phase 1; can land before, after, or in parallel.
- **WS4** (Delete `command_helpers.dart`) — independent; small follow-up.
- **Phase 2+** — explicitly not pre-planned. The shape will be obvious (or obviously absent) after Phase 1.

## Implementation order

1. Sketch `Turn` and `TranscriptSink` in `cli/lib/src/turn/turn.dart` with method stubs and no logic.
2. Write `cli/test/turn/turn_test.dart` against the stubs (red).
3. Move agent-event handling body from `agent_orchestration.dart` into `Turn` method-by-method, getting the test green.
4. Wire App: introduce `_activeTurn`, `_AppTranscriptSink`, replace `_startAgent` body, delete old fields.
5. Convert `_mode` from field to getter; delete `_mode = ...` assignments.
6. Delete (or shrink) `agent_orchestration.dart`.
7. `just check`; manual smoke (interactive: streaming text, thinking, tool approval Y/N/Always, early-approval, cancel mid-tool, agent error, two turns back-to-back).
8. Open PR titled `extract Turn` with this plan linked in the body.

## Verification

- `dart format --set-exit-if-changed .`
- `dart analyze --fatal-infos`
- `dart test`
- `just check`
- Interactive smoke (above)
- Diff inspection: `agent_orchestration.dart` gone or <50 lines; App fields list lost the turn-scoped block; `_mode` is a getter; no new back-callbacks on ctx
