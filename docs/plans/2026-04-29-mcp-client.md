# Plan: MCP Client Support

**Status:** plan only — no code yet
**Date:** 2026-04-29 (revised; earlier draft focused on Glue-as-server)
**Companion docs:**
- `docs/plans/2026-02-27-acp-webui.md` — ACP server (the surface above us)
- `docs/plans/2026-04-29-harness-layers.md` — package layering

> **Doc title clarification.** "MCP support" in coding agents almost
> always means *being an MCP client* — connecting to user-configured
> MCP servers and surfacing their tools to the agent. That's the focus
> here. The inverse direction (Glue *as* an MCP server, exposing its
> own tools to other agents) is sketched in the appendix and deferred
> to a separate plan.

## Why

Every modern coding agent — Claude Desktop, Cursor, Zed, Continue,
Cline, RooCode — lets users plug in
[Model Context Protocol](https://modelcontextprotocol.io/) servers to
extend the agent's capabilities without a code change. You install
`@modelcontextprotocol/server-filesystem`, `…/server-postgres`,
`…/server-github` (or any third-party server) and the agent can
suddenly read your DB, query your repo, search your wiki, etc.

Glue should match. Without it, every new capability needs a Dart
`Tool` implementation in `glue_strategies/`. With it, the long tail of
integrations becomes a config-only addition.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Agent loop (glue_harness)                                       │
│   AgentCore + ToolRegistry                                      │
│   ▲                                                             │
│   │ Tool.execute() — same call shape for native + MCP-sourced   │
│   │                                                             │
│ ┌─┴────────────────┐   ┌────────────────────────────────────┐   │
│ │ Native Tools     │   │ MCP-backed Tools (one per server   │   │
│ │ ReadFileTool …   │   │ tool, registered at session start) │   │
│ └──────────────────┘   └─────────────┬──────────────────────┘   │
│                                      │                          │
└──────────────────────────────────────┼──────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────┐
│ packages/glue_strategies/lib/src/mcp_client/                    │
│   • McpClient        — JSON-RPC dispatch over a transport       │
│   • McpClientPool    — one client per configured server         │
│   • McpToolFactory   — turns MCP tool descriptors into          │
│                         glue_core Tool impls                    │
│   • McpServerSpec    — typed config (stdio | http+sse | ws)     │
│   • Transports       — stdio (subprocess), HTTP+SSE, WebSocket  │
└─────────────────────────────────────────────────────────────────┘
```

The client sits in `glue_strategies` because each MCP server is an
external service — same shape as LLM providers and search providers.

## Configuration

User declares servers in `~/.glue/config.yaml`, with per-project
overrides in `.glue/config.yaml` near the project root:

```yaml
mcp:
  servers:
    # stdio transport — most common; matches Claude Desktop config shape
    filesystem:
      command: "npx"
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/work"]
      env:
        DEBUG: "false"

    # http+sse with bearer token
    company-wiki:
      url: "https://mcp.example.com/wiki"
      auth:
        kind: bearer
        token: "${WIKI_MCP_TOKEN}"   # see § Auth → env-var expansion

    # http+sse with OAuth (discovery-driven)
    notion:
      url: "https://mcp.notion.com"
      auth:
        kind: oauth
        # discovery, dynamic client registration, and token storage are
        # all handled by glue's OAuth flow. No client_id needed here
        # for servers that support DCR (RFC 7591).

    # disabled servers stay in config but skip the connect step
    postgres:
      command: "/usr/local/bin/mcp-postgres"
      enabled: false

  # global per-tool policy applied across all servers
  tool_policy:
    auto_approve:
      - "filesystem.read_file"
      - "filesystem.list_directory"
    deny:
      - "*.delete_file"     # never expose this name from any server

  # connection lifecycle (see § Connection lifecycle for defaults)
  reconnect:
    enabled: true
    initial_delay_ms: 500
    max_delay_ms: 30000
    max_attempts: 10        # per server, resets after a successful connect
  call_timeout_seconds: 30  # default; overridable per-server
```

ACP integration: `session/new`'s params already accept `mcpServers`.
When a client passes that, Glue's ACP delegate uses *that* list for
the session instead of (or in addition to — see open question) the
config.yaml list. This matches how Zed, Claude Desktop, etc. behave.

## Auth

Three authentication modes ship in v1:

### Bearer token

For HTTP+SSE / WebSocket transports. Token comes from one of
(in priority order):

1. `auth.token` literal in config (discouraged — leaks via dotfile sync)
2. `auth.token: "${ENV_VAR}"` interpolation from the process env
3. Glue's `CredentialStore` under the key `mcp:<server-id>:bearer`
   (set via `glue mcp auth set <server> --bearer …` — encrypted at rest)

**Env-var expansion** happens at config-load. Missing var → load fails
loudly with the server name and the missing var. (We don't lazy-load
because lazy means the user finds out at session start, after waiting
through provider init.) Empty string is treated as missing.

### OAuth 2.1 (Authorization Code + PKCE)

Required by the upstream MCP spec for HTTP transports beginning with
the 2025-03-26 protocol revision. Flow:

1. **Discovery** — `GET /.well-known/oauth-authorization-server` from
   the MCP server's base URL. We honour `authorization_endpoint`,
   `token_endpoint`, `registration_endpoint` (RFC 8414).
2. **Dynamic Client Registration** — `POST` to `registration_endpoint`
   with our redirect URI, client name `glue`, logo URL. Response gives
   `client_id` (+ optional `client_secret` for confidential clients).
   We persist these per-server in `CredentialStore` so re-registration
   only happens on first connect.
3. **Authorization** — open the user's browser to
   `authorization_endpoint` with PKCE challenge + a fresh `state`. We
   bind a one-shot loopback HTTP server on `127.0.0.1:0` that the user
   is redirected back to with the authorization code. The server then
   shuts down. If the user dismisses the browser, the loopback server
   times out after 5 minutes.
4. **Token exchange** — POST to `token_endpoint`, get `access_token` +
   `refresh_token` + `expires_in`. Stored encrypted in
   `CredentialStore` under `mcp:<server-id>:oauth`.
5. **Per-call** — `Authorization: Bearer <access_token>`. On 401 with
   `error=invalid_token`, refresh once using the stored refresh token
   and retry. If refresh fails (revoked, expired refresh token), emit
   `McpServerAuthRequiredEvent` (see § MCP event vocabulary) and pause the
   server until the user re-authorises via `glue mcp auth login`.

This reuses the existing OAuth state machine generalised from
`CopilotAdapter` — same loopback-redirect mechanics, same encrypted
credential store, just driven by discovery rather than hardcoded
endpoints.

### None (stdio implicit trust)

Subprocesses spawned over stdio are implicitly trusted — the user
launched them. No auth header. The integrity story is process
isolation + env hygiene (next section).

### stdio env hygiene

By default a stdio server's subprocess gets a **scrubbed** environment:
`PATH`, `HOME`, `LANG`, `TERM`, `USER`, `SHELL`, the OS-specific
homologues, and *only* the keys explicitly listed in the server's
`env:` block. This prevents the user's `OPENAI_API_KEY` /
`AWS_SECRET_ACCESS_KEY` / `~/.netrc` indirections from leaking to
every MCP server they install.

(Claude Desktop currently inherits the full parent env. We're
intentionally stricter; it's `mcp.subprocess_env: full` in
`glue_config.yaml` to opt out.)

### Process lifecycle for stdio

- Spawned with `start_mode: detached: false` so the child dies if
  Glue dies. On Linux additionally `PR_SET_PDEATHSIG = SIGTERM` to
  guarantee orphan-free exit; on macOS we use a watchdog. Without
  this, killed-Glue → zombie MCP processes is a real problem.
- Clean shutdown: `SIGTERM` → wait 2s → `SIGKILL`.
- Crash-loop detection: if a server respawns >5 times in 60 seconds
  it's marked dead for the rest of the session and an
  `McpServerError` event fires.

### Credential storage

Everything sensitive (bearer tokens supplied via `glue mcp auth set`,
OAuth tokens, registered client_secrets) lives in the existing
`CredentialStore` under namespaced keys:

| Key                                | Value                            |
|------------------------------------|----------------------------------|
| `mcp:<server-id>:bearer`           | the literal bearer token         |
| `mcp:<server-id>:oauth.access`     | access token + expires_at        |
| `mcp:<server-id>:oauth.refresh`    | refresh token                    |
| `mcp:<server-id>:oauth.client_id`  | DCR-issued client id             |
| `mcp:<server-id>:oauth.client_secret` | DCR-issued secret (if any)    |

`CredentialStore` is already encrypted-at-rest and shared across
sessions, so re-auth survives Glue restarts.

## Tool registration flow

1. **Session start.** When the harness builds a session (via
   `ServiceLocator` or the ACP `CliAcpDelegate`), it constructs an
   `McpClientPool` from the resolved `mcp.servers` config + any
   session-scoped servers.
2. **Connect + initialize.** For each server, `McpClient.initialize()`
   negotiates the protocol version, gets server capabilities. Servers
   that fail to start are logged and skipped — they don't kill the
   session.
3. **List tools.** `tools/list` returns each server's tool descriptors.
4. **Wrap as `Tool`.** Each MCP descriptor becomes a `_McpTool`
   instance — `Tool` subclass that delegates `execute()` to
   `mcpClient.callTool(name, args)`.
5. **Register.** All `_McpTool`s are added to the agent's
   `ToolRegistry` alongside native ones. Names are namespaced
   `<server>.<tool>` to avoid collisions (Claude Desktop convention).

## Naming and namespacing

| Native tool name           | MCP tool full name                    |
|----------------------------|---------------------------------------|
| `read_file`                | (unchanged — built-in)                |
| `filesystem.read_file`     | server `filesystem`, tool `read_file` |
| `github.search_issues`     | server `github`, tool `search_issues` |

When a server's name itself matches a native tool, the native one
wins; the MCP-sourced version is logged and skipped. The `tool_policy`
allowlists / denylists apply to the namespaced name.

## Permission model

MCP-sourced tools route through the **same** `PermissionGate` as
native ones. The gate sees them by name; the surface displays:

- the tool name (`filesystem.write_file`)
- the source server (`filesystem` from `~/.glue/config.yaml`)
- the rendered arguments

Editor / web UIs already get this for free via ACP's
`session/request_permission`: the `title` field carries the namespaced
name and the `rawInput` carries the args. We add an optional
`source_server` extension field for surfaces that want to show
provenance separately.

For external MCP clients connecting to *us* (the inverse direction —
appendix), we'd never proxy permission decisions to a downstream MCP
server; tools come from us, permission stays with us.

## Transports

| Transport | When to use                  | Library                        |
|-----------|------------------------------|--------------------------------|
| stdio     | Default; matches the config shape Claude Desktop / Cursor use. The MCP server is a subprocess Glue spawns and pipes JSON-RPC over stdin/stdout. | `dart:io.Process` + reuse `glue_server`'s `LineDelimitedTransport` |
| HTTP + SSE| Remote servers (company-hosted, cloud APIs). HTTP for client→server requests, SSE for server→client notifications. | `package:http` + a tiny SSE decoder (we already have one in `glue_strategies/llm/sse.dart`) |
| WebSocket | Symmetric, single connection. Useful for browser-bridged servers and future glue↔glue connections. | `dart:io.WebSocket` (or `package:web_socket_channel` if we need cross-platform) |

`McpClient` is transport-agnostic — it speaks JSON-RPC against an
`McpTransport` interface. We can reuse `glue_server`'s
`JsonRpcMessage` types and `JsonRpcTransport` interface verbatim
(MCP is JSON-RPC 2.0, same as ACP).

## Capability negotiation

On `initialize`, advertise:

```json
{
  "capabilities": {
    "roots": { "listChanged": true }
  },
  "clientInfo": {
    "name": "glue",
    "version": "<from glue_core/AppConstants.version>"
  },
  "protocolVersion": "2025-03-26"
}
```

- **`roots`** — tells the server which dirs Glue is operating in.
  Servers like `filesystem` use this to scope access. Glue advertises
  the cwd from `session/new` (or the project root if detected).
  `listChanged` because cwd can change mid-session.
- **`sampling`** — *not* advertised in v1. If a server's `initialize`
  response lists `sampling` in `serverCapabilities` *and* its tool
  descriptors require it, we emit `McpServerError(reason:
  unsupported_capability)`, mark the server unavailable, and surface
  in `glue mcp test`. Failing loud at connect rather than at first
  call.

### Protocol version handling

Glue pins `MCP_PROTOCOL_VERSION` to `"2025-03-26"` per release. Server
responses are negotiated as follows:

| Server's `protocolVersion` response                    | Action                                                  |
|--------------------------------------------------------|---------------------------------------------------------|
| Equal to ours                                          | Continue.                                               |
| One we know about but older (within 12 months)         | Continue with downgrade flag — we suppress messages we know don't exist on the older spec. Logged. |
| Newer than ours                                        | Continue with upgrade-tolerant mode — we ignore unknown notification types from the server (we don't *send* anything new) and warn at connect. |
| Unparseable, or older than our minimum-supported (currently 2024-11-05) | Refuse. Emit `McpServerError(reason: protocol_too_old)` and disable. |

The client never silently sends messages the server can't understand
— spec downgrade is a one-way truncation of what *we* emit.

## Connection lifecycle

The agent loop keeps running when any individual MCP server is flaky.
This section specifies *exactly* what happens at each transition.

### State machine (per server)

```
disconnected ──connect attempt──▶ connecting
                                      │
                                      ├── ok ──▶ connected ──drop──▶ reconnecting
                                      │              │                   │
                                      │              │                   ├── retries left ──▶ reconnecting (backoff)
                                      │              │                   └── exhausted ─────▶ dead
                                      └── fail ──▶ reconnecting (backoff)
                                                       │
                                                       └── max_attempts ──▶ dead
```

### Drop detection

- **stdio**: child stdout EOF or non-zero exit → drop.
- **HTTP+SSE**: SSE stream disconnect, or 5xx on the next request → drop.
- **WebSocket**: `WebSocket.close` with non-1000 code, or absent
  pong-on-ping after 30s → drop.

### Backoff (with jitter)

```
attempt N delay = clamp(initial * 2^(N-1), 0, max) ± random(0, 0.3 * delay)
```

Defaults: `initial=500ms`, `max=30s`, `max_attempts=10` per server.
Reset to attempt 0 after any successful `tools/list` round-trip.
Exhausting `max_attempts` transitions the server to `dead` for the
session; `glue mcp reconnect <server>` (or restarting the session)
clears it.

### In-flight `tools/call` during a drop

| State at drop          | Behaviour                                            |
|------------------------|------------------------------------------------------|
| Pending response       | Resolve as `ToolResult(success: false, summary: "server disconnected", metadata: {"retryable": true})` immediately. Do not auto-retry — the agent loop decides whether to retry or change tack. |
| Queued (rate-limited)  | Reject with the same shape.                          |
| New call while reconnecting | Reject immediately with `"server reconnecting"`. The agent typically waits / picks another tool. |

We never auto-replay tool calls. Even reads can have side effects
(rate-limit charges, audit log entries). Replay is the agent's call.

### Crash-loop and dead state

A server that respawns/reconnects ≥5 times in 60s is marked `dead`
without further attempts. Avoids hot-looping a broken server and
spamming the user with reconnect events.

### Hot config reload (deferred)

v1: config changes apply at next session. Hot reload is a v2 feature
(open question on whether mid-session pool reconfiguration is worth
the complexity).

## MCP event vocabulary

New `SessionEvent` variants in `glue_core` (sealed-extending the
existing hierarchy in `session_event.dart`). Surfaces — TUI, ACP
clients, observability sinks — pattern-match exhaustively.

```dart
class McpServerConnectedEvent extends SessionEvent {
  final String serverId;
  final String serverVersion;            // from initialize response
  final List<String> toolNames;          // namespaced
}

class McpServerDisconnectedEvent extends SessionEvent {
  final String serverId;
  final McpDisconnectReason reason;      // dropped | shutdown | crashLoop | dead
  final int reconnectAttempt;            // 0 if not retrying
  final Duration nextAttemptIn;          // Duration.zero if dead
}

class McpServerErrorEvent extends SessionEvent {
  final String serverId;
  final McpErrorKind kind;
    // protocolTooOld | unsupportedCapability | authFailed
    // | spawnFailed | crashLoop
    // (authRequired is its own event below)
  final String message;                  // human-readable
}

class McpServerAuthRequiredEvent extends SessionEvent {
  final String serverId;
  final String reauthCommand;            // e.g. "glue mcp auth login notion"
  // Surfaces remediate by: TUI shows a banner with the command;
  // ACP clients can show a notification + button.
}

class McpToolListChangedEvent extends SessionEvent {
  final String serverId;
  final List<String> added;              // namespaced
  final List<String> removed;
}
```

### ACP surface for MCP events

ACP doesn't have native MCP-status notifications. v1 strategy:

- Reflect them as `session/update` notifications using a
  Glue-extension `sessionUpdate: "glue_mcp_status"` discriminator. The
  payload mirrors the `SessionEvent` variant. Clients that don't
  recognise the type ignore it (forward-compatible).
- `McpServerAuthRequiredEvent` *additionally* triggers a
  `session/request_permission`-shaped request with a single `oauth`
  option, so editors that already render the permission modal get
  re-auth UX for free.
- `tools/call` failures continue to flow as `tool_call_update(failed)`
  with the disconnect reason in the content text.

### TUI surface

- New `/mcp` slash command opens a status panel listing each
  configured server, its connection state, last error, tool count.
- Status-bar indicator when *any* server is in `reconnecting` or
  `dead`: `MCP: 2 dead, 1 reconnecting`.
- Inline system-message on `McpServerDisconnectedEvent` with a hint
  about `/mcp reconnect <server>` if applicable.

### Observability

Every event is logged as a span on the current `Observability` sink
(reusing the existing infrastructure). OpenTelemetry users get them
as structured events on the session's parent span; debug builds
write them to the per-session log file.

## Concurrency

- **Multiple in-flight `tools/call` per server.** Supported. JSON-RPC
  correlates by id; the `McpClient` keeps a `Map<int, Completer>` for
  pending calls. The agent already invokes tools via `Future.wait`
  for parallelism; this just extends to MCP-sourced tools.
- **Server-side rate limiting.** When a server returns a JSON-RPC
  error with `code == -32011` (Glue-reserved for rate limit) or an
  HTTP 429, `McpClient` waits the `Retry-After` (HTTP) or
  `data.retry_after_seconds` (JSON-RPC) hint, then retries the call
  *once* before surfacing as failure. Configurable per server.
- **Backpressure.** No explicit limit on concurrent calls per server.
  If a server can't handle parallelism it should rate-limit; we
  honour the response.

## Testing strategy

- **Unit tests** — `McpToolFactory` wraps a synthetic descriptor;
  `_McpTool.execute()` against a stub `McpClient` that returns canned
  responses. Permission gate unaffected (existing tests cover that).
- **Integration tests** — spawn the official
  `@modelcontextprotocol/server-everything` reference server as a
  subprocess in tests; assert tool listing + invocation round-trips.
  Tagged `@Tags(['integration'])` because it requires Node.
- **Conformance** — periodically run the
  [`mcp-spec` test harness](https://github.com/modelcontextprotocol)
  against `McpClient`. Nightly CI.

## CLI surface

```sh
# inspect / debug user-configured servers
glue mcp list                # configured servers + state (connected/dead/…)
glue mcp tools <server>      # tools advertised by one server
glue mcp call <server> <tool> --arg key=value
glue mcp test <server>       # ping initialize + tools/list
glue mcp reconnect <server>  # clear `dead` state, retry immediately

# auth helpers
glue mcp auth set <server> --bearer    # prompts for token, stores encrypted
glue mcp auth login <server>           # OAuth: opens browser, completes flow
glue mcp auth logout <server>          # forgets stored credentials
glue mcp auth status                   # per-server: bearer | oauth(expires…) | none

# in-session toggles
/mcp                          # slash command: status panel
/mcp toggle <server>          # disable/enable for the current session
/mcp reconnect <server>       # same as the top-level command
/mcp call <server>.<tool>     # invoke directly without the agent
```

## Implementation order

1. **`glue_strategies/mcp_client/protocol.dart`** — shared MCP message
   types (initialize, tools/list, tools/call, tools/list_changed,
   server `error`/auth shapes). Reuses `glue_server`'s
   `JsonRpcMessage` for transport.
2. **`mcp_client/transport/stdio.dart`** — subprocess spawn + stdio
   pipe with the env-hygiene + PR_SET_PDEATHSIG + crash-loop logic
   from § Connection lifecycle.
3. **`mcp_client/client.dart`** — `McpClient`: initialize (with
   protocol-version negotiation), list tools, call tool with the
   concurrent-id pending map, rate-limit retry, drop/reconnect state
   machine.
4. **`mcp_client/connection_state.dart`** — sealed
   `McpConnectionState` (disconnected / connecting / connected /
   reconnecting / dead) + the backoff-with-jitter helper.
5. **MCP `SessionEvent` variants** — five new sealed-extending types
   in `glue_core/session_event.dart`:
   `McpServerConnectedEvent`, `McpServerDisconnectedEvent`,
   `McpServerErrorEvent`, `McpServerAuthRequiredEvent`,
   `McpToolListChangedEvent`. Update the exhaustiveness test.
6. **`mcp_client/tool_factory.dart`** — wraps an MCP tool descriptor
   into a glue_core `Tool` impl whose `execute()` calls the client
   (and whose `disabled`/`unavailable` state reflects connection
   state).
7. **`mcp_client/pool.dart`** — `McpClientPool`: holds N clients,
   one per configured server; eager-connect on session start
   (non-blocking), lifecycle, drives reconnect.
8. **Config plumbing** — `mcp:` section in `glue_config.yaml`,
   parsed by `glue_harness`'s `GlueConfig`. Env-var expansion at
   load (with missing-var diagnostics). Reconnect / call_timeout
   defaults.
9. **Bearer auth** — config + `CredentialStore` integration + the
   `glue mcp auth set` subcommand.
10. **OAuth 2.1 (PKCE + DCR)** — generalise the existing Copilot
    OAuth machinery in `glue_strategies/providers/auth_flow.dart`:
    discovery (`/.well-known/oauth-authorization-server`), DCR
    (`registration_endpoint`), loopback redirect, encrypted token
    storage, refresh-on-401-once. Surfaces as
    `glue mcp auth login <server>` and the typed
    `McpServerAuthRequiredEvent`.
11. **`ServiceLocator` integration** — at session start, build the
    pool from config + any session-scoped servers, register tools.
12. **ACP integration** — `CliAcpDelegate.createSession` honours
    `SessionNewParams.mcpServers`. MCP `SessionEvent`s map to the
    Glue-extension `glue_mcp_status` `session/update` payloads.
    `McpServerAuthRequiredEvent` additionally surfaces a
    `session/request_permission`-shaped re-auth request.
13. **`glue mcp` CLI subcommands** — list / tools / call / test /
    reconnect / auth (set/login/logout/status).
14. **In-session `/mcp` slash commands** — status panel, toggle,
    reconnect, direct invocation.
15. **HTTP+SSE transport.** Includes the SSE drop-detection +
    reconnect path.
16. **WebSocket transport.**
17. **`tools/list_changed` reactivity.** Subscribe at connect; on
    notification refresh the server's tool list, diff against last,
    emit `McpToolListChangedEvent` with added/removed.
18. **Conformance harness in CI.** Run the official
    `@modelcontextprotocol/server-everything` reference server in
    nightly + assert tool round-trips and the connection-lifecycle
    behaviours.

Estimated total: ~1200–1500 lines across `mcp_client/` plus
glue_core event additions + harness + ACP integration. The OAuth
and connection-lifecycle additions roughly double the original
estimate. Resources / prompts (`resources/*`, `prompts/*`) are
deferred to v2 — see § Out of scope.

## Out of scope for v1

- **`sampling` capability** — letting MCP servers ask Glue's LLM to do
  work. Powerful but rare. We refuse-with-error rather than partially
  support; deferred until we see real demand.
- **`roots/listChanged` notifications going *out*** — we advertise the
  capability but don't push updates yet (cwd is fixed for the session
  in v1 anyway).
- **Resources** (`resources/*`) and **prompts** (`prompts/*`) —
  v2; tool support is the most-requested.
- **Hot config reload.** Config changes apply at next session.
- **Confidential clients (OAuth client_secret in config).** v1 only
  supports public clients (PKCE-only) and DCR-issued credentials.
- **OS keychain integration.** v1 stores credentials in
  `CredentialStore`'s encrypted file. Keychain (macOS Keychain,
  Linux Secret Service) is a follow-up.
- **Inline server install** (`glue mcp install <pkg>`) — the user
  installs servers themselves with `npm`/`brew`/whatever; we just
  consume them.

## Open questions

These need a decision before coding ships, but each has a recommended
default that the doc above already assumes.

1. **Session vs. global config precedence.** When ACP's
   `session/new.mcpServers` is non-empty *and* `~/.glue/config.yaml`
   has servers, do we union, override, or replace? Claude Desktop /
   Cursor use *only* the editor's list per-session.
   **Recommended:** match — replace, not union. The editor is the
   source of truth for that session.
2. **Auto-approve names over ACP.** Should we expose
   `tool_policy.auto_approve` to the editor (in the `glue_mcp_status`
   payload) so it can suppress the permission modal client-side?
   **Recommended:** no — the gate runs in the harness regardless;
   leaking the policy doesn't change behaviour and makes the auth
   surface confusing.
3. **Eager vs lazy connect.** Eagerly at `session/new` makes the
   first tool call snappy; lazily defers the cost.
   **Recommended:** eager + non-blocking (fire all `connect()`s in
   parallel, don't await). `tools/list` populates the registry as
   each completes; `McpToolListChangedEvent` fires when each lands.
4. **OAuth on stdio.** The MCP spec auth section is HTTP-focused.
   For stdio servers that nevertheless want OAuth (some Anthropic
   examples bridge a stdio shim to an OAuth API), do we support it?
   **Recommended:** v1 = no. stdio is implicitly trusted; OAuth-style
   stdio servers can use an envelope auth header passed via env.
5. **Server identity for credential keys.** OAuth + bearer keys
   namespace by `<server-id>`, but the user can rename a server in
   their config. Re-authing every rename is annoying.
   **Recommended:** keys are by server-id (the user's chosen name).
   Renaming → user re-auths once. Document the trade-off.
6. **`tool_policy.deny` patterns.** Glob-style (`*.delete_file`)?
   Exact match only?
   **Recommended:** glob with `*` and `?` wildcards, scoped to the
   namespaced name. Same matcher we'd use for any allow/deny lists.

---

## Appendix: Glue *as* an MCP server (deferred)

The inverse direction — exposing Glue's native tools (`read_file`,
`bash`, `web_*`, skills) so other agents can use them — has its own
plan deferred to a separate doc. Sketch:

- `packages/glue_server/lib/src/mcp/` — sibling to `acp/`. Same
  `JsonRpcTransport` plumbing.
- `tools/list` reflects the harness's `ToolRegistry`; `tools/call`
  routes through `Tool.execute()` with `PermissionGate` carrying
  over.
- Resources: `glue://sessions`, `glue://skills`, `glue://catalog`
  read-only.
- Prompts: the system prompt + skill prompts.
- Transport: stdio (matches Claude Desktop config shape) and HTTP+SSE.
- Useful when integrating with: Claude Desktop config blocks, Cursor
  (which supports MCP servers as tool sources), agent frameworks that
  want Glue's session machinery as a building block.

The inverse plan can land later without disturbing the client work,
since both directions share `glue_server`'s JSON-RPC plumbing.
