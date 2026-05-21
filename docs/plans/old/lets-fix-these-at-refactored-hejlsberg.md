# Plan: OTEL session.id, tool-cancel tracking, exit cleanup, alias autocomplete, /model description

## Context

Five small but unrelated fixes have piled up on `refactor/c1-turn`:

1. **`session.id` is missing/empty in OTEL spans.** In `--print` mode the session
   store isn't created until deep inside the agent loop, so the `agent.turn` span
   ships with `session.id = ""`. Even when set on the turn span, child spans
   (`agent.iteration`, `llm.call`, `tool.*`, `tool.approval`) don't carry the
   attribute at all — they only inherit `traceId`/`parentSpanId`. Langfuse / Arize
   / OpenInference backends group per-span by `session.id`, so traces lose their
   session grouping.
2. **Tool cancellation isn't tracked.** When the user hits Escape mid-turn,
   `Turn.cancel()` flips UI state and injects synthetic `[cancelled by user]`
   tool_results, but `tool.<name>` spans started in `Agent.executeTool` are
   either left dangling (slow tool never returns) or close as `tool.success: true`
   when the orphaned background future eventually resolves — a misleading
   "succeeded" trace for a cancelled turn.
3. **`/quit`, `/exit`, and Ctrl+C don't restore the terminal cleanly.** The
   cleanup in `App._runInteractive`'s `finally` does call `disableMouse` /
   `resetScrollRegion` / `showCursor` / `disableAltScreen` / `disableRawMode`,
   but it does so **after** `_obs?.flush()` and `_obs?.close()`. A slow or
   unreachable OTLP endpoint blocks teardown for seconds while the TUI still
   owns the terminal — looks like a freeze on exit.
4. **Aliases show up as separate entries in the slash-command dropdown.**
   `/exit` and `/quit` (and `/model` and `/models`) both surface as candidates
   even though they're the same command, cluttering autocomplete.
5. **`/model` description is verbose.** Currently
   `"Switch model (no args = picker, with arg = switch directly)"` — the
   parenthetical is noise once the user is in a picker UI that demonstrates
   itself.

Goal: ship all five as a small, focused set of edits before resuming the
larger turn refactor. Each issue lives in one or two files; no cross-cutting
refactors required.

---

## Files to modify

| # | File | Change |
| - | ---- | ------ |
| 1 | `cli/lib/src/runtime/turn.dart` | Ensure session store before opening `agent.turn` span; cancel in-flight tool spans on `cancel()`. |
| 1 | `cli/lib/src/observability/observability.dart` | In `startSpan`, inherit `session.id` from effective parent's attributes when child doesn't supply one. |
| 2 | `cli/lib/src/agent/agent.dart` | Track in-flight tool spans by `callId`; expose `markToolCancelled(callId)`. Wire `executeTool` to remove-and-end via the map. |
| 3 | `cli/lib/src/app.dart` | Reorder `_runInteractive` finally so terminal restore happens before obs flush/close; add 2s timeout around obs flush. |
| 4 | `cli/lib/src/commands/slash_autocomplete.dart` | In `_updateNameMode`, drop the `for (final alias in cmd.aliases)` loop — match only on `cmd.name`. (`SlashCommandRegistry.findByName` already resolves aliases at execute time, so typing a full alias still works.) |
| 5 | `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` | Trim `/model` description to `"Switch model"`. |

---

## Implementation detail per item

### 1. `session.id` on every span (`turn.dart`, `observability.dart`)

**`Turn.runPrint` (turn.dart:148):** call `session.ensureStore()` at the very
top, before the span is opened. Same defensive call at the top of `Turn.run`
(turn.dart:74) — interactive path already calls `ensureStore` upstream in
`app.dart:568`, so this is just belt-and-braces and a no-op when the store
already exists.

**`Observability.startSpan` (observability.dart:183):** when an effective
parent exists and the caller-supplied attributes don't include `session.id`,
copy `parent.attributes['session.id']` into the new span's attributes. This
makes `agent.iteration`, `llm.call`, `tool.*`, and `tool.approval` automatically
carry the session id without touching every callsite. Implementation:

```dart
ObservabilitySpan startSpan(
  String name, {
  String kind = 'internal',
  Map<String, dynamic>? attributes,
  ObservabilitySpan? parent,
}) {
  final effectiveParent = parent ?? activeSpan;
  final merged = <String, dynamic>{...?attributes};
  final inheritedSessionId = effectiveParent?.attributes['session.id'];
  if (inheritedSessionId != null &&
      inheritedSessionId is String &&
      inheritedSessionId.isNotEmpty) {
    merged.putIfAbsent('session.id', () => inheritedSessionId);
  }
  return ObservabilitySpan(
    name: name,
    kind: kind,
    attributes: merged,
    traceId: effectiveParent?.traceId,
    parentSpanId: effectiveParent?.spanId,
  );
}
```

This way the `agent.turn` span (which we make sure has a real `session.id`)
seeds it for every descendant.

### 2. Tool cancellation tracking (`agent.dart`, `turn.dart`)

**`Agent` (agent.dart):**
- Add `final Map<String, ObservabilitySpan> _activeToolSpans = {};`
- In `executeTool` (agent.dart:500), after creating `span`, register
  `_activeToolSpans[call.id] = span` (when `_obs != null`).
- In both the success and error paths, change span end logic to:
  `final s = _activeToolSpans.remove(call.id); if (s != null) _obs!.endSpan(s, extra: {...});`
  This guarantees we only end the span if it hasn't already been ended via
  cancellation.
- New method:
  ```dart
  void markToolCancelled(String callId, {String reason = 'user_cancel'}) {
    final span = _activeToolSpans.remove(callId);
    if (span == null || _obs == null) return;
    _obs!.endSpan(span, extra: {
      'cancelled': true,
      'tool.success': false,
      'tool.cancel.reason': reason,
    });
  }
  ```
- Reuse this from `ensureToolResultsComplete` (agent.dart:464) — for every
  unmatched `tool_use`, also call `markToolCancelled(tc.id)` so any still-open
  tool span gets a cancelled close.

**`Turn.cancel` (turn.dart:270):** before `agent.ensureToolResultsComplete()`,
iterate `transcript.toolUi.values` and for any state in `running` /
`awaitingApproval` / `preparing` phase call `agent.markToolCancelled(state.id)`.
(Calling it for not-yet-started ids is a safe no-op since they aren't in the
map.) `ensureToolResultsComplete` then handles any leftovers we missed.

### 3. Exit-path reordering (`app.dart`)

In `_runInteractive`'s `finally` (app.dart:394–426), reorder so terminal
state is restored as the **first** step after subscriptions are closed, and
slow IO is the last step:

```dart
} finally {
  _stopSpinner();
  _currentTurn?.cancel();             // close agent.turn span while obs still open
  await termSub.cancel();
  await appSub.cancel();
  await _subagentSub?.cancel();
  await _events.close();

  // Visual restore — must happen before slow IO so the user always sees
  // a normal terminal even if obs flush hangs.
  terminal.disableMouse();
  terminal.resetScrollRegion();
  terminal.showCursor();
  terminal.write('\x1b[0m');
  terminal.disableAltScreen();
  terminal.disableRawMode();

  // Slow / network teardown, capped so a misconfigured OTLP endpoint
  // can't hold the shell hostage.
  for (final tool in agent.tools.values) {
    try { await tool.dispose(); } catch (_) {}
  }
  await _flushObsBounded();           // Future.any(flush+close, 2s timeout)
  await _sessionManager.closeCurrent();
  await jobSub.cancel();
  await _jobManager.shutdown();

  // Exit footer + final dispose
  final sessionId = _sessionManager.currentSessionId;
  if (sessionId != null) {
    stdout.writeln('\n\x1b[33m◆\x1b[0m Holding it together till next time.');
    stdout.writeln('  \x1b[90m\$ glue --resume $sessionId\x1b[0m');
  }
  terminal.dispose();
}
```

`_flushObsBounded` is a tiny private helper:

```dart
Future<void> _flushObsBounded() async {
  final obs = _obs;
  if (obs == null) return;
  await Future.any([
    () async { await obs.flush(); await obs.close(); }(),
    Future.delayed(const Duration(seconds: 2)),
  ]);
}
```

This addresses Ctrl+C / `/exit` / `/quit` together — they all funnel through
`requestExit()` → this finally block.

### 4. Hide aliases from autocomplete (`slash_autocomplete.dart`)

In `_updateNameMode` (slash_autocomplete.dart:95), delete the inner
`for (final alias in cmd.aliases)` loop. Result: only canonical command
names appear in the dropdown. Typing `/quit` and pressing Enter still works
because `SlashCommandRegistry.findByName` already resolves aliases and
hiddenAliases.

### 5. Trim `/model` description (`register_builtin_slash_commands.dart:101`)

Change:
```dart
description: 'Switch model (no args = picker, with arg = switch directly)',
```
to:
```dart
description: 'Switch model',
```

---

## Tests to update / add

- `cli/test/observability/observability_test.dart` — add a case asserting
  child spans inherit `session.id` from the effective parent.
- `cli/test/runtime/turn_test.dart` (or nearest existing) — add a case that
  cancels mid-tool and asserts the corresponding `tool.*` span ends with
  `cancelled: true`, `tool.success: false`.
- `cli/test/agent/agent_test.dart` — add a case for `markToolCancelled` and
  for the integration with `ensureToolResultsComplete`.
- `cli/test/commands/slash_autocomplete_test.dart` (or wherever name-mode is
  tested) — assert that an alias prefix no longer surfaces a candidate.
- `cli/test/app/print_mode_test.dart` (if present) — assert `session.id` is
  non-empty on the emitted `agent.turn` span.

---

## Verification

```sh
# from cli/
just check                      # gen-check + analyze + test
dart test test/observability    # spot-check observability tests
dart test test/agent            # spot-check tool-cancel tests
dart test test/commands         # autocomplete behaviour
```

End-to-end smoke (manual):

1. `dart run bin/glue.dart --print -m <model> "say hi"` — confirm the OTLP
   export contains a non-empty `session.id` on the turn span and on each
   child span (use `OTEL_EXPORTER_OTLP_ENDPOINT` with a local collector or
   `glue --debug` + file sink).
2. `dart run bin/glue.dart` → ask for a long-running tool (e.g. a web fetch),
   hit `Esc` to cancel → confirm the corresponding `tool.*` span carries
   `cancelled: true`.
3. `/exit` and `/quit` and Ctrl+Ctrl+C from idle → terminal returns to
   normal cursor / colors / scroll region within a second even if OTEL
   endpoint is unreachable (`OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:1`
   to simulate).
4. Type `/q` in the prompt — autocomplete shows only `/quit`-prefixed
   *primary* commands; `/quit` itself is hidden, but pressing Enter on the
   typed `/quit` still exits Glue.
5. Open autocomplete with `/m` — `/models` no longer appears as a duplicate
   of `/model`. The `/model` row's description reads simply "Switch model".
