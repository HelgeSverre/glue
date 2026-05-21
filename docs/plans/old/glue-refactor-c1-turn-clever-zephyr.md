# Plan: Make `glue --json` (non-interactive) cancellable with Ctrl+C

## Context

Today, running `glue "<prompt>" --json` (or `--print`/`-p`) does not respond to Ctrl+C. The terminal echoes `^C` repeatedly but the process keeps streaming until the LLM finishes on its own. This wastes output tokens, blocks scripted/CI use, and leaves users having to `kill -9` from another shell.

Root cause is a one-line gap, not an architectural problem:

- `app.dart:314-326` installs `ProcessSignal.sigint.watch().listen((_) => requestExit())` for both modes.
- `requestExit()` (`app.dart:303-306`) only completes `_exitCompleter`. Interactive mode awaits that completer at `app.dart:391`, so SIGINT correctly unblocks it.
- **Print mode** (`app.dart:455-511`) does *not* await `_exitCompleter`. It awaits `turn.runPrint(...)` directly. Inside `runPrint` (`turn.dart:184`), the agent stream is consumed with `await for` — there is no `StreamSubscription` to call `.cancel()` on, so SIGINT has nothing to unblock.

The interactive path already has the right primitive: `Turn.cancel()` (`turn.dart:279-309`) cancels the stored `_sub` subscription, marks the span cancelled, repairs dangling tool UI states, and patches the conversation with synthetic `[cancelled]` results via `Agent.ensureToolResultsComplete()` (`agent.dart:532-566`). The HTTP layer also already supports clean cancellation: providers create a per-request `http.Client` and close it in `finally` (`anthropic_provider.dart:107-155`, `openai_provider.dart:133-185`), so cancelling the subscription tears down the SSE socket and stops billing.

The fix is to wire `runPrint` through the same `_sub` mechanism the interactive path uses, then have the SIGINT handler call `turn.cancel()` (first press) and `exit(130)` (second press), matching the two-press convention used by `curl`, `kubectl`, `ripgrep`, and most coding agents.

We also write a `docs/reference/sigint-handling.md` brief capturing the TTY/termios/Dart background, since the user has hit this several times and it informs future work on shell tools and PTY automation.

## Approach

1. **Refactor `Turn.runPrint`** to consume `agent.run(...)` via a `StreamSubscription` stored in `_sub`, exactly like `Turn.run` (`turn.dart:74-147`) does. Track completion with a `Completer<void>` that's completed on `AgentDone`, `AgentError`, error, or cancel.
2. **Extend `Turn.cancel`** to handle the print-mode case: when `_jsonMode` was active, emit a final JSON envelope with `"cancelled": true` and the partial `conversation` log so pipelines can distinguish cancel from error. When not in JSON mode, the existing `[cancelled]` flush already prints a trailing `[cancelled]` to stdout.
3. **Wire SIGINT in `_runPrintMode`** as a *local* subscription (not the global one in `App.run`). First press → `turn.cancel()` + write `"\nCancelling…"` to stderr. Second press → `exit(130)` immediately. The subscription is cancelled in `finally`. Keep the global SIGINT subscription in `App.run` for the interactive path; the local one takes precedence while print mode is active because `ProcessSignal.watch()` delivers to all listeners but the local one runs first.
4. **Reference doc**: write `docs/reference/sigint-handling.md` with the termios/Dart-specific findings from research (already drafted) so the rationale is captured next to the other reference notes.

## Files to modify

| File | Change |
| --- | --- |
| `cli/lib/src/runtime/turn.dart` | Convert `runPrint` to subscription-based consumption with a completion `Completer`; extend `cancel()` to flush JSON envelope when called from print mode |
| `cli/lib/src/app.dart` | Add per-press SIGINT handling around the `turn.runPrint(...)` call inside `_runPrintMode`; ensure exit code 130 on cancel |
| `cli/test/runtime/turn_test.dart` | Add `Turn.runPrint — cancellation` group mirroring the existing `Turn.cancel` tests, using the existing `_DelayedLlm` and `_makeHarness` patterns (`turn_test.dart:280-426`) |
| `cli/test/app/print_mode_sigint_test.dart` (new) | Process-level integration test: spawn `dart run bin/glue.dart -p "..."` with a stub provider, send `SIGINT`, assert exit code 130 and that JSON output contains `cancelled: true` |
| `docs/reference/sigint-handling.md` (new) | Reference brief on TTY/termios, Dart `ProcessSignal` semantics, two-press convention, child-process group kills |

Reuse, do not duplicate:

- `Turn.cancel()` and `_sub` field (`turn.dart:279-309`) — extend, don't fork.
- `Agent.ensureToolResultsComplete()` (`agent.dart:532-566`) — already called from `Turn.cancel`; works as-is for print mode.
- HTTP teardown via `requestClient.close()` in providers (`anthropic_provider.dart:153`, `openai_provider.dart:183`) — no change needed; cancelling the subscription propagates through the existing `finally` blocks.

## TDD approach

Write tests first, in this order:

1. **`turn_test.dart`** — extend `_makeHarness` so it can drive `runPrint` (currently it only drives `run`), then add:
   - `runPrint cancel mid-stream completes the future` — start `runPrint`, await one delta, call `turn.cancel()`, assert the returned future completes within 100ms.
   - `runPrint cancel ends agent.turn span with cancelled=true` — same as the existing interactive test at `turn_test.dart:303`.
   - `runPrint cancel in jsonMode emits a final JSON envelope with cancelled:true` — capture stdout via `IOOverrides.runZoned`, assert the JSON contains `"cancelled": true` and the partial `conversation` array.
   - `runPrint cancel patches dangling tool calls via ensureToolResultsComplete` — mirror `turn_test.dart:336`.

2. **`print_mode_sigint_test.dart`** (new, tagged `@Tags(['integration'])` so it runs under `just integration`) — spawn the AOT binary or `dart run bin/glue.dart` with a stubbed model that streams slowly (e.g. point at a local fake server, or use the existing `--debug` no-op path). Send `SIGINT` after a short delay, assert:
   - Process exits within 2s.
   - Exit code is `130`.
   - When `--json` was passed, stdout contains a parseable JSON object with `cancelled: true`.
   - A second `SIGINT` arriving during cleanup forces immediate exit (also `130`).

3. Implement against the failing tests.

## Verification

After implementation, run:

```sh
cd cli
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test test/runtime/turn_test.dart
dart test --run-skipped -t integration test/app/print_mode_sigint_test.dart
just check
```

End-to-end manual verification:

```sh
just build
./cli/glue "write a 5000 word essay about the history of the unix shell" --json
# press Ctrl+C ~2s in. Expect: process exits within ~1s, JSON envelope printed with cancelled:true, exit code 130.
echo $?  # → 130

./cli/glue "ditto" -p
# press Ctrl+C ~2s in. Expect: trailing [cancelled] on stdout, no JSON, exit code 130.
echo $?  # → 130

# Two-press hard exit
./cli/glue "ditto" --json
# press Ctrl+C twice rapidly during streaming. Expect: process exits immediately on the second press.
```

Also run the interactive flow to confirm we did not regress it:

```sh
./cli/glue
# start a long turn, press Ctrl+C — turn cancels, prompt returns, app stays running. Press Ctrl+C twice at idle to exit.
```
