# PTY Automation Primitives

The minimal verb set agent-tui exposes for driving an interactive
terminal program from outside. This is the same vocabulary Glue would
want for a `tui_run` tool.

## The verb set

| Verb         | What it does                                                              |
| ------------ | ------------------------------------------------------------------------- |
| `spawn`      | Start a command under a PTY at a given size; return `{ session_id, pid }` |
| `screenshot` | Capture the current screen as plain text + cursor + (optional) styled     |
| `type`       | Write a literal UTF-8 string to the PTY                                   |
| `press`      | Send one named key (`Enter`, `Ctrl+C`, `ArrowDown`, …)                    |
| `keydown`    | Hold a modifier key down                                                  |
| `keyup`      | Release a modifier key                                                    |
| `wait`       | Block until a screen condition holds or a timeout elapses                 |
| `resize`     | Change the PTY size (rows/cols)                                           |
| `kill`       | Terminate the session and its process group                               |
| `restart`    | Kill + re-spawn with the original launch spec; new `session_id`           |

That's the entire surface area an agent needs to drive almost any TUI.

## Spawning

agent-tui uses the `portable-pty` crate (the `wezterm` family). On Unix
that's `openpty(3)` + `fork/exec`. The relevant decisions:

- **Default `TERM`** is forced to `xterm-256color`. Setting this
  consistently is what lets vterm-style emulators interpret colors and
  cursor moves correctly regardless of the host terminal.
- **Terminal size bounds** are enforced at the domain layer: cols
  ∈ [10, 500], rows ∈ [2, 200], default 80×24. Rejecting absurd sizes
  before they reach the kernel avoids confusing failures from the PTY
  layer.
- **The reader thread duplicates the master fd** (`dup(2)`) before
  reading. The duplicate is owned by a `File` so the reader can be
  joined and the original handle dropped independently.
- **Reader shutdown signal is itself a fd.** The reader blocks in
  `poll(2)` on `[shutdown_fd, master_fd]`. Cancelling reads is just
  writing one byte to the shutdown half of a `socketpair`. No timeouts,
  no flag polling, no spurious wakeups.

```text
                  poll(2) blocks here
                  ┌──────────────────┐
   master_fd ────►│                  │── POLLIN ──► drain to channel
                  │   reader_loop    │
   shutdown_fd ──►│                  │── POLLIN ──► break + cleanup
                  └──────────────────┘
```

The reader pushes typed events (`Data(Vec<u8>) | Eof | Error(String)`)
onto an unbounded `crossbeam_channel`, which is then drained by the
session pump. EOF and errors are first-class events, not implicit on
the data channel.

## Killing — the process-group ladder

`child.kill()` alone is not enough. A shell that has launched grandchildren
won't propagate the kill, and you get orphaned processes hanging on the
terminal. agent-tui does this:

1. Verify the child is its own process-group leader: `getpgid(pid) == pid`.
2. If yes, `kill(-pid, SIGTERM)` — negative pid sends to the whole group.
3. Wait up to 500 ms for exit (poll `try_wait()` every 25 ms).
4. If still alive, `kill(-pid, SIGKILL)` and wait up to another 500 ms.
5. If at any step the process-group send fails (e.g. ESRCH), fall back
   to `child.kill()` directly.
6. Treat ESRCH as success — the process is already gone.

This is the pattern Glue's shell tool should adopt when it eventually
spawns interactive children. Without it, a `Ctrl+C` on a hung `npm
install` leaves orphaned `node` processes.

## Key encoding

agent-tui maps human-readable key names to the byte sequences that real
terminals send. The full mapping table from
`cli/crates/agent-tui-infra/src/infra/terminal/pty.rs::key_to_escape_sequence`:

| Key          | Bytes            |
| ------------ | ---------------- |
| `Enter`      | `\r`             |
| `Tab`        | `\t`             |
| `Escape`     | `\x1b`           |
| `Backspace`  | `\x7f`           |
| `Delete`     | `\x1b[3~`        |
| `Space`      | `\x20`           |
| `ArrowUp`    | `\x1b[A`         |
| `ArrowDown`  | `\x1b[B`         |
| `ArrowRight` | `\x1b[C`         |
| `ArrowLeft`  | `\x1b[D`         |
| `Home`       | `\x1b[H`         |
| `End`        | `\x1b[F`         |
| `PageUp`     | `\x1b[5~`        |
| `PageDown`   | `\x1b[6~`        |
| `Insert`     | `\x1b[2~`        |
| `F1`–`F4`    | `\x1bO{P,Q,R,S}` |
| `F5`–`F12`   | `\x1b[{15..24}~` |
| `Shift+Tab`  | `\x1b[Z`         |

### Modifiers

- `Ctrl+<letter>` → byte `(letter & 0x1F)` — i.e. `Ctrl+C` is `0x03`,
  `Ctrl+D` is `0x04`, `Ctrl+Z` is `0x1A`.
- `Ctrl+@`, `Ctrl+Space` → `0x00`.
- `Ctrl+[` → `0x1B` (same as Escape — historical).
- `Ctrl+\` → `0x1C`. `Ctrl+]` → `0x1D`. `Ctrl+^` → `0x1E`. `Ctrl+_` →
  `0x1F`. `Ctrl+?` → `0x7F`.
- `Alt+<key>` (and `Meta+`, `Cmd+`, `Super+`) → `\x1b` prefix +
  recursively-encoded base key.
- `Shift+<key>` → uppercase / shifted form (e.g. `Shift+1` → `!`,
  `Shift+;` → `:`).

A combined chord like `Ctrl+Alt+a` produces `\x1b\x01` (Alt-prefix +
Ctrl-A).

### `type` vs `press`

- `type "hello world"` → write the bytes verbatim. No interpretation.
  Use this for text content.
- `press Enter` → look up `Enter` in the table above and write `\r`.
  Use this for keys.

This split matters: `type "Enter"` writes the five letters, and
`press "hello world"` is meaningless. Glue should mirror the same
distinction in its tool surface.

## Screen capture

agent-tui doesn't store the raw bytes the program emitted — it runs them
through a real terminal emulator and reads back the resulting screen
state. That makes the captured "screenshot" what a human would _see_,
not what was _written_.

The emulator is `tattoy-wezterm-term` (the wezterm-derived VT crate).
Each session owns a `VirtualTerminal` of fixed `(rows, cols)` plus a
1000-line scrollback ring. PTY output is fed in via
`terminal.advance_bytes(data)`. Cursor position, cell colors, bold /
underline / inverse, and Unicode width handling all come for free.

The capture API has three flavors:

| Method                    | What you get                                                     |
| ------------------------- | ---------------------------------------------------------------- |
| `screen_text()`           | Plain text, trailing whitespace per row trimmed, no styling      |
| `screen_render()`         | Same content, but with ANSI escapes for colors/styles re-emitted |
| `screen_render_compact()` | Compacted styled output (whitespace runs collapsed)              |

The `screen_text()` format is what an LLM should see by default — it's
the smallest payload that preserves layout. The styled variants are for
the live-preview UI.

### Cursor as a first-class field

Snapshot output always (optionally) carries cursor position:

```json
{
  "session_id": "abc123",
  "screenshot": "...",
  "cursor": { "row": 7, "col": 23, "visible": true }
}
```

This matters for agents because many TUI states are visually identical
except for cursor location (think a list with a highlight bar that's
just inverse video). Without `cursor` you have to scrape the highlight
out of the styled render; with `cursor` you get it directly.

## Trimming convention

`screen_text()` does **trailing-whitespace trimming on every row** and
**trailing-empty-row trimming on the buffer**. A blank 80×24 screen
serializes as `""`, not 24 newlines of spaces. This keeps screenshots
small for token-constrained LLM contexts.

The implementation is `ScreenBuffer::trimmed_rows()` —
`rposition(|c| !c.is_whitespace())` per row, then truncate to the last
non-empty row. ~50 lines of code; worth lifting verbatim.

## Resize semantics

`resize` propagates in two places: the PTY (`master.resize(PtySize)`)
and the virtual terminal (`terminal.resize(...)`). Doing only one
desyncs the screen state from what the program thinks the size is — the
emulator will render at the old size while the program writes at the
new one.

Programs are notified via `SIGWINCH`, which the PTY layer raises
automatically on resize. This is the same mechanism a normal terminal
uses, so well-behaved programs handle it correctly without further
work.

## Where this lives in agent-tui

| Concern                 | File                                                                       |
| ----------------------- | -------------------------------------------------------------------------- |
| PTY spawn / read / kill | `cli/crates/agent-tui-infra/src/infra/terminal/pty.rs`                     |
| Virtual terminal        | `cli/crates/agent-tui-infra/src/infra/terminal/vterm.rs`                   |
| Screen rendering / trim | `cli/crates/agent-tui-infra/src/infra/terminal/render.rs`                  |
| Modifier handling       | `cli/crates/agent-tui-infra/src/infra/daemon/session.rs` (`ModifierState`) |
| Use-case orchestration  | `cli/crates/agent-tui-usecases/src/usecases/{snapshot,input,wait}.rs`      |
