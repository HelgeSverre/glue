# 2026-04 CLI roadmap — 3 concrete improvements

Follow-up to the structural refactor. Now that the runtime is clean, these three features are where attention goes next. Ranked by impact per effort.

## 1. Git-aware slash commands (`/diff`, `/status`, `/log`)

**Punch line.** Thin slash-command wrappers around `git` that render as collapsible transcript blocks. Skips the "one second, let me run bash for you" detour users hit ten times per session.

**Scope.**
- New `git` slash-command module alongside the existing builtins in `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart`.
- `/diff [pathspec]` → runs `git diff --color=always`, renders output as a bash-style transcript block.
- `/status` → `git status --short`, with emoji/colour badges for staged / unstaged / untracked.
- `/log [-n N]` → short log, defaults to last 10 commits.
- No new controller needed; the commands can use `BashTool` or run the executor directly via a thin helper.
- Handles "not a git repo" gracefully with a single transcript notice.

**Files touched.**
- `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` — new `_GitCommandModule`.
- New `cli/lib/src/commands/git_commands.dart` — thin shell-out helpers.
- `cli/test/commands/` — add tests with a fake executor.

**Effort.** 1–2 days. No new architecture. Existing `CommandExecutor` does the work.

**Why now.**
- Felt every session. The agent already uses bash for git; surfacing it to the user via slash commands removes a common "ok run bash and show me" round-trip.
- Minimal risk: the commands are CLI wrappers; git itself does all the work.
- Natural pairing with the existing `/share`, `/session`, `/model` command family.

---

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
- **Context-window warning** — Token counting already exists; needs a UI alert at 80% of the model's context window. 2-hour job, can ship whenever.
- **Plan mode (`/plan` → think + exec)** — Matches Claude's plan mode; requires integrating extended thinking or two-pass prompts. Architectural; defer.
- **Image paste on Windows** — deliberately excluded from #2; revisit when the top 3 are done.

## Not recommending

- "Add more observability" — already have OpenInference spans.
- "Add more tests" — always true, not actionable.
- Generic quality-of-life passes — schedule those as janitorial work in the background, not as features.

## What makes a "do it" decision for any of these

Before committing to one, ask:
- Can a single session land it? (All three: yes.)
- Does it need a new architecture? (No — each slots into existing structure.)
- Will the first user to try it notice? (Yes for all three.)
- Does it make glue more competitive against Claude Code / opencode / aider? (#3 most; #1 + #2 visibly.)

All three pass. Suggested order: **#1 → #2 → #3**, by impact-per-effort.
