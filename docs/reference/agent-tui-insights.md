# agent-tui Insights

Reference notes extracted from [pproenca/agent-tui](https://github.com/pproenca/agent-tui)
(MIT, Rust). agent-tui is a CLI + background daemon that lets external
processes drive interactive terminal applications: spawn under a PTY, capture
screen state, send keystrokes, wait for conditions, repeat. It is **not** a
TUI itself — the TUI in the name is what it controls.

These notes exist because Glue has overlapping concerns:

- Glue's shell tool blocks on anything interactive (`npm init`, `git rebase
  -i`, `gh auth login`, `vipe`, REPLs, password prompts).
- Glue could expose a TUI-driving tool to its agent so those flows stop
  hanging the conversation.
- Glue's own session model (resumable conversations) maps cleanly onto a
  long-lived PTY session model.

The companion files break the system down by concern:

| File                                  | What it covers                                             |
| ------------------------------------- | ---------------------------------------------------------- |
| `pty-automation-primitives.md`        | PTY spawn, key encoding, type/press, screen capture        |
| `wait-conditions.md`                  | `text`, `stable`, `text_gone` waits and the stable tracker |
| `tui-session-daemon.md`               | Daemon process model, IPC transports, session lifecycle    |
| `live-preview-protocol.md`            | JSON-RPC over WebSocket for streaming terminal state       |
| `clean-architecture-layout.md`        | Crate layout, dependency matrix, port traits, enforcement  |
| `agent-first-architecture.md`         | Underlying design beliefs (companion to the layout doc)    |

## What's actually novel here

Most of agent-tui is "well-known patterns assembled cleanly" — but a few
choices are non-obvious and worth lifting into Glue:

- **Stable-screen detection by hash** — three identical `DefaultHasher`
  hashes of `screen_text()` 50 ms apart is enough to call a TUI "settled".
  Cheap, deterministic, no diffing.
- **PTY reader on a kernel-fronted shutdown channel** — a second `pollfd`
  on a `socketpair` lets the reader thread block in `poll()` and still
  exit instantly on shutdown. No timeouts, no spurious wakeups.
- **Process-group SIGTERM → SIGKILL ladder** — `kill(-pid, SIGTERM)` to
  the whole group with verified `getpgid(pid) == pid` first, then a
  500 ms grace, then SIGKILL. Falls back to direct child kill if the
  child isn't a group leader. Far more reliable than `child.kill()`
  alone for shells that have spawned grandchildren.
- **JSON-RPC over WebSocket for live preview, file-based token
  handoff** — the daemon writes the authenticated WS URL to
  `~/.agent-tui/api.json`; clients read it. No port discovery dance, no
  shared secrets in env vars.
- **WebSocket as an alternate IPC transport** — same JSON-RPC envelopes
  the Unix socket uses; clients pick `unix` vs `ws` via env var
  (`AGENT_TUI_TRANSPORT`). One protocol, two carriers.
- **Compile-time architecture enforcement via Cargo crate boundaries** —
  not a Dart-portable idea, but the *principle* (make the layer rule a
  hard error, not a code-review item) maps onto Dart via package
  separation or strict imports.

## Where this maps onto Glue

The actionable hooks for Glue are:

1. A `tui_run` agent tool that spawns commands under a PTY and exposes
   `screenshot` / `press` / `type` / `wait` to the model. Either via
   `package:pty` directly, or by shelling out to `agent-tui` when present.
   See `pty-automation-primitives.md`.
2. A daemon mode for long-lived sub-process sessions (a dev server, a
   REPL, `tail -f`) that survive across Glue invocations. See
   `tui-session-daemon.md`.
3. A live-preview surface — Glue could expose a similar JSON-RPC stream
   so a browser tab can mirror what the agent sees in any sub-PTY. See
   `live-preview-protocol.md`.
4. The wait-condition vocabulary (`text` / `stable` / `text_gone`) is
   the right primitive set for any "wait for the UI to do X" tool —
   shell, TUI, or browser. See `wait-conditions.md`.

## Source provenance

- Repo: `https://github.com/pproenca/agent-tui`
- Last reviewed: 2026-04-25 against commit on `master` (release v1.0.1,
  published 2026-02-04).
- License: MIT.
- Stack: Rust workspace (`portable-pty`, `tattoy-wezterm-term` for VT
  emulation, `axum` for HTTP/WS, `tungstenite` client, `tokio` runtime).
- Web UI: Bun + xterm.js, served from the daemon at `/ui`.
