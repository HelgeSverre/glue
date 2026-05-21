# Plan: Document ACP client configuration for `glue serve`

## Context

`glue serve` exposes Glue's harness as an ACP (Agent Client Protocol) agent over stdio (default) or WebSocket. Today it has two UX problems:

1. **Silent stdio mode.** When a user runs `glue serve` in a terminal with no ACP client attached, the process just hangs reading stdin and prints nothing. There is no hint that the command exists to be spawned by an editor, nor where to look for setup instructions.
2. **No docs page.** The website (`website/docs/`) covers MCP servers (`docs/advanced/mcp.md`) but has no equivalent for ACP. The only on-site mentions are in the auto-generated changelog and API reference. Editor setup (Zed, VS Code, JetBrains, Neovim, Emacs) is entirely undocumented.

This change adds (a) a minimal TTY-detected hint to `glue serve`'s stderr, (b) a branded WebSocket startup banner, and (c) a new `docs/advanced/acp-server.md` page that documents the protocol, the command surface, and copy-pasteable configs for every editor with an ACP client today.

Decisions captured from the user during planning:
- Docs page goes under **Advanced → Editor Integration (ACP)**, as a peer to MCP Servers.
- Stderr blurb is the **minimal** form: one line + URL. Detailed configs only live on the website, not in the terminal.

## Files to modify

| File | Change |
|---|---|
| `cli/bin/glue.dart` | `_runStdio`: TTY-gated minimal hint (~7 lines). `_runWebSocket`: replace the raw stderr lines with the branded `●` header style used by `catalog show`. |
| `website/docs/advanced/acp-server.md` | **New page.** Covers what ACP is, the `glue serve` command, transports, and per-editor config snippets. |
| `website/.vitepress/config.ts` | Add `{ text: "Editor Integration (ACP)", link: "/docs/advanced/acp-server" }` under the Advanced sidebar group, immediately above `MCP Servers` (line 302). |

## Change 1 — `cli/bin/glue.dart`

### Stdio mode (around line 440)

Add a TTY gate at the top of `_runStdio`. `stdin.hasTerminal` is `true` only when no editor has piped JSON-RPC in.

```dart
Future<int> _runStdio(AppServices services) async {
  if (stdin.hasTerminal) {
    stderr.writeln(
      '$_brandDot ${'glue serve'.styled.bold} '
      '${'speaks ACP over stdin/stdout — meant to be spawned by an editor'.styled.gray}',
    );
    stderr.writeln(
      '  ${'docs:'.styled.gray} https://getglue.dev/docs/advanced/acp-server',
    );
    await services.obs.close();
    return 0;
  }
  // ...existing body unchanged
}
```

### WebSocket mode (around line 494)

Replace the current `stderr.writeln('[glue serve] ACP over WebSocket on …')` with the same `●`/grey-key pattern used by `catalog show` (see `cli/lib/src/commands/catalog_command.dart:256–268`):

```dart
final url = 'ws://${address.host}:$boundPort'
    '${wsPath == '*' ? '' : wsPath}';
stderr.writeln('$_brandDot ${'glue serve'.styled.bold} '
    '${'ACP over WebSocket'.styled.gray}');
stderr.writeln('  ${'url  '.styled.gray} $url');
if (httpHost.bearerToken != null) {
  stderr.writeln('  ${'auth '.styled.gray} ${'bearer token required'.styled.yellow}');
}
stderr.writeln('  ${'docs '.styled.gray} https://getglue.dev/docs/advanced/acp-server');
stderr.writeln('  ${'stop '.styled.gray} Ctrl+C');
```

### Shared helpers

- `_brandDot` (`'●'.styled.rgb(250, 204, 21)`) — already defined in `cli/lib/src/commands/catalog_command.dart:26`. Either (a) move it into a tiny shared helper file (`cli/lib/src/terminal/brand.dart`) and import from both, or (b) re-declare a local copy in `glue.dart`. **Recommended:** extract to `brand.dart` as a `String get brandDot` plus the four `markerOk/Info/Warn/Error` helpers, then update `catalog_command.dart` to consume them. This is a 30-line refactor and lets `doctor` (`cli/lib/src/doctor/doctor.dart`) drop its own copy too.
- `.styled.*` extensions come from `cli/lib/src/terminal/styled.dart` — already a free function on `String`, safe on stderr.

## Change 2 — new docs page

Create `website/docs/advanced/acp-server.md`. Follow the existing VitePress conventions (see `website/docs/using-glue/docker-sandbox.md` and `website/docs/advanced/mcp.md`): H1 title, intro paragraph, H2 sections, fenced code blocks with language tag, `::: tip` / `::: info` callouts, "See also" cross-links to `/api/acp/*`.

### Page outline

1. **Intro** — What ACP is (Agent Client Protocol from Zed Industries, https://agentclientprotocol.com), what `glue serve` does, why you'd use it.
2. **Quick start** — Run `glue serve` → editor spawns it → done.
3. **Transports** — stdio (default, for editors) vs `--port` (WebSocket, for browser/notebook clients).
4. **`glue serve` command reference** — All flags (`--stdio`, `--port`, `--host`, `--ws-path`, `--token`, `--protocol`, `--debug`). Mirror what's in `cli/bin/glue.dart:365–409`.
5. **Editor configuration** — One subsection per editor below.
6. **Security** — Token requirement for non-loopback `--host`, what `glue serve` can do (full harness access).
7. **See also** — `/api/acp/server`, `/api/acp/cli-acp-delegate`, MCP servers page.

### Editor sections (verified by research agent, sourced from official docs)

**Zed** (official, stdio, current as of 2026-05-20):
```json
// ~/.config/zed/settings.json
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
Docs: <https://zed.dev/docs/ai/external-agents>. Custom-agent `icon` is not yet supported in `settings.json` (only in TOML-packaged extensions) — link to <https://github.com/zed-industries/zed/discussions/51149>.

**VS Code** (community only — Microsoft has not adopted ACP, see <https://github.com/microsoft/vscode/issues/265496>):
- Recommend `formulahendry.acp-client` extension. Configure via Command Palette → "ACP: Add Custom Agent" or `acpClient.agents` in `settings.json`. Repo: <https://github.com/formulahendry/vscode-acp>.
- Note alternatives exist (`omercnet.vscode-acp`, `strato-space.acp-plugin`, `multicoder.multicoder`) but all community.

**JetBrains** (official, 2025.3+):
```json
// ~/.jetbrains/acp.json
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
Docs: <https://www.jetbrains.com/help/ai-assistant/acp.html>. Add a `::: warning` callout that ACP agents are not supported under WSL as of 2026-Q1.

**Neovim** (community — recommend `carlos-algms/agentic.nvim` for simplicity):
```lua
require("agentic").setup({
  acp_providers = {
    glue = { name = "Glue", command = "glue", args = { "serve" }, env = {} },
  },
})
```
Mention `olimorris/codecompanion.nvim` and `yetone/avante.nvim` as richer alternatives.

**Emacs** (community — `agent-shell` by xenodium):
```elisp
(require 'agent-shell)
(acp-make-client :command "glue" :command-params '("serve"))
```
Repo: <https://github.com/xenodium/agent-shell>.

**Web / notebook / CLI clients** — short section noting `marimo` (WebSocket only), `use-acp` React hooks, `agent-client-kernel` for Jupyter. For these, use `glue serve --port 3000`.

**Canonical client index** — link to <https://agentclientprotocol.com/get-started/clients>.

## Change 3 — sidebar entry

In `website/.vitepress/config.ts` at line 302, insert a new item directly above `MCP Servers`:

```ts
{ text: "Editor Integration (ACP)", link: "/docs/advanced/acp-server" },
{ text: "MCP Servers", link: "/docs/advanced/mcp" },
```

## Verification

1. **Build the binary**: `cd cli && dart compile exe bin/glue.dart -o glue`.
2. **TTY hint**: run `./glue serve` in a regular terminal. Expect a 2-line branded message (`● glue serve` + `docs:` line) on stderr and exit 0. Run `./glue serve < /dev/null` and confirm it still starts normally (stdin not a TTY) — though it'll exit quickly when stdin closes.
3. **WebSocket banner**: run `./glue serve --port 0`. Expect a multi-line branded block (`●`, `url`, `docs`, `stop`) styled like `glue catalog show`. With `--host 0.0.0.0 --token foo`, expect the `auth` line in yellow.
4. **Quality gate**: `cd cli && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test`. From repo root: `just check`.
5. **Connect Zed end-to-end**: paste the config snippet from the docs page into `~/.config/zed/settings.json`, restart Zed, pick "Glue" from the agent picker, send a prompt. Confirm a session opens.
6. **Website**: `cd website && pnpm dev` (or `bun dev`). Confirm:
   - New page renders at `/docs/advanced/acp-server` with all editor sections, code blocks, and callouts.
   - Sidebar shows "Editor Integration (ACP)" directly above "MCP Servers" under Advanced.
   - All external URLs in the page resolve (manual spot-check: Zed docs, JetBrains docs, agentclientprotocol.com).
7. **Cross-reference check**: confirm no other doc page links to a "Zed integration" or "ACP setup" anchor that we've now broken.

## Out of scope

- No changes to the ACP server protocol implementation or `glue_server` package.
- No new CLI flags on `glue serve` — only output is changed.
- No screenshots or video on the docs page (can be added later; assets dir is `website/public/`).
- No PR to the ACP agent registry (<https://github.com/nicholascelestin/acp-agent-registry>) — that's a separate decision, called out in `docs/plans/2026-02-27-acp-webui.md:690`.
