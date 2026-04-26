# TUI Session Daemon

agent-tui's "daemon" is a background process that owns long-lived PTY
sessions and exposes them to one or more clients. The CLI itself is
stateless — every `agent-tui screenshot` connects to the daemon, asks
for the current screen, prints, and exits.

This separation is the right shape for any tool whose sessions
outlive a single command invocation. Glue's resumable conversations
already have this property at the agent layer; extending it to
sub-process sessions (a dev server, a REPL, `tail -f`) would let an
agent return to a still-running thing instead of re-spawning.

## Process types

| Process            | Role                                                                         |
| ------------------ | ---------------------------------------------------------------------------- |
| `agent-tui daemon` | Long-running session manager + HTTP/WS server + embedded UI                  |
| `agent-tui <cmd>`  | One-shot client; connects, sends one JSON-RPC call, prints result, exits     |
| Bun web UI         | Optional standalone web server when you want the UI separate from the daemon |

The daemon is plain enough to run under `systemd` or in a Procfile —
agent-tui ships an example unit file in `docs/ops/process-model.md`.

## IPC: two transports, one protocol

The daemon speaks JSON-RPC 2.0 line-delimited messages, and clients can
reach it two ways:

| Transport | Selected via                                         | When to use                              |
| --------- | ---------------------------------------------------- | ---------------------------------------- |
| Unix      | default; `AGENT_TUI_TRANSPORT=unix`                  | Local CLI ↔ local daemon                 |
| WebSocket | `AGENT_TUI_TRANSPORT=ws`, `AGENT_TUI_WS_ADDR=ws://…` | Remote client, browser, container ↔ host |

Same JSON-RPC envelopes go over both. The transport layer is a thin
trait (`IpcTransport`) with a `connect_connection()` method. The
client never knows which carrier it ended up on; the request/response
shape is identical.

This is the lesson worth taking: **define your protocol once over
JSON, and let the transport be plug-replaceable.** A Dart equivalent in
Glue would be one `RpcClient` interface with `UnixSocketRpc` and
`WebSocketRpc` implementations.

### Socket location

```
$AGENT_TUI_SOCKET                                # explicit
$XDG_RUNTIME_DIR/agent-tui.sock                  # default on Linux
$TMPDIR/agent-tui-<uid>.sock                     # macOS / fallback
```

The CLI just probes whether the socket exists and is connectable. If
not, it auto-spawns the daemon (see below).

### Auto-start

If the Unix transport finds no listening socket, the CLI:

1. Re-execs the same binary as `agent-tui daemon run` with
   `AGENT_TUI_DAEMON_FOREGROUND=1` set, stdin/stdout to `/dev/null`,
   stderr to `~/.agent-tui/agent-tui.sock.log`.
2. Polls the socket with exponential backoff until it accepts a
   connection or the child exits (whichever first).
3. On exit-before-listening, reads the last 5 lines of the daemon log
   and surfaces them in the error.
4. On success, hands the child off to a "reaper" thread that just
   `wait()`s for it (so the daemon process doesn't become a zombie if
   the parent CLI exits first).

The recursion guard (`AGENT_TUI_DAEMON_FOREGROUND=1`) prevents an
auto-spawned daemon from itself trying to auto-spawn another daemon.

## Session lifecycle

```text
spawn ──► running ──► (terminated by program | killed by client) ──► reaped
                │
                └─ resize / type / press / wait / restart / kill at any time
```

Each session has:

- A `SessionId` (8 random chars, derived from a UUID v4 prefix).
- The original launch spec (`command`, `args`, `cwd`, `env`) so
  `restart` can rebuild it.
- A PTY handle + a virtual terminal + a stream buffer of recent bytes.
- A pump thread that drains PTY output into the stream buffer and
  notifies waiters.
- A 512-entry command timeline that records every input the daemon
  received (sanitized, max 160 chars per entry).

### Active session

Many CLI commands accept an optional `--session <id>`. If omitted, the
daemon resolves to the **active** session — the most recently spawned
running session, or the most recent one if you set it explicitly with
`agent-tui sessions activate <id>`.

This shaves boilerplate off scripted flows: spawn once, then `press` /
`screenshot` / `wait` without re-stating the id. For Glue, the same
"active session implicit, otherwise --session" convention is the right
default.

### Persistence across daemon restarts

Session metadata is appended to `~/.agent-tui/sessions.jsonl` (one
JSON object per line). On daemon startup the file is replayed to
restore the session list. Note that **only metadata** is persisted —
the PTY children themselves do not survive a daemon restart, because
their controlling terminal (the PTY master) was held by the previous
daemon process.

The daemon's startup sweep also kills any leftover process groups from
a prior daemon — it iterates persisted PIDs, verifies they were spawned
within the last 30 s of the recorded `created_at`, and sends SIGTERM.
This stops orphaned children from accumulating across crashes.

## Stream subscription model

The daemon exposes the PTY byte stream as an addressable stream:

- `stream_read(cursor, max_bytes, timeout_ms)` returns bytes ≥
  `cursor.seq` and advances the cursor.
- `stream_subscribe()` returns a `StreamWaiter` whose `wait(timeout)`
  blocks until either a new byte arrives or the timeout elapses.
- The buffer caps at 8 MiB; older bytes are dropped and `dropped_bytes`
  is reported so consumers know they fell behind.

The wait use case relies on `stream_subscribe()` to avoid fixed-interval
polling — see `wait-conditions.md`.

## Configuration surface

| Env var                        | Purpose                                             | Default                           |
| ------------------------------ | --------------------------------------------------- | --------------------------------- |
| `AGENT_TUI_SOCKET`             | Unix socket path                                    | `$XDG_RUNTIME_DIR/agent-tui.sock` |
| `AGENT_TUI_TRANSPORT`          | `unix` or `ws`                                      | `unix`                            |
| `AGENT_TUI_WS_ADDR`            | Remote WS URL (client side, when transport is `ws`) | —                                 |
| `AGENT_TUI_WS_LISTEN`          | Daemon WS bind address                              | `127.0.0.1:0`                     |
| `AGENT_TUI_WS_ALLOW_REMOTE`    | Permit non-loopback bind                            | `false`                           |
| `AGENT_TUI_WS_STATE`           | WS state file location                              | `~/.agent-tui/api.json`           |
| `AGENT_TUI_WS_DISABLED`        | Skip starting the WS server                         | `false`                           |
| `AGENT_TUI_WS_MAX_CONNECTIONS` | Cap on concurrent WS clients                        | `32`                              |
| `AGENT_TUI_SESSION_STORE`      | Session metadata log path                           | `~/.agent-tui/sessions.jsonl`     |
| `AGENT_TUI_DETACH_KEYS`        | Sequence to detach from `attach` mode               | `Ctrl-P Ctrl-Q`                   |

## Where this lives in agent-tui

| Concern            | File                                                                |
| ------------------ | ------------------------------------------------------------------- |
| Daemon runtime     | `cli/crates/agent-tui-infra/src/infra/daemon/session.rs` (2.4k LOC) |
| Repository facade  | `cli/crates/agent-tui-infra/src/infra/daemon/repository.rs`         |
| Unix transport     | `cli/crates/agent-tui-infra/src/infra/ipc/transport.rs`             |
| Auto-start logic   | same — `start_daemon_background_impl()` plus the reaper pattern     |
| Process polling    | `cli/crates/agent-tui-infra/src/infra/ipc/polling.rs`               |
| Persistence        | `cli/crates/agent-tui-infra/src/infra/daemon/repository.rs`         |
| Process model docs | `docs/ops/process-model.md`                                         |
