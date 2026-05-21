# Editor Integration (ACP)

Glue can run headless as an [Agent Client Protocol](https://agentclientprotocol.com) (ACP) agent, so editors and notebooks that speak ACP can drive a Glue session in-process. ACP is a JSON-RPC protocol from Zed Industries — the same one Zed uses for Claude Code, Gemini, Codex, and other agents.

The entry point is `glue acp`. It exposes the full Glue harness (tool calls, runtimes, permission gating, MCP servers, models, sessions) over stdin/stdout or a WebSocket. Editors spawn it; you don't normally invoke it by hand.

## Quick start (Zed)

1. Install Glue and make sure `glue` is on your PATH.
2. Open `~/.config/zed/settings.json` and add:

   ```json
   {
     "agent_servers": {
       "Glue": {
         "type": "custom",
         "command": "glue",
         "args": ["acp"],
         "env": {}
       }
     }
   }
   ```

3. Restart Zed, open the agent panel, and pick **Glue**.

That's it — Zed spawns `glue acp` over stdio, opens an ACP session, and your prompts run through Glue's harness.

## Transports

`glue acp` supports two transports. Editors use **stdio**; browser and notebook clients use **WebSocket**.

| Transport | Use when                                                                 | Flag                              |
| --------- | ------------------------------------------------------------------------ | --------------------------------- |
| stdio     | Default. Editor spawns Glue as a subprocess and pipes JSON-RPC.          | `--stdio` (default)               |
| WebSocket | Browser/notebook clients (marimo, `use-acp`) that can't spawn a process. | `--port N` (implies `--no-stdio`) |

### stdio (editors)

```sh
glue acp              # what the editor runs
```

In stdio mode, stdout is the protocol channel — `glue acp` writes nothing to stdout itself. If you run `glue acp` in a regular terminal (no client attached), you'll see a one-line hint on stderr and the command exits cleanly:

```
● glue acp  speaks ACP over stdin/stdout — meant to be spawned by an editor
  docs https://getglue.dev/docs/advanced/acp-server
```

### WebSocket (browser, notebook)

```sh
glue acp --port 3000
glue acp --port 3000 --host 0.0.0.0 --token secret123
```

On startup `glue acp` prints the URL and (if configured) the auth requirement:

```
● glue acp  ACP over WebSocket
  url  ws://127.0.0.1:3000/acp
  auth bearer token required
  docs https://getglue.dev/docs/advanced/acp-server
  stop Ctrl+C
```

::: warning Non-loopback hosts require a token
Binding `--host` to anything other than `127.0.0.1` requires `--token <secret>`. The token is sent as `Authorization: Bearer …` (or `?token=…` query string). Glue refuses to start without one — exposing an unauthenticated agent on a LAN means anyone on that LAN can run shell commands as you.
:::

## `glue acp` command reference

```
glue acp [--stdio] [--port N] [--host H] [--ws-path P]
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

Status as of 2026-05-21. Always check the upstream docs for the latest config shape.

::: tip Passing provider, model, and credentials
Every editor's `env` block is forwarded into the spawned `glue acp` process, so you can pin a provider per agent without touching `~/.glue/config.yaml`:

```jsonc
"env": {
  "GLUE_PROVIDER": "ollama",
  "GLUE_MODEL": "ollama/gemma3",
  "OLLAMA_HOST": "http://localhost:11434"
}
```

API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, …) work the same way. Editors that don't support per-agent env (some Neovim plugins) inherit the launching shell's environment instead.
:::

### Zed (official)

`~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "Glue": {
      "type": "custom",
      "command": "glue",
      "args": ["acp"],
      "env": {}
    }
  }
}
```

Open the agent panel and pick **Glue**. Settings hot-reload — no restart needed. Debug via Command Palette → `dev: open acp logs`.

If `glue` isn't on Zed's `$PATH` (common when installed via `~/.local/bin` or a version manager), use an absolute path: `"command": "/Users/you/.local/bin/glue"`.

Zed reference: [External agents](https://zed.dev/docs/ai/external-agents) · [Agent server extensions](https://zed.dev/docs/extensions/agent-servers) · [ACP registry](https://zed.dev/blog/acp-registry).

::: info Custom-agent icons
Zed doesn't currently expose an `icon` field for custom agents in `settings.json` — only TOML-packaged agent extensions and entries in the public ACP registry get icons. Follow [zed#51149](https://github.com/zed-industries/zed/discussions/51149) for status.
:::

### JetBrains AI Assistant (official, 2025.3+)

JetBrains AI Assistant ships native ACP support starting with **2025.3** (AI plugin v253.30387.147+). The easiest path is **AI Chat → Add Custom Agent**, which writes `~/.jetbrains/acp.json`. To register Glue by hand, edit that file directly:

```json
{
  "agent_servers": {
    "Glue": {
      "command": "/Users/you/.local/bin/glue",
      "args": ["acp"],
      "env": {
        "GLUE_PROVIDER": "ollama",
        "GLUE_MODEL": "ollama/gemma3",
        "OLLAMA_HOST": "http://localhost:11434"
      }
    }
  }
}
```

The agent-level keys are `command`, `args`, and `env` — there's no `"type"` field (unlike Zed). After editing `acp.json`, refresh the Agents panel or restart the IDE.

::: warning Absolute paths required
JetBrains IDEs do not inherit the user shell's `$PATH` reliably. Always use absolute paths in `command` — `which glue` from a terminal gives you the right value.
:::

Multiple agents live side-by-side under `agent_servers`. A realistic config that mixes Glue with other ACP agents:

```json
{
  "agent_servers": {
    "Glue": {
      "command": "/Users/you/.local/bin/glue",
      "args": ["acp"],
      "env": { "GLUE_PROVIDER": "anthropic" }
    },
    "opencode": {
      "command": "/opt/homebrew/bin/opencode",
      "args": ["acp"]
    },
    "goose": {
      "command": "/opt/homebrew/bin/goose",
      "args": ["acp"]
    }
  }
}
```

#### Exposing the IDE's MCP server to Glue

JetBrains can expose its built-in IntelliJ MCP server (file navigation, refactor primitives, run configurations) to ACP agents. Add a top-level `default_mcp_settings` block:

```json
{
  "default_mcp_settings": {
    "use_idea_mcp": true,
    "use_custom_mcp": true
  },
  "agent_servers": {
    "Glue": {
      "command": "/Users/you/.local/bin/glue",
      "args": ["acp"]
    }
  }
}
```

- `use_idea_mcp` — expose the IDE's built-in MCP server.
- `use_custom_mcp` — also expose any MCP servers you've configured in AI Assistant settings.
- `idea_mcp_allowed_tools` — optional array narrowing which IDE MCP tools are exposed.

These settings apply to every agent. Per-agent overrides are documented as possible by JetBrains but the exact key shape isn't public yet — stick with top-level defaults.

::: warning WSL not supported
JetBrains ACP agents are not supported under WSL as of 2026-Q1. Run on the host OS instead.
:::

JetBrains reference: [AI Assistant — ACP](https://www.jetbrains.com/help/ai-assistant/acp.html) · [ACP Agent Registry](https://blog.jetbrains.com/ai/2026/01/acp-agent-registry/).

### VS Code

No first-party ACP support — Microsoft has not adopted the protocol (see [microsoft/vscode#265496](https://github.com/microsoft/vscode/issues/265496)). The only community extension that reached a usable state, [`gayanper/vscode-acp-provider`](https://github.com/gayanper/vscode-acp-provider), was archived in April 2026 and never shipped on the Marketplace. If you use VS Code, drive Glue through the terminal (`glue` interactively, or `glue acp --port 3000` with a WebSocket client) until first-party or maintained third-party support exists.

### Neovim (community)

Three actively-maintained plugins implement ACP. Pick one — they're mutually exclusive.

#### `carlos-algms/agentic.nvim` — simplest

```lua
{
  "carlos-algms/agentic.nvim",
  opts = {
    acp_providers = {
      glue = {
        name = "Glue",
        command = "glue",
        args = { "acp" },
        env = {
          GLUE_PROVIDER = "anthropic",
        },
      },
    },
  },
}
```

Only `command` is strictly required; `name` shows up in the provider picker. Sessions are interchangeable with terminal `glue` sessions (same session storage).

#### `olimorris/codecompanion.nvim` — full-featured

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      glue = function()
        local helpers = require("codecompanion.adapters.acp.helpers")
        return {
          name = "glue",
          formatted_name = "Glue",
          type = "acp",
          roles = { llm = "assistant", user = "user" },
          commands = {
            default = { "glue", "acp" },
          },
          defaults = {
            mcpServers = "inherit_from_config",
            timeout = 20000,
          },
          parameters = {
            protocolVersion = 1,
            clientCapabilities = {
              fs = { readTextFile = true, writeTextFile = true },
            },
            clientInfo = { name = "CodeCompanion.nvim", version = "1.0.0" },
          },
          handlers = {
            setup = function(self) return true end,
            auth = function(self) return true end,
            form_messages = function(self, messages, capabilities)
              return helpers.form_messages(self, messages, capabilities)
            end,
            on_exit = function(self, code) end,
          },
        }
      end,
    },
  },
})
```

ACP adapters in CodeCompanion only work in the chat buffer, not inline assist. See [adapters-acp](https://codecompanion.olimorris.dev/configuration/adapters-acp).

#### `yetone/avante.nvim` — terse but buggy

```lua
{
  "yetone/avante.nvim",
  opts = {
    provider = "glue",
    acp_providers = {
      glue = {
        command = "glue",
        args = { "acp" },
      },
    },
  },
}
```

Known issues: ACP providers don't appear in `:AvanteSwitchProvider` ([#2958](https://github.com/yetone/avante.nvim/issues/2958)) — you must set `provider` in config. Switching from a non-ACP provider mid-session can error; workaround is `rm -rf ~/.local/state/nvim/avante/projects`.

### Emacs (community)

Use **[`xenodium/acp.el`](https://github.com/xenodium/acp.el)** directly, or the **[`xenodium/agent-shell`](https://github.com/xenodium/agent-shell)** interactive UI on top of it.

```elisp
(require 'acp)

(setq glue-client
  (acp-make-client
    :command "glue"
    :command-params '("acp")
    :environment-variables '("GLUE_PROVIDER=anthropic")))
```

Keyword names matter: `:command-params` (not `:args`) and `:environment-variables` is a list of `"KEY=value"` strings. The `*acp traffic*` buffer tees the JSON-RPC wire log — handy for debugging.

::: warning Early-stage
`acp.el` is explicitly marked as not API-stable. Keyword names may change; install from GitHub via `use-package` `:vc` (not on MELPA).
:::

### Web and notebook clients (WebSocket)

These clients use the **WebSocket** transport — start Glue with `glue acp --port 3000` (see [WebSocket transport](#websocket-browser-notebook) above).

- **[`jupyter-ai-acp-client`](https://github.com/jupyter-ai-contrib/jupyter-ai-acp-client)** — official Jupyter AI v3.0 ACP client. `pip install jupyter_ai_acp_client`. Defines agents via a `persona` with an `executable` field.
- **[`agent-client-kernel`](https://github.com/wiki3-ai/agent-client-kernel)** — alternative Jupyter kernel; configures the agent via the `ACP_AGENT_COMMAND` env var.
- **marimo** — [agent panel](https://docs.marimo.io/guides/editor_features/agents/) ships Claude Code, Gemini, Codex, and OpenCode preconfigured. Custom-agent support is documented as "coming soon" — there's no public hook for pointing it at `glue acp` yet.

A canonical, community-maintained list of ACP clients lives at <https://agentclientprotocol.com/get-started/clients>.

## Security

`glue acp` exposes the full Glue harness, including the shell tool. Treat it like SSH access.

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
