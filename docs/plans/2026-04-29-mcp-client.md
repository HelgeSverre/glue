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

    # http+sse transport
    company-wiki:
      url: "https://mcp.example.com/wiki"
      headers:
        Authorization: "Bearer ${WIKI_MCP_TOKEN}"

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
```

ACP integration: `session/new`'s params already accept `mcpServers`.
When a client passes that, Glue's ACP delegate uses *that* list for
the session instead of (or in addition to — see open question) the
config.yaml list. This matches how Zed, Claude Desktop, etc. behave.

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
    "roots": { "listChanged": true },
    "sampling": {}
  },
  "clientInfo": {
    "name": "glue",
    "version": "<from glue_core/AppConstants.version>"
  },
  "protocolVersion": "2024-11-05"
}
```

- **`roots`** — tells the server which dirs Glue is operating in.
  Servers like `filesystem` use this to scope access. Glue advertises
  the cwd from `session/new` (or the project root if detected).
  `listChanged` because cwd can change mid-session.
- **`sampling`** — placeholder. Glue won't proxy LLM calls back to MCP
  servers in v1; deferred. Some servers (`mcp-langchain`,
  `mcp-search-and-summarize`) use sampling to ask the *client's* LLM
  to do work. v2.

## Error handling

The agent loop must keep running when any individual MCP server is
flaky. Concrete behaviours:

- **Server fails to start** → log, skip its tools, continue session.
- **`tools/list` errors** → cache the last good list (per-server),
  retry on next session.
- **`tools/call` errors** → return as `ToolResult(success: false, ...)`
  — same shape as a native tool failing. The agent can recover.
- **Connection drops mid-session** → mark all of that server's tools
  as unavailable. Future `tools/list_changed` notifications can
  resurrect them.
- **Slow server** → 30s default timeout per `tools/call`, configurable
  per server. Surface as `success: false` with a "timeout" summary.

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
glue mcp list                # list configured servers + connection state
glue mcp tools <server>      # list tools advertised by one server
glue mcp call <server> <tool> --arg key=value
glue mcp test <server>       # ping initialize + tools/list

# in-session toggles
/mcp                          # slash command: list servers + their tools
/mcp toggle <server>          # disable/enable for the current session
/mcp call <server>.<tool>     # invoke directly without the agent
```

## Implementation order

1. **`glue_strategies/mcp_client/protocol.dart`** — shared MCP message
   types (initialize, tools/list, tools/call, …). Reuses
   `glue_server`'s `JsonRpcMessage` for transport.
2. **`mcp_client/transport/stdio.dart`** — subprocess spawn + stdio
   pipe. (HTTP+SSE and WebSocket transports follow.)
3. **`mcp_client/client.dart`** — `McpClient`: initialize, list tools,
   call tool. Handles request correlation by id.
4. **`mcp_client/tool_factory.dart`** — wraps an MCP tool descriptor
   into a glue_core `Tool` impl whose `execute()` calls the client.
5. **`mcp_client/pool.dart`** — `McpClientPool`: holds N clients, one
   per configured server; lifecycle and lazy-connect logic.
6. **Config plumbing** — `mcp:` section in `glue_config.yaml`, parsed
   by `glue_harness`'s `GlueConfig`. (`glue_harness` is allowed to
   import strategies via the path dep, so it can drive the pool.)
7. **`ServiceLocator` integration** — at session start, build the
   pool from config + any session-scoped servers, register tools.
8. **ACP integration** — `CliAcpDelegate.createSession` honours
   `SessionNewParams.mcpServers` (passed by the editor/web client).
9. **`glue mcp` CLI subcommands** — list/test/call helpers for
   debugging.
10. **In-session `/mcp` slash commands** — visibility toggles, manual
    invocation.
11. **HTTP+SSE transport.**
12. **WebSocket transport.**
13. **`tools/list_changed` reactivity.** When a server pushes the
    notification, refresh its tool list mid-session and update the
    agent's registry.
14. **Server-side resources / prompts** — MCP servers can also expose
    *resources* (`resources/list`, `resources/read`) and *prompts*
    (`prompts/list`, `prompts/get`). v2: surface these as
    `glue://mcp/<server>/...` for the agent to read, and as a
    `/prompts` slash command for users.

Estimated total: ~800–1000 lines across `mcp_client/` plus harness +
ACP integration.

## Out of scope for v1

- **`sampling` capability** — letting MCP servers ask Glue's LLM to do
  work. Powerful but rare; deferred until we see real demand.
- **`roots/listChanged` notifications going *out*** — we advertise the
  capability but don't push updates yet.
- **Resources** (`resources/*`) and **prompts** (`prompts/*`) —
  v2; tool support is the most-requested.
- **Multi-tenant auth, key management** — config files are the v1
  story. A keychain integration comes later.
- **Inline server install** (`glue mcp install <pkg>`) — the user
  installs servers themselves with `npm`/`brew`/whatever; we just
  consume them.

## Open questions

1. **Session vs. global config precedence.** When ACP's
   `session/new.mcpServers` is non-empty *and* `~/.glue/config.yaml`
   has servers, do we union, override per-session, or use only the
   ACP list? Claude Desktop / Cursor seem to use only the editor's
   list per-session. Same here? Or layered?
2. **Auto-approve names.** ACP carries the namespaced name in
   `request_permission.title`. Should we expose `tool_policy.auto_approve`
   to the editor so it can suppress the modal locally? (Trade-off:
   visibility vs. convenience.)
3. **Server warmup** — connect lazily (on first tool invocation) or
   eagerly at session start? Eagerly is better UX but slower
   `session/new` if a server is sluggish. Probably eager with a
   non-blocking connect + per-call retry on failure.
4. **Spec versioning.** The MCP spec bumps occasionally. We pin one
   `protocolVersion` per release; if a server speaks a newer one, do
   we negotiate down or refuse? Spec says negotiate.

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
