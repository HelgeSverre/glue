# Handling Ctrl+C / SIGINT in Glue

A reference note for `glue "<prompt>" --json` (and any other non-interactive
flow that streams LLM output). The goal: a single Ctrl+C cleanly cancels
in-flight work; a second Ctrl+C hard-kills the process. This note exists
because Glue had a long-standing bug where `^C` echoed in the terminal but
the Dart process kept streaming until the LLM finished on its own.

## 1. How Ctrl+C actually becomes a SIGINT

The keystroke does not magically kill anything. The path is:

1. **TTY line discipline** in the kernel reads input character-by-character.
   When the input byte matches `c_cc[VINTR]` (default `0x03`, "ETX") *and*
   the `ISIG` flag is set in `c_lflag`, the driver synthesises a signal
   instead of delivering the byte to the reader. (See `termios(3)`.)
2. **Process-group lookup**: the driver consults the controlling terminal's
   *foreground process group* (set via `tcsetpgrp(3)`).
3. **Signal delivery**: `SIGINT` is sent to *every process* in that PGID,
   not just the leader.
4. **Process action**: each receiver runs its installed handler or the
   default action — terminate with exit status `128 + signum`, conventionally
   `130` for SIGINT.

`stty -a` shows the live values; `stty -isig` disables step 1 entirely,
after which Ctrl+C is delivered to the program as a literal `0x03` byte
on stdin.

### Raw mode and `cfmakeraw()`

POSIX `cfmakeraw()` clears `ECHO | ECHONL | ICANON | ISIG | IEXTEN` from
`c_lflag`, so any code that puts the terminal into raw mode **disables
Ctrl+C signal generation by default**. To preserve signals while still
doing character-at-a-time input, clear `ICANON` but leave `ISIG` set, or
only flip `echoMode` / `lineMode` rather than going fully raw.

## 2. Why a CLI "swallows" Ctrl+C

In rough order of likelihood:

- **Raw / no-line-mode TTY without a `0x03` fallback.** With `ISIG` cleared,
  the kernel never raises SIGINT; Ctrl+C arrives as a stdin byte. If the
  reader doesn't translate that byte into a cancellation, the process just
  keeps going. Node has the same trap and warns about it explicitly:
  *"Ctrl+C will no longer cause a SIGINT when in this mode."*
- **A signal listener was installed but never calls `exit()`.** In Dart,
  once you subscribe to `ProcessSignal.sigint.watch()`, the runtime
  *suppresses* the default terminate behaviour. If your handler logs and
  returns, nothing kills the VM.
- **The signal handler can't reach the work.** This is the bug Glue had:
  the global SIGINT handler called `requestExit()` which only completed an
  exit-completer that the *interactive* event loop awaited. The
  *non-interactive* path (`turn.runPrint`) was a single blocking `await for`
  with no subscription to cancel — so SIGINT had nothing to unblock.
- **The process is no longer in the foreground process group.** If the CLI
  forked a child that called `setsid()` / `setpgid()` and took control of
  the TTY, Ctrl+C is delivered to the child's group, not yours.
- **Blocking syscall on a thread that ignores signals.** Some platform
  threads (Dart's I/O isolate doing a blocking native read, libcurl
  synchronous DNS, etc.) won't see EINTR cleanly.
- **stdin not drained / blocking read.** A `stdin.readLineSync()` can hold
  the event loop and prevent the SIGINT stream from firing its callback.

## 3. Dart-specific gotchas

The Dart documentation states that `ProcessSignal.watch` lets you "intercept
the default signal handler and implement another." Two consequences:

- **You replace the default; you do not augment it.** Once you `.listen()`,
  hitting Ctrl+C runs *your* code. If you don't call `exit(130)` or
  re-`Process.killPid(pid, signal)`, the process stays alive.
- **Dart 2.18 stopped restoring terminal state on exit.** Programs that
  touched `stdin.echoMode` / `stdin.lineMode` are now responsible for
  restoring them on every exit path — including SIGINT. Use
  `try { ... } finally { stdin.echoMode = prevEcho; }` *and* a SIGINT
  watcher, because `finally` does **not** run when a signal terminates
  the process by default.
- **`stdin.lineMode = false` puts the TTY into non-canonical mode.**
  Combined with `echoMode = false` this is Dart's "raw-ish" mode. Make
  sure ISIG is still effective (Dart does not clear it for you, but
  third-party packages like `dart_console` may), or translate `0x03`
  yourself.
- **Cancellation must propagate.** A SIGINT handler that just calls
  `exit()` during a long LLM stream may leak sockets and child processes.
  Cancel:
  - the active `http.Client` via `client.close()`,
  - any `StreamSubscription` opened on the SSE/NDJSON stream,
  - `Process` children spawned (call `child.kill(ProcessSignal.sigterm)`,
    and if you grouped them, send to the negative PID — see §5),
  - timers / `CancelableOperation`s bound to the turn.
- **Windows.** Only `SIGINT` is portable; `SIGTERM`/`SIGUSR*`/`SIGWINCH`
  are POSIX-only on the Dart VM. There's a known `dartdev run` quirk where
  signals are delivered to the launcher rather than the child — ship the
  AOT binary (`dart compile exe`) for predictable behaviour.

## 4. Glue's two-press convention

Glue follows the same pattern used by `curl`, `kubectl`, `ripgrep`, and
most coding agents:

1. **First Ctrl+C** → flip a cancellation token, close streams, ask child
   processes to exit, print a one-line "Cancelling…" status. Do **not**
   call `exit()` yet — let the in-flight unwind run so we emit a clean
   JSON envelope or a `[cancelled]` marker.
2. **Second Ctrl+C** (or the first if it arrives during cleanup) → call
   `exit(130)` immediately. By convention, exit status
   `128 + SIGINT (2) = 130`.

In Dart the shape is roughly:

```dart
var sigintCount = 0;
late StreamSubscription<ProcessSignal> sub;
sub = ProcessSignal.sigint.watch().listen((_) {
  sigintCount++;
  if (sigintCount == 1) {
    stderr.writeln('\nCancelling… press Ctrl+C again to force quit.');
    turn.cancel(); // tears down _sub, emits JSON envelope w/ cancelled:true
  } else {
    sub.cancel();
    exit(130);
  }
});
```

### A cancellation token that flows through the request stack

Mirror what Go's `signal.NotifyContext` does for `context.Context`: build a
single cancel signal at the top of the `Turn`, pass it into the LLM client,
the tool runner, and any `Process.start()`. Every `await` point should
either be wired to that signal or be cheap enough that the next iteration
of the loop will check it.

In Glue today this is implicit — cancelling the agent stream subscription
unwinds the per-request `http.Client` via the provider's `finally` block
(`anthropic_provider.dart`, `openai_provider.dart`), which in turn aborts
the SSE socket and stops billing. Tool subprocesses are torn down by the
existing `ShellJobManager` SIGTERM/SIGKILL escalation.

### Kill child processes by group, not by PID

If a tool runs `bash -lc 'long-thing | other-thing'`, the shell creates its
own process group. `child.kill(SIGTERM)` only signals the immediate child;
the pipeline survives. Two reliable fixes:

- Spawn each tool subprocess in its own session (`setsid` on Linux/macOS),
  record the PID, and on cancel send `kill(-pid, SIGTERM)` — the negative
  PID delivers the signal to **the entire group**.
- On Linux specifically, set `prctl(PR_SET_PDEATHSIG, SIGTERM)` in the
  child so the kernel kills it if the Dart parent dies hard.

### Always restore terminal state

Wrap any interactive section in `try/finally` *and* install a SIGINT
watcher that restores the saved `echoMode` / `lineMode` before re-killing
with the same signal. Glue does this in `App._runInteractive` /
`Terminal.disableRawMode`.

### Distinct exit codes

- `0` — success.
- `130` — cancelled by SIGINT (POSIX `128 + signum`).
- `143` — terminated by SIGTERM. Useful in CI / Kubernetes logs.

## 5. Glue checklist for `--json` / `-p` mode

- [x] Subscribe to `ProcessSignal.sigint.watch()` once per non-interactive
      run (locally inside `_runPrintMode`, not just globally in `App.run`).
- [x] First press: cancel the active `Turn` (which cancels `_sub`,
      closes the LLM HTTP client via the provider's `finally`, and patches
      dangling tool calls via `Agent.ensureToolResultsComplete`).
- [x] Second press: `exit(130)` immediately.
- [x] Never enter raw mode in non-interactive flows; keep `ISIG`
      effective so the kernel does the heavy lifting.
- [x] If a slash command flips `stdin.echoMode` / `stdin.lineMode`, it
      registers a `try/finally` restoring the prior values *and* hooks
      the SIGINT watcher to do the same restore before exit.
- [ ] Spawn tool subprocesses with their own session and remember the
      PGID so cancellation can send `kill -- -<pgid>`. (Future work — the
      current `ShellJobManager` only kills the immediate child.)
- [x] Surface "cancelled" in the JSON event stream with a stable shape
      (`{"cancelled": true, ...}`) so pipelines can distinguish cancel
      from error.

## References

- Dart, [`ProcessSignal` class](https://api.dart.dev/dart-io/ProcessSignal-class.html)
  and [`ProcessSignal.watch`](https://api.flutter.dev/flutter/dart-io/ProcessSignal/watch.html)
  — "intercept the default signal handler and implement another."
- Dart, [`Stdin.echoMode`](https://api.dart.dev/stable/3.5.1/dart-io/Stdin/echoMode.html),
  [`Stdin.lineMode`](https://api.dart.dev/stable/2.16.1/dart-io/Stdin/lineMode.html),
  and [SDK issue #45630](https://github.com/dart-lang/sdk/issues/45630)
  — "Don't restore terminal state on exit."
- Linux man-pages, [`termios(3)`](https://man7.org/linux/man-pages/man3/termios.3.html)
  — `ISIG`, `VINTR`, `cfmakeraw()`.
- Nelson Elhage, [A brief introduction to termios](https://blog.nelhage.com/2009/12/a-brief-introduction-to-termios-termios3-and-stty/).
- "Build Your Own Text Editor" (kilo tutorial),
  [Entering raw mode](https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html)
  — the canonical walk-through of disabling `ISIG` and reading `0x03`
  directly.
- Viacheslav Biriukov,
  [Process groups, jobs and sessions](https://biriukov.dev/docs/fd-pipe-session-terminal/3-process-groups-jobs-and-sessions/),
  and Kev Roletin,
  [How terminal works — pty, sessions](https://kevroletin.github.io/terminal/2022/02/05/how-tty-works-sessions.html)
  — foreground process group and `tcsetpgrp` semantics.
- Node.js docs, [TTY: `setRawMode`](https://nodejs.org/api/tty.html) and
  [Process: signal events](https://nodejs.org/api/process.html) — explicit
  warning that raw mode disables Ctrl+C-as-SIGINT, plus the `'SIGINT' /
  'SIGTERM'` default-handler override rule.
- Henrique Vicente, [`signal.NotifyContext`](https://henvic.dev/posts/signal-notify-context/)
  and Mat Ryer, [Make Ctrl+C cancel the context.Context](https://medium.com/@matryer/make-ctrl-c-cancel-the-context-context-bd006a8ad6ff)
  — the Go pattern Glue's cancellation should mirror.
- Igor Šarčević,
  [Killing a process and all of its descendants](https://morningcoffee.io/killing-a-process-and-all-of-its-descendants),
  and Baeldung,
  [Kill all members of a process group](https://www.baeldung.com/linux/kill-members-process-group)
  — negative-PID / `setsid` patterns for tool subprocesses.
