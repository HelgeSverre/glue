# Plan: MCP Server Support

**Status:** sketch
**Date:** 2026-04-29
**Companion docs:**
- `docs/plans/2026-02-27-acp-webui.md` — ACP server (the surface above us)
- `docs/plans/2026-04-29-harness-layers.md` — package layering

## Why

[Model Context Protocol](https://modelcontextprotocol.io/) is the de-facto
standard for exposing tools, prompts, and resources to LLM agents. Glue
already *consumes* MCP indirectly through future strategies, but it
should also *expose* its native tools as an MCP server so other agents
(Claude Desktop, Cursor, Zed, custom agents) can use them.

There are two complementary integrations:

1. **MCP server (host)** — Glue exposes its own tools (`read_file`,
   `bash`, `web_search`, `web_browser`, `web_fetch`, skills, subagents)
   as an MCP server that other clients can connect to.
2. **MCP client** — Glue connects to user-configured MCP servers and
   surfaces their tools to the agent. ACP's `session/new` already
   accepts `mcpServers` — Glue's ACP server forwards that config to a
   per-session MCP client pool.

This doc focuses on **#1 (MCP server)**. #2 is sketched at the bottom.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ External MCP client (Claude Desktop, Cursor, Zed, …)        │
└──────────────────────────┬──────────────────────────────────┘
                           │  MCP over stdio or HTTP+SSE
┌──────────────────────────▼──────────────────────────────────┐
│ packages/glue_server/lib/src/mcp/                           │
│   • McpServer — JSON-RPC dispatch + capability negotiation  │
│   • McpToolBridge — Glue Tool → MCP tool descriptor + exec  │
│   • McpResourceBridge — sessions, transcripts, skills as    │
│                          MCP resources (read-only)          │
│   • McpPromptBridge — system prompts + skill prompts as     │
│                        MCP prompt templates                 │
└──────────────────────────┬──────────────────────────────────┘
                           │  Tool API
┌──────────────────────────▼──────────────────────────────────┐
│ packages/glue_harness/                                      │
│   • ToolRegistry  • Tool (from glue_core)                   │
│   • SessionManager (read-only resource access)              │
│   • SkillRegistry (skill prompts)                           │
└─────────────────────────────────────────────────────────────┘
```

The MCP server lives in `glue_server/` next to the ACP server — they
are sibling surfaces over the same harness API.

## Package layout

```
packages/glue_server/lib/src/
├── jsonrpc/        ← shared JSON-RPC framing (used by both ACP + MCP)
├── acp/            ← ACP server (separate plan)
└── mcp/
    ├── messages.dart       — typed MCP message types
    ├── server.dart         — McpServer (dispatcher, capability nego)
    ├── tool_bridge.dart    — Glue Tool ↔ MCP tool descriptor
    ├── resource_bridge.dart — sessions, transcripts as resources
    ├── prompt_bridge.dart  — skills + system prompts as prompts
    └── transport/
        ├── stdio.dart      — stdio transport (default)
        └── sse.dart        — HTTP + SSE transport (later)
```

## What we expose

### Tools

Every `Tool` in the harness's `ToolRegistry` is reflected as an MCP
tool. The `ToolParameter` schema already maps almost 1:1 to MCP's
JSON-Schema format — the bridge just needs to:

| Glue concept       | MCP tool field                   |
|--------------------|----------------------------------|
| `tool.name`        | `name`                           |
| `tool.description` | `description`                    |
| `tool.parameters`  | `inputSchema` (JSON Schema)      |
| `tool.execute()`   | `tools/call` request handler     |
| `ToolResult`       | `tools/call` response content    |
| `ToolTrust`        | annotation (`requires_approval`) |

**Permission gate carries over.** When an external MCP client invokes a
mutating tool, Glue still goes through `PermissionGate` — but instead
of asking the local user, the gate emits `PermissionRequestedEvent` to
the *MCP session's* event stream, and the server returns an error
(`-32000 permission_denied`) if no approver is configured. A "headless"
mode auto-approves whatever the MCP client's manifest declares
(`tools/auto_approve: ["read_file", "grep", ...]`).

### Resources

| Resource URI                          | Returns                                         |
|---------------------------------------|-------------------------------------------------|
| `glue://sessions`                     | List of `SessionMeta` (id, title, model, cwd)   |
| `glue://sessions/{id}/transcript`     | The conversation as markdown                    |
| `glue://sessions/{id}/events`         | NDJSON stream of `SessionEvent`s                |
| `glue://skills`                       | List of available `SkillMeta`                   |
| `glue://skills/{name}`                | The skill's `SKILL.md` body                     |
| `glue://config`                       | The active GlueConfig (redacted)                |
| `glue://catalog/models`               | The bundled + remote model catalog              |

Resources are read-only. Subscriptions (`resources/subscribe`) come
later — Glue would push `resources/updated` notifications when a new
session ends, when a skill is added, etc.

### Prompts

| Prompt                         | Source                            |
|--------------------------------|-----------------------------------|
| `glue.system`                  | The harness `Prompts.build()` system prompt |
| `glue.skill.<name>`            | A skill's prompt template         |
| `glue.share-summary`           | The session-share summary template |

These let an external client *use Glue's prompt library* without
running the harness.

## Capability negotiation

The MCP `initialize` handshake advertises:

```json
{
  "capabilities": {
    "tools": { "listChanged": true },
    "resources": { "subscribe": false, "listChanged": true },
    "prompts": { "listChanged": true },
    "logging": { "level": "info" }
  },
  "serverInfo": {
    "name": "glue",
    "version": "<from glue_core/AppConstants.version>"
  },
  "protocolVersion": "2024-11-05"
}
```

`listChanged: true` lets clients react to skill installs and dynamic
tool registration. `subscribe: false` for resources is the v1 stance —
clients re-read on demand.

## Transport

- **stdio (default)** — same NDJSON framing as ACP. Used by Claude
  Desktop config, Cursor, etc.
- **HTTP + SSE (later)** — for remote / web clients. The SSE half is
  for server→client `notifications/*` messages.
- **WebSocket (later)** — symmetric, single connection. Used by web UI
  clients that already speak ACP — they can multiplex MCP on the same
  socket via JSON-RPC method routing.

## CLI surface

```sh
glue serve mcp --stdio                # default; for Claude Desktop config
glue serve mcp --port 3001            # HTTP + SSE on localhost:3001
glue serve mcp --port 3001 --token X  # bearer token required
```

Auth is HTTP-only. The stdio transport is implicitly trusted (the
client is the spawning process).

## Reuse with ACP

Both servers share `packages/glue_server/lib/src/jsonrpc/` for framing,
correlation, and error codes. The MCP and ACP message types are
distinct (different field names, different method namespaces) but the
underlying transport plumbing is the same. The two protocols can run
in the same process: `glue serve --stdio --acp --mcp` would multiplex
over a single stdio connection by method-name dispatch. (Not v1 —
listed for symmetry.)

## Testing strategy

- **Unit:** `Tool.toMcpDescriptor()` and `ToolResult.toMcpContent()`
  pure functions, exhaustively tested.
- **Integration:** spin up the server as a subprocess, send canned
  JSON-RPC messages via stdio, assert responses. Same harness as ACP
  integration tests.
- **Conformance:** run the official MCP test suite
  ([`@modelcontextprotocol/inspector`](https://github.com/modelcontextprotocol/inspector))
  against the running server in CI nightly.

## Out of scope for v1

- `roots` capability (filesystem mounts other than the project's cwd).
- `sampling` capability (Glue does not currently let MCP clients ask
  *Glue's* model to sample — the agent loop is the consumer of LLMs,
  not the producer).
- Prompt-template arguments. v1 prompts are static; arguments come
  later.
- Multi-tenant auth, rate limiting.
- Resource update subscriptions.

## Implementation order

1. **`glue_server/jsonrpc/`** — types, codec, stdio framing, error
   codes. Shared with ACP. (Likely already landed by the time we start
   MCP.)
2. **`glue_server/mcp/messages.dart`** — typed MCP message vocabulary.
3. **`glue_server/mcp/tool_bridge.dart`** — Tool ↔ McpToolDescriptor
   mapping. Exhaustive unit tests.
4. **`glue_server/mcp/server.dart`** — initialize, tools/list,
   tools/call. Smallest viable surface.
5. **`glue serve mcp --stdio`** — CLI subcommand. Manual smoke test
   with Claude Desktop's MCP config.
6. **Resources** — start with `glue://sessions` and `glue://skills`.
7. **Prompts** — `glue.system` first.
8. **HTTP + SSE transport** — once stdio is solid.
9. **Conformance test integration** — nightly CI.

Estimated total: ~600–800 lines of Dart spread across ~10 files.

## Companion: MCP *client* (Glue connects out)

Briefly, since it's symmetric:

- `glue_strategies/lib/src/mcp_client/` — connects to user-configured
  MCP servers (declared in `~/.glue/config.yaml` or per-project).
- Each connected server's tools surface in the agent's `ToolRegistry`
  alongside Glue's native tools.
- Transports: stdio (subprocess), HTTP+SSE, WebSocket.
- The harness's `PermissionGate` treats MCP-sourced tools the same as
  native ones — the user approves them by name, the surface displays
  the source server.

This sits in `glue_strategies` because each MCP client is a strategy
implementation of an external service. Lives in its own subdir to keep
the existing strategies clean.

## Open questions

1. **Tool naming under client mode** — when Glue uses an external MCP
   server's tool, is its name `<server>.<tool>` or just `<tool>` with
   collision handling? Claude Desktop uses prefixes; we should match.
2. **Resource URIs** — `glue://` is unregistered; `mcp+glue://` might
   be safer if URIs leak.
3. **Subagent + MCP interaction** — can a subagent be invoked through
   MCP? It's already exposed as a tool; the question is whether the
   permission model carries through to the spawned subagent.
4. **Versioning** — when the MCP spec bumps (new method names), do we
   support multiple protocol versions or hard-cut over? The
   `protocolVersion` field in `initialize` lets clients choose.
