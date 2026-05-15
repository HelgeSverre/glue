# App Decomposition — Phase 1: extract `Turn`

**Status:** 📋 Planned
**Date:** 2026-05-15 (rewritten after part-of inline at `26a6760`)
**Prereq:** `26a6760` (all part-of files inlined; App is one honest 2122-line class)

## Why now

After inlining the part-of files, `cli/lib/src/app.dart` is one large class with no hidden seams. The fake decomposition is gone, so the *real* cut-lines are visible. The cleanest cut is by **lifetime** — App holds two kinds of state:

- **App-lifetime** (born at startup, dies at exit): services, transcript, panels, render state, session manager
- **Turn-lifetime** (born on user submit, dies on `AgentDone` / cancel / error): streaming buffers, agent subscription, observability span, tool-approval bookkeeping

The Turn-lifetime cluster is small (~5 fields) but it touches ~340 lines of behaviour. Pulling it out is the highest-blast-radius win: it makes `_mode` derivable, gives tool approval a real owner, and turns "is it safe to start a new turn?" into a single field check.

## Success criterion — field loss

Phase 1 is done when **these exact fields are gone from `App`**:

| Field | Type | Current line in app.dart (after `26a6760`) |
|-------|------|---------------------------------------------|
| `_streamingText` | `String` | ~166 |
| `_streamingThinking` | `String` | ~167 |
| `_agentSub` | `StreamSubscription<AgentEvent>?` | ~168 |
| `_turnSpan` | `ObservabilitySpan?` | ~202 |
| `_earlyApprovedIds` | `Set<ToolCallId>` | ~205 |

And `_mode` (line ~149) becomes a **computed getter**, not a stored field. The `_mode = AppMode.X` assignment sites (~15 of them) are gone.

Counter-example: if the work ends and `_streamingText` still lives on App, the extraction isn't done. The field-loss test is mechanical and unambiguous.

### What stays on App
- `_activeModal` — used by *both* tool approval *and* Ollama pull-confirm; not turn-scoped. Turn requests modals via a port, doesn't own the field.
- `_toolUi` — tool UI state outlives turns (rendered in scrollback). Turn writes into it via the sink, doesn't own it.
- `_subagentGroups`, `_outputLineGroups` — App-tier transcript state.
- `_spinnerTimer`, `_spinnerFrame` — App-lifetime UI state. Turn calls `_startSpinner`/`_stopSpinner` via the sink or a port.

## `Turn`'s public surface

```dart
class Turn {
  Turn({
    required AgentCore agent,
    required String userMessage,
    required String expandedMessage,
    required TranscriptSink transcript,
    required PermissionGate permissions,
    required ModalRequester modals,
    required ApprovalPolicy approvalPolicy,
    Observability? observability,
    String? sessionId,
    String? modelId,
  });

  Future<TurnOutcome> get outcome;  // completes once, then nothing
  TurnPhase get phase;               // streaming | confirming | toolRunning | done
  void cancel();
}

enum TurnPhase { streaming, confirming, toolRunning, done }

sealed class TurnOutcome {
  const factory TurnOutcome.completed({String? assistantText}) = TurnCompleted;
  const factory TurnOutcome.cancelled() = TurnCancelled;
  const factory TurnOutcome.failed(Object error) = TurnFailed;
}
```

**Hard rule (pre-mortem rule #6):** `TurnOutcome` has exactly three terminal variants. In-flight inspection goes through `Turn.phase` (a getter). If a fourth outcome variant gets proposed during implementation, stop and decide whether it's actually a phase.

## Ports — narrow seams

### `TranscriptSink` (already exists in spirit via `ConversationView`)

Turn writes through this; never touches App fields:

```dart
abstract class TranscriptSink {
  void addAssistantText(String text);
  void addThinking(String text);
  void addError(String message);
  void addToolCallRef(ToolCallId id);
  void addToolResult(String summaryOrContent);
  void registerToolUi(ToolCallId id, String name);
  void setToolPhase(ToolCallId id, ToolUiPhase phase);
  void setToolArgs(ToolCallId id, Map<String, dynamic> args);
  void logSessionEvent(String kind, Map<String, dynamic> body);
  void recordUsage(LlmUsage usage);
  void onStreamingDelta();             // signal to repaint
  void onTurnIdleHandoff();            // start/stop spinner + render
  void onTurnRunningHandoff();         // mode transition signals
}
```

App implements this against `_blocks` / `_toolUi` / `_sessionManager` / spinner / `_render` via a private adapter (`_AppTranscriptSink`). No back-callback table on ctx. One cohesive port.

### `ModalRequester` — opens a single-slot modal

```dart
abstract class ModalRequester {
  Future<int> requestConfirm({
    required String title,
    required List<String> bodyLines,
    required List<ModalChoice> choices,
  });
}
```

Backed by App: opens `_activeModal`, returns its future, clears the field on completion. Turn doesn't see `_activeModal`. The Ollama pull-confirm flow uses the same App-internal modal slot directly — no coordination needed because the agent loop and pull-confirm are mutually exclusive (pull-confirm only fires from `/model`, an idle-state command).

### `ApprovalPolicy` — read-only view

```dart
class ApprovalPolicy {
  final Set<String> trustedTools;
  void Function(String) persistTrusted;
}
```

Holds the trusted-tool set + the persistence callback. Approval mode (`_approvalMode`) is read via `PermissionGate` which Turn receives directly.

## What moves into `Turn`

Mechanical moves — the body of each becomes a Turn method:

- `_startAgent` body → `Turn` constructor (everything after `_blocks.add(user-entry)` which stays on App)
- `_handleAgentEvent` (all 6 event cases)
- `_endTurnSpan`, `_flushThinking`
- `_approveTool`, `_denyTool`, `_showToolConfirmModal`, `_traceToolApproval`
- `_executeAndCompleteTool`
- `_cancelAgent` → `Turn.cancel()`
- `_persistTrustedTool` → moves into `ApprovalPolicy.persistTrusted` callback

Total: ~340 lines leave App.

## App's new shape

```dart
class App {
  // ... unchanged services + transcript fields ...
  Turn? _activeTurn;  // ← new
  // _mode is now a getter, not a field
  // _streamingText, _streamingThinking, _agentSub, _turnSpan,
  // _earlyApprovedIds — gone.

  AppMode get _mode {
    final turn = _activeTurn;
    if (turn == null) {
      return _activeModal != null ? AppMode.confirming : AppMode.idle;
    }
    return switch (turn.phase) {
      TurnPhase.confirming  => AppMode.confirming,
      TurnPhase.toolRunning => AppMode.toolRunning,
      TurnPhase.streaming   => AppMode.streaming,
      TurnPhase.done        => AppMode.idle,
    };
  }

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _blocks.add(ConversationEntry.user(displayMessage,
        expandedText: expandedMessage));
    _startSpinner();
    _render();

    _activeTurn = Turn(
      agent: agent,
      userMessage: displayMessage,
      expandedMessage: expandedMessage ?? displayMessage,
      transcript: _AppTranscriptSink(this),
      permissions: _permissionGate,
      modals: _AppModalRequester(this),
      approvalPolicy: ApprovalPolicy(
        trustedTools: _autoApprovedTools,
        persistTrusted: _persistTrustedTool,
      ),
      observability: _obs,
      sessionId: _sessionManager.currentSessionId,
      modelId: _modelId,
    );
    _activeTurn!.outcome.then(_onTurnOutcome);
  }

  void _onTurnOutcome(TurnOutcome outcome) {
    _activeTurn = null;
    _stopSpinner();
    switch (outcome) {
      case TurnCompleted():
        _reevaluateTitle();
      case TurnCancelled():
        // sink already folded cancelled state into transcript
      case TurnFailed(:final error):
        _blocks.add(ConversationEntry.error(error.toString()));
    }
    _render();
  }
}
```

Bash slash command path (`!cmd`) is unaffected — it doesn't go through a turn.

## What this phase does NOT do

- **No MVU vocabulary** (`Msg`, `reduce`, `Effect`). If MVU emerges as the natural shape inside `Turn`, Phase 2 adopts it then.
- **No `Transcript` extraction.** Phase 2 candidate, only if `TranscriptSink` grows past ~12 methods.
- **No `RenderPipeline` extraction.** Frame state is small; deferred.
- **No `BashRuntime`.** Already a separate concern.
- **No file split.** `Turn` lives in `cli/lib/src/turn/turn.dart`, but `App` stays in `app.dart`. No part-of files.

## Done criteria (mechanical)

1. New file `cli/lib/src/turn/turn.dart` defines `Turn`, `TurnPhase`, `TurnOutcome`, `TranscriptSink`, `ModalRequester`, `ApprovalPolicy`.
2. App fields gone: `_streamingText`, `_streamingThinking`, `_agentSub`, `_turnSpan`, `_earlyApprovedIds`. Verified by `grep -n "_streamingText\|_streamingThinking\|_agentSub\b\|_turnSpan\|_earlyApprovedIds" cli/lib/src/app.dart` returning no matches.
3. `_mode` is a getter — no `_mode = AppMode.X` assignments anywhere. Verified by `grep -n "_mode = " cli/lib/src/app.dart` returning no matches.
4. App method count drops: `_startAgent` shrinks to ~15 lines; `_handleAgentEvent`, `_endTurnSpan`, `_flushThinking`, `_approveTool`, `_denyTool`, `_showToolConfirmModal`, `_traceToolApproval`, `_executeAndCompleteTool`, `_cancelAgent`, `_persistTrustedTool` are gone from App.
5. New test file `cli/test/turn/turn_test.dart` exercises `Turn` against a fake `Agent` and fake `TranscriptSink`/`ModalRequester`. Coverage: happy-path text streaming, tool-call approve/deny/always, early-approval flow, cancel mid-stream, agent error.
6. `dart format`, `dart analyze --fatal-infos`, `dart test`, `just check` all green.

## Abort conditions

- More than 2 non-sink/non-modal back-channels from `Turn` into App → lifetime cut is wrong here; stop and reconsider MVU.
- `TurnOutcome` accumulates a 4th terminal variant → variant accretion; figure out if it's a phase instead.
- `_AppTranscriptSink` grows real logic (anything beyond field assignments and one-line forwards) → transcript needs its own type first.
- Test setup needs to fake more than `Agent + TranscriptSink + ModalRequester + PermissionGate` → port shape is wrong.

## Implementation order

1. Sketch `Turn` and the three ports in `cli/lib/src/turn/turn.dart` with method stubs and `throw UnimplementedError()`.
2. Write `cli/test/turn/turn_test.dart` against the stubs (all red).
3. Move `_handleAgentEvent`'s body into `Turn` case-by-case, with associated helpers (`_flushThinking`, `_endTurnSpan`, tool approval methods). After each case, tests should green.
4. Move `_cancelAgent` into `Turn.cancel()`.
5. Replace App's turn-state with `Turn? _activeTurn`. Convert `_mode` to a getter. Delete the 5 fields.
6. Implement `_AppTranscriptSink` and `_AppModalRequester` adapters.
7. Wire `_startAgent` to construct a `Turn` and route its outcome.
8. `just check` + manual smoke (interactive: streaming, thinking, tool Y/N/Always, early-approval, cancel mid-tool, error, two turns back-to-back, Ollama pull-confirm via `/model`).
9. Open PR titled `extract Turn from App` with this plan linked.

## Reassessment checkpoint (post-Phase-1)

Answer with code in hand:

1. Is `TranscriptSink` honest? Did it stay around ~12 methods or balloon?
2. How many non-sink/non-modal back-channels does `Turn` have into App? Target: 0.
3. Did `Turn`'s internals develop a clear Msg/State/Effect shape? If yes → name it (Phase 2 = adopt MVU inside `Turn`, not across App).
4. Is the App class now sub-2000 lines and obviously not turn-aware? → potential stopping point.

If none of those bite, **stop after Phase 1**.
