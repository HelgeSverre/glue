# Editor Integration (ACP)

Glue can run headless as an [Agent Client Protocol](https://agentclientprotocol.com) (ACP) agent, so editors and notebooks that speak ACP can drive a Glue session in-process. ACP is a JSON-RPC protocol from Zed Industries — the same one Zed uses for Claude Code, Gemini, Codex, and other agents.

The entry point is `glue serve`. It exposes the full Glue harness (tool calls, runtimes, permission gating, MCP servers, models, sessions) over stdin/stdout or a WebSocket. Editors spawn it; you don't normally invoke it by hand.

## Quick start (Zed)

1. Install Glue and make sure `glue` is on your PATH.
2. Open `~/.config/zed/settings.json` and add:

   ```json
   {
     "agent_servers": {
       "Glue": {
         "type": "custom",
         "command": "glue",
         "args": ["serve"],
         "env": {}
       }
     }
   }
   ```

3. Restart Zed, open the agent panel, and pick **Glue**.

That's it — Zed spawns `glue serve` over stdio, opens an ACP session, and your prompts run through Glue's harness.

## Transports

`glue serve` supports two transports. Editors use **stdio**; browser and notebook clients use **WebSocket**.

| Transport | Use when                                                                 | Flag                              |
| --------- | ------------------------------------------------------------------------ | --------------------------------- |
| stdio     | Default. Editor spawns Glue as a subprocess and pipes JSON-RPC.          | `--stdio` (default)               |
| WebSocket | Browser/notebook clients (marimo, `use-acp`) that can't spawn a process. | `--port N` (implies `--no-stdio`) |

### stdio (editors)

```sh
glue serve              # what the editor runs
```

In stdio mode, stdout is the protocol channel — `glue serve` writes nothing to stdout itself. If you run `glue serve` in a regular terminal (no client attached), you'll see a one-line hint on stderr and the command exits cleanly:

```
● glue serve  speaks ACP over stdin/stdout — meant to be spawned by an editor
  docs https://getglue.dev/docs/advanced/acp-server
```

### WebSocket (browser, notebook)

```sh
glue serve --port 3000
glue serve --port 3000 --host 0.0.0.0 --token secret123
```

On startup `glue serve` prints the URL and (if configured) the auth requirement:

```
● glue serve  ACP over WebSocket
  url  ws://127.0.0.1:3000/acp
  auth bearer token required
  docs https://getglue.dev/docs/advanced/acp-server
  stop Ctrl+C
```

::: warning Non-loopback hosts require a token
Binding `--host` to anything other than `127.0.0.1` requires `--token <secret>`. The token is sent as `Authorization: Bearer …` (or `?token=…` query string). Glue refuses to start without one — exposing an unauthenticated agent on a LAN means anyone on that LAN can run shell commands as you.
:::

## `glue serve` command reference

```
glue serve [--stdio] [--port N] [--host H] [--ws-path P]
           [--token T] [--protocol acp] [--debug]
```

| Flag               | Default     | Purpose                                                                                       |
| ------------------ | ----------- | --------------------------------------------------------------------------------------------- |
| `--stdio`          | `true`      | Speak ACP over stdin/stdout. This is what editors expect.                                     |
| `--port N`, `-p N` | —           | Bind a WebSocket server on the given port. `0` picks an ephemeral port. Implies `--no-stdio`. |
| `--host H`         | `127.0.0.1` | Bind address for `--port`. Pass `0.0.0.0` to expose on all interfaces (requires `--token`).   |
| `--ws-path P`      | `/acp`      | HTTP path that accepts the WebSocket upgrade. `*` accepts any path.                           |
| `--token T`        | —           | Bearer token required on every WebSocket connection. Required when `--host` is non-loopback.  |
| `--protocol`       | `acp`       | Protocol to serve. ACP only today; MCP-client support is on the roadmap.                      |
| `--debug`, `-d`    | `false`     | Enable debug observability sinks for the agent loop.                                          |

## Editor configuration

Status as of 2026-05-20. Always check the upstream docs for the latest config shape.

### Zed (official)

`~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "Glue": {
      "type": "custom",
      "command": "glue",
      "args": ["serve"],
      "env": {}
    }
  }
}
```

Zed reference: [External agents](https://zed.dev/docs/ai/external-agents) · [agent_servers extension docs](https://zed.dev/docs/extensions/agent-servers).

::: info Custom-agent icons
Zed doesn't currently expose an `icon` field for custom agents in `settings.json` — only TOML-packaged agent extensions and entries in the public ACP registry get icons. Follow [zed#51149](https://github.com/zed-industries/zed/discussions/51149) for status.
:::

### JetBrains IDEs (official, 2025.3+)

JetBrains AI Assistant ships native ACP support starting with 2025.3. The easiest path is **AI Chat → Add Custom Agent**, which writes `~/.jetbrains/acp.json`. To register Glue by hand:

```json
{
  "default_mcp_settings": {},
  "agent_servers": {
    "Glue": {
      "command": "glue",
      "args": ["serve"],
      "env": {},
      "use_idea_mcp": true
    }
  }
}
```

JetBrains reference: [AI Assistant — ACP](https://www.jetbrains.com/help/ai-assistant/acp.html).

::: warning WSL not supported
JetBrains ACP agents are not supported under WSL as of 2026-Q1. Run on the host OS instead.
:::

### VS Code (community)

Microsoft has not adopted ACP — see the open feature request at [microsoft/vscode#265496](https://github.com/microsoft/vscode/issues/265496). For VS Code users today, install a community ACP client extension:

- **[`formulahendry.acp-client`](https://github.com/formulahendry/vscode-acp)** — most popular; ships 11+ preconfigured agents plus a "ACP: Add Custom Agent" command. Configure via Command Palette or the `acpClient.agents` setting.
- Alternatives: `omercnet.vscode-acp`, `strato-space.acp-plugin`, `multicoder.multicoder`.

With `formulahendry.acp-client`, open the Command Palette → **ACP: Add Custom Agent** and use `glue` as the command and `serve` as the single arg.

### Neovim (community)

Three plugins implement ACP support:

- **[`carlos-algms/agentic.nvim`](https://github.com/carlos-algms/agentic.nvim)** — closest match to Zed's minimal config:

  ```lua
  require("agentic").setup({
    acp_providers = {
      glue = {
        name = "Glue",
        command = "glue",
        args = { "serve" },
        env = {},
      },
    },
  })
  ```

- **[`olimorris/codecompanion.nvim`](https://codecompanion.olimorris.dev/configuration/adapters-acp)** — richer adapter table with `commands.default`, `parameters.protocolVersion`, custom handlers.
- **[`yetone/avante.nvim`](https://github.com/yetone/avante.nvim)** — also lists ACP support.

### Emacs (community)

Use **[xenodium/agent-shell](https://github.com/xenodium/agent-shell)** (UI) backed by **[xenodium/acp.el](https://github.com/xenodium/acp.el)** (library):

```elisp
(require 'agent-shell)
(acp-make-client :command "glue" :command-params '("serve"))
```

The `*acp traffic*` buffer is handy when debugging — it tees the JSON-RPC wire log.

### Web, notebook, and CLI clients

These clients use the **WebSocket** transport, so start Glue with `glue serve --port 3000` (or whatever port you prefer):

- **[marimo](https://docs.marimo.io/guides/editor_features/agents/)** — notebook ACP panel; custom-agent support is on the roadmap. Today the panel ships Claude Code, Gemini, Codex, and OpenCode preconfigured.
- **[`use-acp`](https://marimo-team.github.io/use-acp/)** — React hooks for embedding ACP in web UIs.
- **[`agent-client-kernel`](https://github.com/wiki3-ai/agent-client-kernel)** — Jupyter kernel that drives an ACP agent.

A canonical, community-maintained list of ACP clients lives at <https://agentclientprotocol.com/get-started/clients>.

## Security

`glue serve` exposes the full Glue harness, including the shell tool. Treat it like SSH access.

- **stdio is implicitly trusted** — only the parent process can talk to it.
- **WebSocket on loopback (`127.0.0.1`)** is reachable only from the host. Still consider a token if other users share the machine.
- **WebSocket on non-loopback hosts** requires `--token`. Glue refuses to start without one.
- **Permission gating still applies.** Every tool call goes through the same approval modes (`auto-approve`, `ask`, `deny`) as the interactive TUI. Configure them in `~/.glue/config.yaml`.

## See also

- [Server](/api/acp/server) — `AcpServer` API
- [CliAcpDelegate](/api/acp/cli-acp-delegate) — delegate that owns the per-session `AgentCore`
- [HttpHost](/api/acp/http-host) — WebSocket transport
- [MCP Servers](./mcp.md) — Glue as an MCP **client** (the symmetric setup: editor → Glue → MCP servers)
- [Agent Client Protocol spec](https://agentclientprotocol.com) — upstream protocol reference
