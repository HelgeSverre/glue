# Changelog

All notable changes to Glue CLI will be documented in this file.

## [Unreleased]

### Added

- **Model registry & picker** — curated `ModelRegistry` catalog of 7 models
  across Anthropic, OpenAI, and Ollama with capability, cost, and speed
  metadata. `/model` with no args opens a selectable panel picker grouped
  by provider; `/model <name>` does fuzzy lookup by ID or display name.
  Only models with configured API keys are shown.
- **`GlueConfig.copyWith`** — immutable config update for provider/model
  switching.
- **`LlmClientFactory.createFromEntry`** — create an LLM client directly
  from a `ModelEntry`.
- **Spinner animation** in status bar during LLM streaming — braille dot
  pattern cycles at 80ms instead of static `●` indicator.
- **Collapsible subagent output** — subagent activity is now grouped by
  task into compact summary lines (e.g. `↳ [1/3] task… (5 steps…)`) that
  update in-place. Click a group to expand/collapse its full step log.
- **Alt+Backspace** deletes previous word (same as Ctrl+W).
- **Alt+Left / Alt+Right** word-level cursor navigation in input editor.
- Terminal parser now decodes **CSI modifier parameters** (`;3` = Alt,
  `;5` = Ctrl) from extended arrow key sequences.
- Terminal parser handles **ESC + byte** sequences for Alt+char and
  Alt+Backspace (macOS Terminal convention: ESC prefix = Alt modifier).
- `KeyEvent` and `CharEvent` carry an `alt` flag for modifier-aware
  input handling.

- **Hidden aliases** for slash commands — `SlashCommand` now supports
  `hiddenAliases` that resolve on execution but are excluded from
  autocomplete and `/help`. `/q` is now a hidden alias for `/exit`.

### Fixed

- `/model` switch now updates `_config` (provider + model) via `copyWith`,
  fixing stale config bug where session metadata and subagent spawning
  read outdated values.

### Changed

- Default model strings removed from `GlueConfig` — `_defaultModel()` now
  delegates to `ModelRegistry.defaultModelId()`.
- Subagent updates use a grouped data model (`_SubagentGroup`) instead
  of individual conversation entries — reduces output noise during
  multi-agent orchestration.

## [0.1.0] — Initial development

### Added

- TUI application shell with raw-mode terminal, layout zones
  (output/overlay/status/input), and 60fps render throttling.
- Readline-style line editor with history, Emacs keybindings (Ctrl+A/E/K/U/W),
  and cursor movement.
- AgentCore ReAct loop with streaming LLM ↔ tool execution, parallel
  tool calls, and token counting.
- **LLM providers:** Anthropic Messages API (SSE), OpenAI Chat Completions
  (SSE), Ollama (NDJSON) — each with per-provider tool schema encoding
  and message mapping.
- SSE stream decoder for chunked event parsing.
- LlmClientFactory for provider instantiation from config.
- GlueConfig resolution chain: CLI args → env vars → ~/.glue/config.yaml
  → defaults.
- Headless AgentRunner with configurable approval policies (allowlist,
  always-approve, always-deny).
- AgentManager for subagent orchestration with depth-limited recursive
  spawning.
- `spawn_subagent` and `spawn_parallel_subagents` tools.
- Built-in tools: `read_file`, `write_file`, `edit_file` (multi-line
  find-and-replace), `bash` (with configurable timeout), `grep`,
  `list_directory`.
- Slash command system with `/help`, `/model`, `/clear`, `/resume`,
  `/info`, and tab-completing autocomplete overlay.
- `@file` reference expansion — type `@` to get fuzzy-matched file hints
  (recursive, with directory browsing), expanded inline on submit.
- Inline confirmation modal for tool approval (hotkeys + arrow
  navigation).
- Full-screen panel modal with scrolling, barrier rendering, and
  dismiss.
- Session persistence — `~/.glue/sessions/` with conversation logging,
  listing, and `/resume` command.
- ConfigStore with mtime-based caching and atomic saves.
- DebugLogger for `~/.glue/debug.log`.
- Auto-loads `AGENTS.md` and `CLAUDE.md` into system prompt.
- Bash mode — `!` prefix for shell passthrough with background job
  lifecycle management (ShellJobManager).
- `bashMaxLines` config setting and box-drawn bash output renderer.
- Markdown table rendering with box-drawing characters.
- Animated mascot splash screen with liquid simulation.
- Mascot explodes into goo particles when clicked repeatedly.
- Status bar with mode indicator, model name, working directory,
  scroll position, and token count.
- Status bar padding accounts for ANSI escape sequence lengths.
- Scroll/resize events routed through event bus.
- Render throttling at ~60fps to reduce flicker during streaming.

### Fixed

- Ollama tool results use tool name instead of call ID.
- OpenAI tool call arguments serialized as JSON instead of Dart
  `toString()`.
- `/model` command now actually switches the LLM client.
- BashTool uses `Process.start` with proper kill on timeout.
- ConfigStore uses mtime-based caching with atomic saves and `update()`
  API.
- AtFileHint caches directory listing to avoid blocking UI on every
  keystroke.
- Expanded `@file` content stored in conversation entries for session
  logging.
- Fire-and-forget `.then()` replaced with proper async error handling.
