# MCP Client — Implementation Plan

**Status:** 📋 Planned
**Date:** 2026-05-15
**Design doc:** `docs/plans/2026-04-29-mcp-client.md` (the spec — read first)

This plan converts the design doc's 18-step implementation order into **landable bundles** sized for individual PRs. Each bundle is self-contained, testable, and either user-visible or a clean substrate for the next one.

## Bundling philosophy

- **Foundation before features**: protocol + transport + client land before pool + tool registration.
- **Bearer before OAuth**: first useful MCP servers ship with bearer-or-none auth; OAuth comes after, generalising Copilot's flow.
- **stdio before HTTP**: stdio is the most-common transport and the simplest to test; HTTP+SSE and WebSocket follow.
- **Each bundle is shippable**: green CI, no half-built APIs, no dead code.
- **App-touching work is concentrated**: bundle 4 is the only App-touching bundle in the critical path. Bundle 6 reuses the existing modal slot for re-auth — no architecture changes.

### Slash mirror policy

Every `glue mcp <verb>` CLI subcommand has a `/mcp <verb>` slash equivalent landed **in the same bundle**. Duplication between the two implementations is acceptable — both call into the same pool/client/credential APIs, but the rendering layer differs (CLI: stdout / stderr / exit code; slash: panel / system message / modal). No premature shared "presenter" abstraction; refactor later if duplication becomes painful.

Slash mirrors for the v1 surface:

| CLI                                  | Slash                            | Bundle |
|--------------------------------------|----------------------------------|--------|
| `glue mcp list`                      | `/mcp` (status panel) + `/mcp list` | B4    |
| `glue mcp auth set <server>`         | `/mcp auth set <server>`         | B3     |
| `glue mcp auth login <server>`       | `/mcp auth login <server>`       | B6     |
| `glue mcp auth logout <server>`      | `/mcp auth logout <server>`      | B7     |
| `glue mcp auth status`               | `/mcp auth status`               | B7     |
| `glue mcp tools <server>`            | `/mcp tools <server>`            | B7     |
| `glue mcp call <server> <tool>`      | `/mcp call <server>.<tool>`      | B7     |
| `glue mcp test <server>`             | `/mcp test <server>`             | B7     |
| `glue mcp reconnect <server>`        | `/mcp reconnect <server>`        | B7     |
| —                                    | `/mcp toggle <server>` (no CLI mirror — session-scoped only) | B7 |

Awkward cases (handled per slash command, not via shared infra):
- **`/mcp auth set` token prompt** — opens a `TextInputPanel` (or, if that's not yet a thing in `ui/`, posts a system message "use `glue mcp auth set <server>` in another shell"). Cheap fallback is fine for v1.
- **`/mcp auth login` browser flow** — opens the user's browser via `Process.run`, then surfaces progress via system messages. Same flow as the CLI version; the difference is just rendering.

## Dependency graph

```
B1 (protocol + stdio + client)         ──┐
                                         ├──▶ B3 (pool + tool factory + bearer + ServiceLocator)
B2 (events + config)                   ──┘                       │
                                                                 ▼
                                                     B4 (App surfaces: events, status bar, /mcp panel)
                                                                 │
                                                                 ├──▶ B5 (HTTP+SSE transport)
                                                                 │
                                                                 ├──▶ B6 (OAuth + re-auth modal)
                                                                 │
                                                                 ├──▶ B7 (list_changed reactivity, polish, ACP)
                                                                 │
                                                                 └──▶ B8 (WebSocket transport, low priority)
```

B1 and B2 are independent and can land in either order or in parallel.

---

## Bundle 1 — Protocol + stdio transport + client

**Scope:** Pure backend, no agent integration, no App changes. Ships green but does nothing observable yet.

**Files (new):**
- `packages/glue_strategies/lib/src/mcp_client/protocol.dart` — MCP message types: `initialize`, `tools/list`, `tools/call`, `tools/list_changed`, server `error`. Reuses `glue_server`'s `JsonRpcMessage`.
- `packages/glue_strategies/lib/src/mcp_client/transport.dart` — `McpTransport` interface.
- `packages/glue_strategies/lib/src/mcp_client/transport/stdio.dart` — subprocess + env hygiene + `PR_SET_PDEATHSIG` on Linux + crash-loop detector. Spec § "Process lifecycle for stdio" + "stdio env hygiene".
- `packages/glue_strategies/lib/src/mcp_client/connection_state.dart` — sealed `McpConnectionState` + backoff-with-jitter helper.
- `packages/glue_strategies/lib/src/mcp_client/client.dart` — `McpClient`: protocol-version negotiation, `tools/list`, `tools/call` with the concurrent-id pending map, rate-limit retry, drop/reconnect state machine.

**Files (test):**
- `packages/glue_strategies/test/mcp_client/` — unit tests with an in-memory `McpTransport` fake. Coverage: handshake, protocol-version downgrade, rate-limit retry, drop mid-call, reconnect backoff.

**LOC estimate:** ~700 lines src + ~400 lines tests.

**Done criteria:**
- All new files analyze clean.
- Unit tests pass against an in-memory transport (no real subprocess).
- An adversarial transport test confirms: protocol-too-old refused, unknown notifications ignored, in-flight call resolves as failure on drop.
- Zero references from the rest of the codebase — `git grep McpClient` returns only the new files + tests.

**Out of bundle:** No HTTP+SSE, no WebSocket, no OAuth, no tool wrapping, no pool. Just the bare client speaking stdio JSON-RPC.

---

## Bundle 2 — Event types + config

**Scope:** Sealed `SessionEvent` additions + `mcp:` section of `GlueConfig`. Independent of B1.

**Files (modified):**
- `packages/glue_core/lib/src/session_event.dart` — add five sealed variants: `McpServerConnectedEvent`, `McpServerDisconnectedEvent`, `McpServerErrorEvent`, `McpServerAuthRequiredEvent`, `McpToolListChangedEvent`. Update the exhaustiveness test in `glue_core/test`.
- `packages/glue_harness/lib/src/config/glue_config.dart` — `mcp:` section (servers, tool_policy, reconnect, call_timeout_seconds).
- `packages/glue_harness/lib/src/config/mcp_config.dart` (new) — typed `McpServerSpec` (stdio | http+sse | ws), `McpToolPolicy`, env-var expansion at load.

**Files (test):**
- `packages/glue_harness/test/config/mcp_config_test.dart` — parse the four config flavours in the design doc; missing env-var fails loudly with server name + var name; disabled servers parse but flag `enabled: false`.
- `packages/glue_core/test/session_event_exhaustiveness_test.dart` — exhaustiveness assertion catches the new variants.

**LOC estimate:** ~200 lines src + ~150 lines tests.

**Done criteria:**
- New event variants compile across the workspace (exhaustiveness check forces every existing `switch` to be updated or add a `default`).
- Config parser handles every flavour in the design doc § "Configuration".
- Env-var expansion: literal, `${VAR}`, missing `${VAR}` produces a `ConfigError` naming the server and var.

---

## Bundle 3 — Pool + tool wrapping + ServiceLocator + bearer auth + `glue mcp list`

**Scope:** First user-observable functionality. After this bundle, you can drop a stdio MCP server into `~/.glue/config.yaml` and the agent can call its tools.

**Files (new):**
- `packages/glue_strategies/lib/src/mcp_client/tool_factory.dart` — `McpToolFactory.fromDescriptor(descriptor, client) → Tool`. The wrapped tool's `execute()` calls `client.callTool(name, args)` and maps `ToolResult.failure` for disconnected state.
- `packages/glue_strategies/lib/src/mcp_client/pool.dart` — `McpClientPool`: builds N clients from config, eager-connect non-blocking, exposes `Stream<SessionEvent>` for connect/disconnect/error, methods `toggle(serverId)`, `reconnect(serverId)`, `unhealthyCount`.
- `cli/lib/src/commands/mcp_command.dart` — top-level `glue mcp list` subcommand. Reads config + (if a session is active) live pool state; otherwise reads config and prints "not connected".
- `cli/lib/src/credentials/mcp_credentials.dart` — `CredentialStore` keys: `mcp:<server-id>:bearer`. Helper to set/get/clear.
- `cli/lib/src/commands/mcp_auth_set_command.dart` — `glue mcp auth set <server> --bearer` (prompts for token, writes to credentials).

**Files (modified):**
- `packages/glue_harness/lib/src/service_locator.dart` — at session start, build `McpClientPool` from config, eagerly connect, register all advertised tools with the agent's `ToolRegistry`. The pool is exposed on `Services` so the CLI / slash commands can find it.
- `packages/glue_harness/lib/src/agent/agent_core.dart` — accept extra tools at construction. (Likely no change — already supports registration; verify before bundle starts.)
- `cli/lib/src/commands/glue_command.dart` (or wherever top-level commands are registered) — register `mcp` subcommand.

**Files (test):**
- `packages/glue_strategies/test/mcp_client/pool_test.dart` — pool builds N clients from a config, tools are registered, disconnect of one server doesn't kill the agent loop.
- `packages/glue_strategies/test/mcp_client/tool_factory_test.dart` — synthetic descriptor → invokable Tool; disconnected client → `ToolResult(success: false, summary: …, metadata: retryable: true)`.
- E2E integration test (tagged `@Tags(['integration'])`) — spawn `@modelcontextprotocol/server-everything` as a subprocess, assert tool listing + a sample `echo` call round-trips. Skipped by default (requires Node), runs in nightly CI.

**LOC estimate:** ~600 lines src + ~400 lines tests.

**Done criteria:**
- A stdio MCP server in config gets its tools registered with the agent.
- `glue mcp list` shows configured servers + state.
- `glue mcp auth set filesystem --bearer` round-trips to the credential store.
- Bearer token resolves via priority order: literal → `${ENV_VAR}` → CredentialStore.
- Disconnect-mid-call resolves as `ToolResult.failure` with `retryable: true` in metadata; agent loop continues.

**App touches:** **None.** This bundle is harness-only. App receives no new events, no new ctx fields, no new UI.

---

## Bundle 4 — App surfaces (the only App-touching bundle in the critical path)

**Scope:** Wire MCP events through App, add `/mcp` slash command, status-bar segment, ctx pool reference.

**App-internal changes:**

1. **New event subscription in `run()`.** Add `_mcpSub = pool.events.listen(_handleMcpEvent);` to the existing fan-in (alongside termSub / appSub / jobSub / subagentSub). Cancel in the cleanup `finally` block.
2. **`_handleMcpEvent(SessionEvent)`** — pattern-match on the 5 new variants, mostly `_addSystemMessage(...)` for status changes; reconnecting / dead state changes also `_render()` so the status bar updates.
3. **Status-bar segment in `_doRender`.** Read `pool.unhealthyCount` (a synthetic count of `reconnecting` + `dead`); if > 0, append `'MCP: 2 dead, 1 reconnecting'` to `rightSegs`.
4. **`ctx.mcpPool`** — add `McpClientPool` as a stable field on `SlashCommandContext`. Construction: pull from `Services` or whatever app.dart's services bundle holds.

**Files (new):**
- `cli/lib/src/commands/slash/mcp.dart` — `/mcp` slash command. Default behaviour: open a status panel (one row per server: name, state, last error, tool count). Sub-actions: toggle, reconnect, call. Uses the existing `ModalSurface` and `ResponsiveTable`.

**Files (modified):**
- `cli/lib/src/app.dart` — the four App-internal changes above. ~50 lines.
- `cli/lib/src/commands/slash_command_context.dart` — `final McpClientPool mcpPool;` (or `McpClientPool? mcpPool` if it's null in tests; lean toward non-null with a no-op pool fixture in tests).
- `cli/lib/src/commands/builtin_commands.dart` — register `MccCommand` in the slash registry.
- `cli/test/commands/builtin_commands_test.dart` + `recap_command_test.dart` — add `mcpPool` fixture (no-op pool that lists 0 servers).

**LOC estimate:** ~200 lines src + ~150 lines tests.

**Done criteria:**
- Starting Glue with a configured (and reachable) MCP server posts an `↳ MCP connected: filesystem (3 tools)` system message.
- A misconfigured server posts an error system message and shows in the status bar.
- `/mcp` opens a status panel; selecting a server with state `dead` and choosing "Reconnect" calls `pool.reconnect(server)`.
- `dart test` green; new `mcp_slash_command_test.dart` exercises the panel with a fake pool.

**App-decomposition signal:** Watch for which of these things feel forced:
- Did `_handleMcpEvent` end up needing to coordinate with `_handleAgentEvent`? (Expected answer: no — they're independent.)
- Did the status-bar segment require restructuring `_doRender`? (Expected: no — one-line append to `rightSegs`.)
- Did the ctx addition feel like it's growing toward "App fields by another name"? (Expected: no — `mcpPool` is a service object same as `dockManager`.)

If any of those answers is unexpectedly "yes", that's the real signal to extract — not the Turn speculation.

---

## Bundle 5 — HTTP+SSE transport

**Scope:** Second transport. Remote MCP servers (company-hosted, cloud APIs).

**Files (new):**
- `packages/glue_strategies/lib/src/mcp_client/transport/http_sse.dart` — HTTP for client→server, SSE for server→client. Reuses `glue_strategies/llm/sse.dart`'s decoder.

**Files (modified):**
- `packages/glue_harness/lib/src/config/mcp_config.dart` — accept `url:` flavour (already specified in B2).
- `packages/glue_strategies/lib/src/mcp_client/pool.dart` — transport selection based on `McpServerSpec` shape.

**Files (test):**
- `packages/glue_strategies/test/mcp_client/transport/http_sse_test.dart` — `package:shelf` test server for handshake, tool list, tool call, mid-stream SSE drop, server 5xx → reconnect.

**LOC estimate:** ~300 lines src + ~250 lines tests.

**Done criteria:**
- An HTTP+SSE MCP server with bearer auth in config works end-to-end (mock server in test).
- SSE drop triggers the same drop/reconnect path that stdio EOF does.
- Pending `tools/call` on SSE drop resolves as `ToolResult.failure` per spec § "In-flight `tools/call` during a drop".

**App touches:** None.

---

## Bundle 6 — OAuth 2.1 (PKCE + DCR) + re-auth modal

**Scope:** The bigger of the auth bundles. Generalises Copilot's OAuth flow so MCP and Copilot share infrastructure.

**Files (modified):**
- `packages/glue_strategies/lib/src/providers/auth_flow.dart` (likely renamed to `oauth_flow.dart`) — extract the loopback-redirect mechanics + PKCE + token exchange + refresh-on-401-once into a transport-agnostic helper. Copilot's adapter becomes a thin caller. The MCP flow adds discovery (`/.well-known/oauth-authorization-server`) and Dynamic Client Registration (RFC 7591).
- `packages/glue_strategies/lib/src/mcp_client/client.dart` — on 401, attempt refresh; on refresh fail, emit `McpServerAuthRequiredEvent`.
- `cli/lib/src/commands/mcp_auth_login_command.dart` (new) — `glue mcp auth login <server>` invokes the OAuth flow.

**Files (test):**
- `packages/glue_strategies/test/providers/oauth_flow_test.dart` — refactored Copilot tests to use the generalised flow.
- `packages/glue_strategies/test/mcp_client/oauth_test.dart` — discovery → DCR → authorize → token → refresh round-trip against a `shelf` test server.

**App touches (small):**
- `cli/lib/src/app.dart` — `_handleMcpEvent` adds a case for `McpServerAuthRequiredEvent`: open a `ConfirmModal` ("Re-authorise notion?") via the existing `_activeModal` slot. On confirm, spawn `glue mcp auth login notion` flow inline (or print the remediation command, depending on whether we can run the OAuth flow from inside a TUI session — see open question).

**LOC estimate:** ~500 lines src + ~400 lines tests.

**Done criteria:**
- An OAuth-protected MCP server (Notion-style) works end-to-end with a test discovery endpoint.
- Token refresh on 401 succeeds transparently; refresh failure surfaces as `McpServerAuthRequiredEvent`.
- Copilot's existing tests still pass against the generalised flow.

**Open question:** Can the OAuth flow be initiated from inside the TUI session (loopback redirect while raw mode is on)? Likely yes — the loopback server is just a `dart:io.HttpServer` and the browser open is a `Process.run('open' / 'xdg-open' / …)`. But terminal mode handling needs verification. Worst case: TUI flags the auth-required state and the user runs `glue mcp auth login <server>` in another shell.

---

## Bundle 7 — `tools/list_changed` reactivity + ACP integration + CLI polish

**Scope:** The remaining design-doc items, grouped because they're all small.

**Subtasks:**

1. **`tools/list_changed` reactivity** — subscribe to the notification at connect; on receipt, refresh that server's tool list, diff against last, emit `McpToolListChangedEvent` with `added` / `removed`. App's `_handleMcpEvent` posts a system message. ~150 lines src + tests.

2. **CLI polish** — `glue mcp tools <server>`, `glue mcp call <server> <tool>`, `glue mcp test <server>`, `glue mcp reconnect <server>`, `glue mcp auth logout`, `glue mcp auth status`. Each is a thin wrapper on pool / credential APIs. ~300 lines src + tests.

3. **Slash command polish** — `/mcp toggle <server>`, `/mcp reconnect <server>`, `/mcp call <server>.<tool>`. ~150 lines.

4. **ACP integration** — `CliAcpDelegate.createSession` honours `SessionNewParams.mcpServers` (replace not union — design doc open question 1's recommendation). Map MCP `SessionEvent`s to `glue_mcp_status` `session/update` payloads. `McpServerAuthRequiredEvent` also surfaces a `session/request_permission`-shaped re-auth. ~250 lines.

**LOC estimate:** ~850 lines src + ~500 lines tests.

**Done criteria:**
- A server emitting `tools/list_changed` updates the live registry.
- All CLI + slash subcommands wired and tested.
- ACP `mcpServers` parameter exercised in an integration test.

---

## Bundle 8 — WebSocket transport (deferred)

Lowest priority. Specified in the design doc; only matters for browser-bridged servers and future glue↔glue. Track as a follow-up; not in the critical path.

---

## Summary of App-decomposition signal

Across all 7+1 bundles, App is touched in **two places**:

1. **B4** — one new event subscription, one new system-message handler, one new status-bar segment, one new ctx field. ~50 lines.
2. **B6** — one new case in `_handleMcpEvent` reusing the existing `_activeModal` slot. ~20 lines.

**Total App-internal MCP code: ~70 lines.** This is well within tolerance and gives zero signal to extract Turn, RenderPipeline, or anything else. The decomposition plan stays shelved.

If, during B4 or B6, the work feels harder than this estimate, *that* is the signal to revisit decomposition — and it'll point at the specific cut needed, not a speculative one.

## What to verify before starting Bundle 1

- `glue_server` exposes `JsonRpcMessage` + `JsonRpcTransport` in a form the MCP client can reuse without circular dependency. Quick grep / package layer check.
- `glue_core/Tool` already supports registration after agent construction (B3 depends on this). If not, that's a small prerequisite refactor.
- `CredentialStore` accepts arbitrary namespaced keys (the design doc assumes `mcp:<server-id>:bearer` and `mcp:<server-id>:oauth.*`). Confirm or extend.
- Linux `PR_SET_PDEATHSIG` invocation strategy from Dart — verify by trial; macOS watchdog needs design.

## Open questions carried forward from the design doc

These don't block the implementation; they have defaults the doc already assumes. Confirm or override:

1. Session-scoped MCP servers replace, not union, with config — **recommended: replace**.
2. Auto-approve names not exposed over ACP — **recommended: don't expose**.
3. Eager + non-blocking connect at `session/new` — **recommended: yes**.
4. OAuth on stdio — **recommended: no in v1**.
5. Credential keys by server-id, renaming forces re-auth — **recommended: accept this; document the trade-off**.
6. Glob denylist patterns — **recommended: yes with `*` / `?`**.
