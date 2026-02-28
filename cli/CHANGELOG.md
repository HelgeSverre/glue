# Changelog

All notable changes to Glue CLI will be documented in this file.

## [Unreleased]

### Added

- **Terminology standardization** — established canonical glossary
  (`docs/architecture/glossary.md`). "Workspace" is the primary unit of
  work (an agent context with directory, model, optional branch, and
  conversation history). "Project" is a registered directory (git or
  non-git) that workspaces run against. "Session" is retired as a
  UI-facing term. See glossary for full definitions, lifecycle states,
  settings hierarchy, and CLI resumption semantics.


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

- **`web_fetch` tool** — fetches a URL and returns clean markdown for the
  LLM. Three-stage pipeline: (1) try `Accept: text/markdown` header,
  (2) HTML fetch → Readability-style content extraction → HTML-to-markdown
  conversion, (3) optional Jina Reader API fallback. Configurable timeout,
  max bytes, and token budget. Auto-approved (read-only).
- **`web_search` tool** — searches the web via configurable providers
  (Brave, Tavily, Firecrawl) with unified result model. Auto-detects
  provider from available API keys (priority: Brave → Tavily → Firecrawl)
  with automatic fallback on error. Supports explicit provider selection
  via parameter. Configured via `web.search.*` in config.yaml or
  `BRAVE_API_KEY`/`TAVILY_API_KEY`/`FIRECRAWL_API_KEY` env vars.
- **`WebConfig`** — web tool configuration model with `WebFetchConfig`
  and `WebSearchConfig`, wired into `GlueConfig` with env var and config
  file resolution following existing patterns.
- **Hidden aliases** for slash commands — `SlashCommand` now supports
  `hiddenAliases` that resolve on execution but are excluded from
  autocomplete and `/help`. `/q` is now a hidden alias for `/exit`.
- **Multi-shell support** — unified `CommandExecutor` abstraction with
  `HostExecutor` that respects the user's shell via `$SHELL`,
  `GLUE_SHELL`/`GLUE_SHELL_MODE` env vars, or `shell.*` in config.yaml.
  Supports bash, zsh, fish, pwsh with correct flag mapping for
  interactive/login/non-interactive modes.
- **Docker sandbox** — `DockerExecutor` runs agent commands in ephemeral
  `docker run --rm` containers with bind-mounted directories. Uses
  cidfile-based container termination with retry for race conditions.
  `ExecutorFactory` handles Docker availability detection with automatic
  host fallback. Configurable via `docker.*` in config.yaml or
  `GLUE_DOCKER_*` env vars.
- **Session-scoped Docker mounts** — `SessionState` persists directory
  whitelist additions in `state.json` per session, merged with config
  mounts at executor creation.
- **`/models` command** — lists available models from the current
  provider (Ollama `/api/tags`, OpenAI `/v1/models`, Anthropic
  `/v1/models`). Shows model name, size (Ollama), and marks current.
- **E2E integration tests** — headless agent loop tests via
  `AgentRunner` with real Ollama (`qwen2.5:7b`). Tagged `@e2e`,
  skipped by default, run with `dart test --run-skipped -t e2e`.
  Retry wrapper handles small-model non-determinism.

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
