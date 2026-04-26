# 2026-04 CLI roadmap — 3 concrete improvements

Follow-up to the structural refactor. Now that the runtime is clean, these three features are where attention goes next. Ranked by impact per effort.

## 1. Git aware pwd and branch name in status bar

## regular, no git repo

```text
1:  ◆ Glue v0.1.2 — gpt-5.4
2:  Working directory: ~/code/glue
3:  Type /help for commands.
[.... truncated for brevity  ]
-3:
-#   [status]                                       [provider]   [model]    [mode]     [pwd]        [token count]
-2: -[ Ready       ~[EXPANDS_TO_FIT]~                   openai · gpt-5.4 · [confirm] · ~/code/glue · 0 tokens]
-1: ❯ this is the text i type
```

## In git repo

```text
1:  ◆ Glue v0.1.2 — gpt-5.4
2:  Working directory: ~/code/glue
3:  Type /help for commands.
[....]
-3:
-#   [status]                                       [provider]   [model]    [mode]     [pwd]         [git-branch]        [token count]
-2: -[ Ready       ~[EXPANDS_TO_FIT]~                   openai · gpt-5.4 · [confirm] · ~/code/glue (feature/bugfix-123) · 0 tokens]
-1: ❯ this is the text i type
```

if we ar ein a git repo, id like to show

## 2. Clipboard image paste

**Punch line.** When the user pastes an image (from system clipboard or via bracketed-paste binary), detect it and wrap it as a multimodal `ImagePart` in the next turn's user message.

**Scope.**

- Detect paste events that carry binary image data. Terminals deliver these via bracketed-paste sequences on most platforms, or the app can probe the system clipboard (`pbpaste`, `wl-paste`, `xclip`) on submit.
- Platform support: start with macOS + Linux (`pbpaste` / `wl-paste`). Windows later.
- Wrap detected images as `ImagePart` (already exists at `cli/lib/src/agent/content_part.dart`), injected into the outbound user message.
- Render as a small thumbnail indicator in the transcript (`[image pasted · 240KB png]`).
- Respect the model's vision capability (catalog flag `vision`) — if the active model lacks vision, fall through to saving the image to `/tmp/` and passing the path as text with a notice.

**Files touched.**

- `cli/lib/src/input/text_area_editor.dart` — paste handler extension.
- New `cli/lib/src/input/clipboard_image.dart` — platform detection + decoding.
- `cli/lib/src/runtime/turn.dart` — hook for attaching `ImagePart` to the outgoing user message.
- `cli/lib/src/runtime/transcript.dart` — maybe a small `ConversationEntry.image(thumbnail)` kind.

**Effort.** 1–2 days. `ImagePart` already exists in the domain model.

**Why now.**

- High-delight visual debugging: "look at this UI glitch" → paste screenshot → done. No save-to-disk-and-reference dance.
- Anthropic vision is strong and widely available; local vision models (Gemma 4, Qwen 3.6) also support it.
- Platform-native; no new dependencies on `pbpaste`/`wl-paste` (already on every Mac/Linux).

**Watch-outs.**

- Don't try Windows in the first cut. PowerShell clipboard is a different animal.
- Size cap: paste of a 10MB screenshot shouldn't accidentally fire a multimodal call. Warn + downsample or reject over 4MB.

---

## 3. MCP (Model Context Protocol) server integration

**Punch line.** Auto-load tools from local MCP servers declared in `config.yaml`. Users get Postgres, filesystem-beyond-cwd, GitHub API, etc. without glue shipping a tool for each one.

**Scope.**

- Config: new `mcp_servers:` block in `~/.glue/config.yaml` declaring `{name, command, args, env}` per server.
- Spawn each declared server as a child process on startup, speak JSON-RPC over stdio (the MCP wire format).
- Introspect each server's tool list via `tools/list`, wrap each one as a `glue.Tool` that forwards to `tools/call`.
- Register the wrapped tools in the `Agent.tools` map alongside built-ins.
- `/tools` shows the full set with a "via MCP (server name)" label for provenance.
- Clean shutdown: `SIGTERM` each MCP process on app exit.

**Files touched.**

- `cli/lib/src/config/glue_config.dart` — parse `mcp_servers`.
- New `cli/lib/src/agent/mcp/` module: `mcp_client.dart` (JSON-RPC over stdio), `mcp_tool_adapter.dart` (wraps each remote tool as a `Tool`), `mcp_registry.dart` (lifecycle mgmt).
- `cli/lib/src/core/service_locator.dart` — spawn MCP servers, merge their tools into the agent's tool map.
- `cli/lib/src/runtime/controllers/system_controller.dart` — `/tools` output shows MCP origin.

**Effort.** 2–3 days. MCP protocol is straightforward (JSON-RPC 2.0 + a small schema); the lifecycle work is where most time goes.

**Why now.**

- Claude Code, gemini-cli, aider, opencode all ship MCP. Glue having zero MCP support is the largest 2026-era feature gap.
- Massive capability unlock per line of code: users bring their own tool ecosystem instead of waiting for us to ship each integration.
- The protocol is stable; the ecosystem is active. Early April 2026 is the moment to hop on.

**Watch-outs.**

- Don't build our own MCP server (at least not yet). We're a client.
- Don't ship built-in MCP servers. Make it fully user-declared.
- Trust: each MCP tool runs in a separate process; still needs to go through glue's approval flow (`PermissionGate`) since the tool's arguments come from the LLM.
- Error handling: a crashed MCP server should surface a clear notice, not lock the agent.

---

## Also-rans (not in the top 3)

- **Prompt caching for Anthropic** — Real token-cost win. Needs message-prep refactor + cache-control headers. Medium effort, medium win. Do after #1–#3.
- **Session search / cross-session history** — Sessions are already persisted; searching them is a small UI. Nice-to-have.
- **Plan mode (`/plan` → think + exec)** — Matches Claude's plan mode; requires integrating extended thinking or two-pass prompts. Architectural; defer.
- **Image paste on Windows** — deliberately excluded from #2; revisit when the top 3 are done.
