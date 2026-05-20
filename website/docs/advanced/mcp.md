# MCP Servers

Glue can act as a client of any [Model Context Protocol](https://modelcontextprotocol.io/) server. Drop a server into your config and its tools become available to the agent alongside Glue's built-ins — namespaced so they don't collide.

## When to use MCP

Use MCP servers when you want a capability that isn't built into Glue and that someone has already packaged as an MCP server. Common examples:

- **Filesystem servers** with scoped roots and richer file primitives
- **Database connectors** (Postgres, SQLite, Snowflake)
- **Browser automation** via the official Playwright MCP server
- **Repo / issue tracker bindings** (GitHub, GitLab, Linear)
- **Org-internal tools** exposed as MCP servers behind OAuth

Glue speaks MCP `2025-03-26`. Tools advertised by the server become first-class entries in the agent's tool registry; everything else (permission gating, observability, session log, recap) just works.

## Configuration

Servers live under `mcp:` in `~/.glue/config.yaml`:

```yaml
mcp:
  servers:
    # stdio — most common; same shape as Claude Desktop's config
    filesystem:
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-filesystem"
        - "/Users/me/work"
      env:
        DEBUG: "false"

    # http+sse with a literal bearer (use ${ENV} for real secrets)
    company-wiki:
      url: "https://mcp.example.com/wiki"
      auth:
        kind: bearer
        token: "${WIKI_MCP_TOKEN}"

    # http+sse with OAuth 2.1 (run `glue mcp auth login <server>` first)
    notion:
      url: "https://mcp.notion.com"
      auth:
        kind: oauth

    # WebSocket
    ws-server:
      url: "wss://mcp.example.com/socket"
      auth:
        kind: bearer
        token: "${WS_MCP_TOKEN}"

    # Disabled servers stay in config but skip the connect step
    postgres:
      command: /usr/local/bin/mcp-postgres
      enabled: false

  # Optional per-tool policy applied across all servers. Glob patterns
  # match against the namespaced name (`<server>__<tool>`).
  tool_policy:
    auto_approve:
      - "filesystem__read_file"
      - "filesystem__list_directory"
    deny:
      - "*__delete_file"

  # Reconnect defaults; per-server overrides via `call_timeout_seconds`.
  reconnect:
    enabled: true
    initial_delay_ms: 500
    max_delay_ms: 30000
    max_attempts: 10
  call_timeout_seconds: 30
```

### Environment variables in config

Values like `command`, `args`, `env: ...`, and `auth.token` support `${VAR}` interpolation against your shell environment. Expansion happens at config load — if a referenced variable is unset or empty, Glue fails loudly with the server name and the offending field, so you find out before a session starts.

### Stdio environment hygiene

Glue runs each stdio MCP server with a **scrubbed** environment: only `PATH`, `HOME`, `LANG`, `TERM`, `USER`, `SHELL`, and a few cross-platform homologues are forwarded, plus whatever you list under the server's `env:` block. This prevents your `OPENAI_API_KEY`, `AWS_SECRET_ACCESS_KEY`, and `.netrc` indirections from leaking into every MCP server you install.

To opt out (matches Claude Desktop's behaviour), set `mcp.subprocess_env: full`.

## Transports

| Transport | Use when                                                                              | Auth                |
| --------- | ------------------------------------------------------------------------------------- | ------------------- |
| stdio     | Default; the server is a subprocess Glue spawns and pipes JSON-RPC over stdin/stdout. | Implicit trust      |
| HTTP+SSE  | Remote servers (company-hosted, cloud APIs). Streamable HTTP per the 2025-03-26 spec. | Bearer or OAuth 2.1 |
| WebSocket | Symmetric single-connection servers, browser-bridged servers.                         | Bearer              |

Stdio servers are implicitly trusted — you launched them. Remote transports require explicit auth.

## Authentication

### None / implicit (stdio)

Stdio servers run as your subprocess. No auth headers; integrity comes from process isolation and the scrubbed environment.

### Bearer tokens (HTTP / WebSocket)

Resolved in priority order:

1. Literal `auth.token` in config (use `${ENV}` interpolation for secrets — don't commit them)
2. CredentialStore key `mcp:<server-id>:bearer`

Store a bearer token securely:

```sh
glue mcp auth set <server> --bearer
# Prompts for the token (input hidden); stores it encrypted at rest.
```

### OAuth 2.1 with PKCE and DCR

For HTTP servers that advertise OAuth (Notion, etc.), run:

```sh
glue mcp auth login <server>
```

Glue will:

1. Discover the authorization-server metadata at `<base>/.well-known/oauth-authorization-server` (RFC 8414) or fall back to OIDC.
2. Dynamically register a client (RFC 7591) if the server supports it, otherwise reuse the stored `client_id`.
3. Open your browser with a PKCE challenge + fresh state, bind a one-shot loopback HTTP server on `127.0.0.1`, and capture the redirect.
4. Exchange the authorization code for tokens at the token endpoint.
5. Persist tokens encrypted under `mcp:<server-id>:oauth_*` in your credential store.

Re-run the same command if your refresh token ever expires.

## CLI commands

```sh
glue mcp add <id> [options]            # add a new server entry to config.yaml
glue mcp remove <id>                   # remove a server (also clears its creds)
glue mcp enable <id>                   # un-park a disabled server
glue mcp disable <id>                  # park a server without removing it
glue mcp list                          # configured servers + enabled/disabled
glue mcp tools [<server>]              # list tools (all servers if no id)
glue mcp auth set <server> --bearer    # store a bearer token (stdin, hidden)
glue mcp auth login <server>           # OAuth flow (opens browser)
glue mcp auth logout <server>          # forget stored credentials
glue mcp auth status                   # per-server credential summary
```

### Adding servers from the shell

`glue mcp add` writes to `~/.glue/config.yaml` using `yaml_edit`, so your
existing comments and key order survive untouched. Transport is explicit
via `--transport stdio|http|ws`:

```sh
# stdio — everything after `--` is the command + args
glue mcp add filesystem --transport stdio \
  -e DEBUG=false \
  -- npx -y @modelcontextprotocol/server-filesystem /Users/me/work

# http+sse — `--auth bearer` records the kind; store the token afterwards
glue mcp add company-wiki --transport http \
  --url https://mcp.example.com/wiki \
  --auth bearer
glue mcp auth set company-wiki --bearer   # then store the token

# http+sse with OAuth
glue mcp add notion --transport http \
  --url https://mcp.notion.com \
  --auth oauth
glue mcp auth login notion                 # opens the browser

# websocket
glue mcp add ws-server --transport ws \
  --url wss://mcp.example.com/socket \
  --auth bearer

# start a server parked; enable later with `glue mcp enable <id>`
glue mcp add postgres --transport stdio --disabled -- /usr/local/bin/mcp-postgres
```

Flags:

| Flag                  | Applies to | Purpose                                                                                         |
| --------------------- | ---------- | ----------------------------------------------------------------------------------------------- |
| `--transport`, `-t`   | required   | `stdio`, `http`, or `ws`.                                                                       |
| `--url`               | http / ws  | Server URL. Scheme must match transport.                                                        |
| `--auth`              | http / ws  | `none` (default), `bearer`, or `oauth`. The token / OAuth flow is handled by `glue mcp auth …`. |
| `--env`, `-e KEY=val` | stdio      | Repeatable. Env vars passed to the subprocess (after the global allowlist scrub).               |
| `--cwd <dir>`         | stdio      | Working directory.                                                                              |
| `--timeout <seconds>` | any        | Per-server override of `mcp.call_timeout_seconds`.                                              |
| `--disabled`          | any        | Add the entry parked. Use `glue mcp enable <id>` to turn on.                                    |
| `--force`             | any        | Overwrite an existing entry with the same id.                                                   |

`glue mcp remove <id>` deletes the YAML entry **and** clears any stored
bearer / OAuth credentials. Pass `--keep-credentials` if you plan to
re-add the same id later and want the stored token reused.

## Slash commands

Inside a Glue session you have the same surface plus live-state actions:

```
/mcp                            Open the status panel (visual table)
/mcp list                       Print a text table inline
/mcp tools [<server>]           List tools (grouped by server if no arg)
/mcp reconnect <server>         Retry a dead or reconnecting server
/mcp toggle <server>            Session-scoped enable/disable
/mcp auth login <server>        OAuth flow inside the TUI
/mcp auth logout <server>       Forget stored credentials
/mcp auth status                Show credential state per server
/mcp help                       Subcommand cheatsheet
```

All subcommands tab-complete. `/mcp <TAB>` lists subcommands; `/mcp reconnect|toggle|tools <TAB>` enumerates configured server ids; `/mcp auth login|logout <TAB>` filters down to HTTP/WebSocket servers (stdio servers can't OAuth).

`/mcp tools` (and `glue mcp tools`) take the server id as **optional**. With no argument, both list every configured server grouped by id and annotated with status — `(connecting)`, `(reconnecting)`, `(disconnected)`, `(dead)`, or `(disabled)` — so a single command surfaces "what's available right now" across the whole pool. The CLI form waits up to 10 seconds for every selected server to settle before printing.

Inside the status panel (`/mcp` with no args) press `Enter` on a row to open an action submenu: **Reconnect**, **Enable/Disable for this session** (label tracks current state), **View tools**, **Copy server ID**, and **Show last error** (only when a failure is recorded). The submenu reuses the pool's `reconnect()`/`toggle()` methods, so panel actions and the slash subcommands are interchangeable.

The status bar shows a `MCP:N⚠` badge when one or more servers are in `reconnecting` or `dead` state, so you notice flaky servers without opening the panel.

## How tools are exposed

When a server completes its handshake, its tools are registered with the agent under a namespaced name:

```
<server-id>__<tool-name>
```

For example, with the `playwright` server configured, the agent gains `playwright__browser_navigate`, `playwright__browser_snapshot`, and so on. The double-underscore separator avoids collisions with both hyphenated server ids and snake_case tool names, and stays within OpenAI's stricter function-name pattern.

**Native tool names always win.** If a server advertises a tool that collides with a Glue built-in (`read_file`, `bash`, etc.), the built-in keeps the name and the server's version is dropped with a log entry. Use the server-namespaced form if you specifically want the MCP version.

## Permissions

MCP-sourced tools route through the **same** permission gate as native ones — the same approval modal, the same per-tool trust persistence, the same `tool_policy` allow/deny lists. See [Tool Approval](../using-glue/tool-approval.md).

The `mcp.tool_policy.auto_approve` and `mcp.tool_policy.deny` globs match against the namespaced name, so `*__delete_file` denies every server's `delete_file` tool, and `filesystem__read_file` auto-approves only the filesystem server's read.

## Connection lifecycle

Each server runs an independent state machine: `disconnected → connecting → connected`, with `reconnecting` and `dead` for failure recovery.

- **Drop detection**: stdio EOF, HTTP 5xx / SSE close, WebSocket non-1000 close.
- **Backoff**: exponential with jitter, defaults to `500ms → 30s` over 10 attempts. The attempt counter resets on every successful connect, and on manual `/mcp reconnect <id>` or `/mcp toggle <id>`. After `max_attempts` consecutive failures the server is marked `dead` for the session; clear with `/mcp reconnect <id>`. Tunable via `mcp.reconnect.{enabled, initial_delay_ms, max_delay_ms, max_attempts}` in `config.yaml`.
- **In-flight calls** at drop time resolve as `ToolResult(success: false, metadata: {retryable: true, ...})`. We never auto-retry — the agent loop decides whether to try again or change tack.
- **`tools/list_changed`** notifications are honoured: when a server tells us its tool list changed, Glue refreshes, diffs against the previous set, and posts a system message naming what came and went.

Use `/mcp reconnect <server>` to clear a `dead` state and retry immediately.

## Troubleshooting

**Server immediately dies on connect** — Run `glue mcp tools <server>` to surface the error message. Common causes: wrong flag (Playwright MCP uses `--headless`, not `--headed`; default is headed), missing dependency, env-var interpolation referencing an unset variable.

**OpenAI rejects tool names** — If you see `Invalid 'tools[N].function.name'`, you're on an older Glue release that used `.` as the namespace separator. Upgrade to the current release, which uses `__`.

**Tokens expire mid-session** — Currently you re-run `glue mcp auth login <server>` and start a new session. Auto-refresh-on-401 is a planned improvement.

**Subprocess leaked after Glue crashed** — Stdio orphan prevention (PR_SET_PDEATHSIG on Linux, kqueue watchdog on macOS) is planned. Kill the leaked subprocess manually for now.

## Worked example: Playwright headed browser

```yaml
mcp:
  servers:
    playwright:
      command: npx
      args:
        - "-y"
        - "@playwright/mcp@latest"
      env:
        PLAYWRIGHT_BROWSERS_PATH: "0"
```

Start a session and ask the agent to do something browser-y:

```
> Use playwright__browser_navigate to open https://example.com,
  then playwright__browser_snapshot. Tell me what's on the page.
```

The agent will hit the Playwright MCP server's tools, drive a real browser window (headed by default), and report back via the accessibility snapshot.

## See also

- [Tools](../using-glue/tools.md) — built-in tools + how MCP tools fit alongside them
- [Tool Approval](../using-glue/tool-approval.md) — the permission gate also covers MCP tools
- [Observability](./observability.md) — MCP tool calls emit spans like any other tool
- [MCP specification](https://modelcontextprotocol.io/specification) — upstream protocol
