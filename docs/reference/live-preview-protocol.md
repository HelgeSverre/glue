# Live Preview Protocol

agent-tui ships a browser-based live preview of every running session.
The interesting part is not the UI (xterm.js wrapper, ~standard) but
the **protocol** that makes a daemon-owned PTY mirrorable into a browser
tab without any custom client code beyond JSON-RPC over WebSocket.

This is the most directly portable surface for Glue: if Glue ever wants
"watch the agent's terminal from another window," the same protocol
shape works.

## Topology

```text
┌────────────┐       /ui (HTTP)        ┌─────────────┐
│  browser   │ ──────────────────────► │   daemon    │
│  + xterm   │       /ws (WS)          │   axum      │
│            │ ◄══════════════════════►│   server    │
└────────────┘     JSON-RPC frames     └──────┬──────┘
                                              │ owns
                                              ▼
                                         PTY sessions
```

The daemon embeds a single-page app (built once, served at `/ui`). It
also exposes:

- `GET /` → 307 redirect to `/ui?ws=<authenticated-ws-url>`
- `GET /ui` → the embedded SPA
- `GET /ws` → WebSocket upgrade endpoint
- `GET /api/v1/stream` → legacy alias for `/ws`

Both UI and CLI clients converge on the same `/ws` endpoint.

## Authentication: file-based token handoff

Token handoff is the cleanest part. Two-line summary:

1. **The daemon writes its authenticated WS URL to a file**:
   `~/.agent-tui/api.json` (overrideable via `AGENT_TUI_WS_STATE`).
2. **Clients read the file** to learn both the port and the token.

```json
{
  "ws_url": "ws://127.0.0.1:53129/ws?token=eyJ..."
}
```

That's it. No port discovery dance. No env-var leakage. Filesystem
permissions on `~/.agent-tui/` are the access control. The browser is
handed the URL through the redirect query string (`/ → /ui?ws=…`),
which the daemon constructs server-side so the token never needs to
appear in client-side code.

For Glue, this is reusable as-is. Write the URL to
`~/.glue/live.json`; CLI consumers and browser bookmarks both work
without further coordination.

## Authorization rules

- Tokens go in the `token=` query parameter on the `/ws` upgrade.
- Browser requests (those with an `Origin` header) must match the
  daemon UI origin. Cross-origin upgrades get 403.
- Concurrent WS connections are capped (`AGENT_TUI_WS_MAX_CONNECTIONS`,
  default 32). Excess gets 503.
- Binary frames are rejected — all data is text JSON-RPC.

## JSON-RPC envelopes

Standard JSON-RPC 2.0 over text WebSocket frames, one frame per
message. Two methods matter for live preview.

### `live_preview_stream`

Subscribe to a session's terminal output. The daemon sends one initial
"render the whole screen now" frame, then an incremental update for
every subsequent change.

Request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "live_preview_stream",
  "params": { "session": "abc12345" }
}
```

`session` may be a literal id or `"active"` to follow whatever the
active session is at any given moment. Switching the active session at
the daemon flips all `active`-following streams.

Successful frames look like:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "kind": "init" | "delta",
    "payload_base64": "<base64-encoded-bytes>",
    "cursor": { "row": 0, "col": 0, "visible": true },
    "size": { "cols": 80, "rows": 24 }
  }
}
```

Terminal output is delivered as base64 inside the JSON `result`
because plain JSON strings can't carry arbitrary control bytes
faithfully (CR, ESC, NUL all confuse parsers somewhere along the
pipeline). xterm.js gets exactly the byte sequence the program
emitted; it does its own ANSI parsing.

### `flightdeck_stream`

A second method that streams the **session inventory** — a live view of
which sessions exist, which is active, what their PIDs and sizes are.
Used by the UI to show a session list that updates without polling.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "flightdeck_stream"
}
```

Successful frames carry a snapshot of `{ sessions: [...], active: "..." }`
on every change.

## Error envelopes

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": { "code": -32603, "message": "session not found: abc12345" }
}
```

agent-tui uses standard JSON-RPC error codes plus an `ErrorCategory` in
the message for programmatic dispatch. The codes themselves stay
generic; the category tag is what lets a client know whether to retry,
reconnect, or surface to the user.

## What makes this design good

- **Single endpoint, multiple subscriptions.** One WS connection can
  carry both a `live_preview_stream` and a `flightdeck_stream`
  subscription concurrently — they're just different `id`s. No
  per-stream socket setup.
- **Same protocol, two carriers.** The `/ws` JSON-RPC surface and the
  Unix-socket JSON-RPC surface accept the same envelopes. A CLI
  command that runs locally over Unix can run remotely over WS by
  flipping `AGENT_TUI_TRANSPORT`.
- **Base64 for terminal bytes.** Avoids every encoding pitfall around
  control characters in JSON strings. The cost is ~33 % bandwidth
  inflation, which is irrelevant for terminal traffic volume.
- **`"active"` as a sentinel session id.** Lets the UI follow whatever
  the user is doing in the CLI without re-subscribing on every switch.

## Where this lives in agent-tui

| Concern                        | File                                                       |
| ------------------------------ | ---------------------------------------------------------- |
| HTTP/WS server                 | `cli/crates/agent-tui-app/src/...` (axum)                  |
| Live preview RPC               | `cli/crates/agent-tui-adapters/src/adapters/rpc/...`       |
| Token + URL state file         | `~/.agent-tui/api.json` (path via `AGENT_TUI_WS_STATE`)    |
| Embedded UI                    | `web/src/` (Bun + xterm.js), built and embedded at compile |
| OpenAPI / AsyncAPI specs       | `docs/api/openapi.yaml`, `docs/api/asyncapi.yaml`          |
