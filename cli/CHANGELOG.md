# Changelog

All notable changes to Glue CLI will be documented in this file.

## [Unreleased]

### Added

- **Native `OllamaAdapter`** — Ollama now has a dedicated
  `ProviderAdapter` + `OllamaClient` that talks to `/api/chat` directly
  instead of riding the OpenAI-compat adapter at `/v1/chat/completions`.
  Errors correctly attribute to Ollama (no more "OpenAI API error 404"
  on missing Ollama models), and Ollama-specific request options now
  have a home in the native client.
- **`options.num_ctx` injection** — `OllamaClient` now sets
  `options.num_ctx = min(ModelDef.contextWindow, 131072)` on every
  request when the catalog knows the model's context window. Fixes the
  silent agent-loop truncation when Ollama falls back to its 2048-token
  default. Clamped at 128K so catalog entries that claim 1M contexts
  don't OOM mid-range GPUs. Uncatalogued passthrough models (user-typed
  tags) omit `options` and get Ollama's default.
- **Exact-match model resolver** — new
  `lib/src/catalog/model_resolver.dart` is the single source of truth
  for turning a user-typed identifier into a `ModelRef`. Explicit
  `<provider>/<id>` inputs are never fuzzy-matched: catalogued refs
  return the catalog entry, uncatalogued refs pass through to the
  provider verbatim. Bare inputs require an exact match against `id`
  or display name; ambiguous bare inputs return the candidate list and
  unknown bare inputs return a clear error. The previous substring
  fallback silently rewrote `gemma4` into `gemma4:26b`; it's gone.
- **Status bar + `/info` show the wire address** — the right-hand
  status segment now reads `<provider> · <apiId>` (what the provider
  actually receives), not the internal catalog key. `/info` expands to
  `<name> — <provider>/<apiId>` for catalogued models and falls back to
  `<provider>/<modelId>` for uncatalogued passthrough. Surfaces `apiId`
  drift (e.g. Groq's `gpt-oss-120b` goes out as `openai/gpt-oss-120b`).
- **Ollama dynamic discovery** —
  `lib/src/providers/ollama_discovery.dart` merges Ollama's `/api/tags`
  into the `/model` picker. Catalogued+pulled entries render normally;
  catalogued but not-pulled show `[pull]`; tag-only locally-installed
  models show `[local]` and are synthesised into picker rows. 2 s
  timeout, 30 s in-memory cache. Fail-soft: picker falls back to the
  bundled catalog silently when the daemon is down.
- **"Pull this model?" confirmation flow** — selecting a not-installed
  Ollama tag (via the `/model` picker or by typing `ollama/<tag>`
  directly) opens a `ConfirmModal`. On **Yes**, Glue streams
  `POST /api/pull` progress as system messages and only switches the
  active model after a `{"status":"success"}` frame. On **No** or on
  pull failure, the active model stays put.
- **Clean `ConfigError` surface at startup** — `bin/glue.dart` now
  catches `ConfigError` and `ModelRefParseException`, writes a
  single-line `Error: …` to stderr, and exits with code 78 (EX_CONFIG)
  instead of dumping a Dart "Unhandled exception" stack trace.

### Changed

- **`glue --resume` now opens the resume panel at startup.** The
  root CLI flag now mirrors interactive `/resume` behavior when used
  without an argument, instead of requiring a session ID. Resuming a
  specific session from the CLI now uses `--resume-id <id>`. Print mode
  rejects bare `--resume` with a clear error because the panel is
  interactive-only.
- **Ollama no longer masquerades as OpenAI-compat.** The `ollama`
  provider in `docs/reference/models.yaml` now uses `adapter: ollama`
  (not `adapter: openai + compatibility: ollama`), and `base_url`
  drops the legacy `/v1` suffix. Catalog regenerated.
- **`/model` picker picks the user's intent, not a substring match.**
  See "Exact-match model resolver" under Added. Errors list
  candidates for ambiguous inputs instead of silently choosing one.

### Fixed

- **Docker executor test now skips when the daemon is down.** The
  skip guard changed from `docker --version` (CLI-only check) to
  `docker info` (requires the daemon), so the test stops failing on
  machines that have Docker installed but not running.

### Removed

- **`CompatibilityProfile.ollama`** — dead after the native adapter
  move. `CompatibilityProfile.fromString('ollama')` now falls through
  to `openai` (kept for a forgiving parse; the native adapter handles
  the real wiring).

## [0.1.1] — 2026-04-20

### Added

- **Build metadata injection** — `just build` now passes `GLUE_BUILD_TIME`,
  `GLUE_GIT_SHA`, `GLUE_GIT_DIRTY`, and `GLUE_BUILT_BY` to `dart compile` via
  `--define` flags. `BuildInfo` reads them at startup; `glue --version` prints
  a compact summary (e.g. `glue v0.1.1 (a1b2c3d, 2026-04-20T…)`),
  `glue --version --debug` prints a detailed block, and `--debug` emits a
  banner to stderr before the TUI launches. Dev builds (`dart run`) fall back
  to `(dev)`. `just release` now builds after the tag commit so the binary
  carries a clean SHA.
- **`glue config init`** — non-interactive config initializer that writes an
  annotated v2 `config.yaml` template to the resolved Glue home
  (`~/.glue/config.yaml` or `$GLUE_HOME/config.yaml`). Supports
  `--force` overwrite/reset behavior, and `/config init` now delegates to the
  same real config writer instead of creating an empty `./config.yaml`.
- **`glue config path` and `glue config validate`** — scriptable config
  utilities for printing the resolved `config.yaml` path and validating the
  active config/provider credential setup.
- **`glue doctor`** — read-only install/config diagnostic command that reports
  resolved paths, parse errors for config/preferences/credentials/catalog
  files, active config validation, malformed session files, orphaned temp
  files, and returns non-zero when errors are found. Output uses the Glue
  brand header (yellow `●`), bold section headings, and coloured severity
  glyphs (`✓`/`·`/`!`/`✗`). Informational findings (e.g., empty session
  directories missing `conversation.jsonl`) are hidden by default — pass
  `--verbose`/`-v` to surface them.
- **DuckDuckGo search provider** — zero-config `duckduckgo` search backend
  that scrapes the HTML endpoint (`html.duckduckgo.com/html/`), decodes the
  `uddg` redirect parameter to surface clean result URLs, and requires no
  API key. Registered in the default search provider chain. Includes unit
  tests for the HTML parser and an opt-in live integration test
  (`dart test --run-skipped -t integration test/integration/duckduckgo_search_integration_test.dart`).
- **Hyperbrowser backend for `web_browser`** — new `hyperbrowser` browser
  backend provisions Hyperbrowser cloud sessions
  (`POST /api/session`), connects over the returned `wsEndpoint` CDP
  WebSocket URL, surfaces the live view URL in browser tool output, and
  stops the remote session on disposal (`PUT /api/session/{id}/stop`).
  Configured with `web.browser.backend: hyperbrowser` plus
  `HYPERBROWSER_API_KEY` or `web.browser.hyperbrowser.api_key`. Includes
  docs/config examples and an opt-in live smoke test:
  `dart test --run-skipped -t hyperbrowser test/integration/hyperbrowser_e2e_test.dart`.
- **Anchor Browser backend for `web_browser`** — new `anchor` browser
  backend provisions Anchor Browser cloud sessions, connects over the
  returned CDP WebSocket URL, includes the live view URL in browser tool
  output, and stops the remote session on disposal. Configured with
  `web.browser.backend: anchor` plus `ANCHOR_API_KEY` or
  `web.browser.anchor.api_key`. Includes docs/config examples and an
  opt-in live smoke test:
  `dart test --run-skipped -t anchor_browser test/integration/anchor_browser_e2e_test.dart`.
- **`ModelDef.apiId`** — optional field in `docs/reference/models.yaml`
  decoupling the stable catalog key from the mutable upstream identifier.
  Defaults to the YAML key when omitted (zero churn for simple entries).
  Adapters send `model.apiId` on the wire; the YAML key stays as the
  URL-safe, user-facing identifier in configs, sessions, and the `/model`
  picker. Motivation: upstream renames (e.g. Groq dropping Qwen3-Coder)
  no longer invalidate user configs. Matches precedent from OpenRouter,
  LiteLLM, Continue.dev, MLflow, and Docker.
- **Ollama catalog registry integration test** —
  `test/integration/ollama_catalog_registry_test.dart` verifies every
  Ollama catalog tag resolves via `registry.ollama.ai`. Opt-in via
  `dart test --run-skipped -t ollama_registry`; skipped by default to
  stay hermetic. Catches future drift when model authors rename tags.
- **`glue --where`** — prints `GLUE_HOME` and every resolved path
  (`config.yaml`, `preferences.json`, `credentials.json`, `models.yaml`,
  `sessions/`, `logs/`, `cache/`, `skills/`, `plans/`) with an exists / not-yet
  marker. Useful on a fresh install to see where Glue will read and write.
- **`$GLUE_HOME` environment variable** — overrides the default
  `~/.glue` root. Every on-disk path (sessions, logs, cache, credentials,
  config) moves with it. Documented in `docs/reference/config-yaml.md` and
  the Installation / Configuration docs.
- **Installer script** at `getglue.dev/install.sh` — POSIX `sh`, detects
  `linux|macos|windows × x64|arm64`, pulls the matching binary from the
  latest GitHub Release, verifies the `.sha256`, drops it in
  `~/.local/bin` (overridable via `--dir` or `$GLUE_INSTALL_DIR`).
  Supports `--version vX.Y.Z` for pinned installs.
- **`ToolCallPhase.cancelled`** — distinct from `denied` (never ran) and
  `error` (ran but failed). Agent cancel now marks every in-flight tool —
  including ones awaiting approval — as `cancelled` instead of overloading
  `error`.
- **TUI behavior contract** — `docs/reference/tui-behavior.md` codifies
  the alt-screen, scrollback, resize, tool-phase, spinner, focus-priority,
  wrapping, and glyph rules the TUI follows today.
- **CLI prompt arguments and print mode** — pass prompts directly from
  the command line for non-interactive use:
  - `glue "review my code"` — positional prompt argument
  - `glue -p "query"` — print mode, streams response to stdout without TUI
  - `glue -p --json "query"` — JSON output for scripting
  - `glue -r <session-id>` — resume a specific session by ID
  - Model aliases: `glue -m opus` resolves to `claude-opus-4-6`
- **DevTools instrumentation** — consolidated observability with
  `dart:developer` integration:
  - `DevToolsSink` bridges observability spans to `developer.log()` and
    `developer.postEvent()` for Dart DevTools visibility
  - `GlueDev` utility: CPU profiler tags (`tagRender`, `tagLlmStream`,
    `tagToolExec`, `tagAgentLoop`), Timeline helpers, DevTools URL helper
  - TTFB (time to first byte) tracking in `ObservedLlmClient`
  - Tool call name and response preview tracking in observability spans
- **Session replay improvements** — proper tool_call/tool_result
  grouping during session resume and fork:
  - Assistant messages now include their associated tool calls
  - Tool results are properly paired with their tool_use IDs
  - Orphaned `tool_result` messages are filtered from conversation
    history, preventing Anthropic API 400 errors
- **Subagent output improvements** — richer grouped output display:
  - `_SubagentEntry` class with optional JSON pretty-printing for
    expandable tool result content
  - `_SubagentGroup` shows current tool name during execution
  - Expanded view renders indented JSON for structured results
- **Multimodal tool results** — tools can now return images (e.g.
  browser screenshots) as native content blocks instead of base64 text.
  This reduces token usage from ~738K text tokens to ~1,600 vision
  tokens per screenshot.
  - `ContentPart` sealed class hierarchy (`TextPart`, `ImagePart`) for
    structured content in tool results.
  - `Tool.execute()` returns `List<ContentPart>` — single dispatch
    method for all content types (text and images).
  - `ForwardingTool` base class for decorators (Go embedding pattern) —
    new `Tool` methods auto-forward to all decorators.
  - Provider-native image formats: Anthropic inline `image` blocks in
    `tool_result`, OpenAI/Ollama follow-up user messages with
    `image_url`/`images` arrays.
  - `WebBrowserTool` screenshots now return `ImagePart` instead of
    base64 text strings.
- **Observability & debug system** — pluggable telemetry with zero
  changes to business logic. Three wrapper layers instrument all
  activity without polluting core code:
  - `LoggingHttpClient` — wraps `http.Client`, logs every outbound
    HTTP request (method, URL, status, duration).
  - `ObservedLlmClient` — wraps `LlmClient`, tracks provider, model,
    message count, token usage, tool calls, and latency per generation.
  - `ObservedTool` — wraps each `Tool`, tracks execution time, args,
    and output size.
- **`/debug` slash command** — toggles verbose debug mode at runtime.
  Also available via `--debug` / `-d` CLI flag or `GLUE_DEBUG=1` env var.
- **File-based debug logging** — daily-rotating log files at
  `~/.glue/logs/glue-debug-YYYY-MM-DD.log` with timestamped entries
  for HTTP calls, LLM generations, tool executions, and span lifecycle.
- **`Observability` facade** — composite dispatcher that fans out to
  multiple sinks. Sinks are independently enabled/disabled. The facade
  provides `log()`, `startSpan()`, `flush()`, and `close()` methods.
- **`ObservabilityConfig`** — configuration model for debug and
  telemetry settings, parsed from config file and env vars following
  the existing resolution chain.
- **Terminology standardization** — established canonical glossary
  (`docs/architecture/glossary.md`). Two-level hierarchy: **Project**
  (registered directory) → **Session** (resumable agent conversation).
  Sessions are independent and carry their own model, worktree, branch,
  and conversation history. No intermediate "workspace" layer — matches
  the data model used by Claude Code, Codex CLI, and Cline.
- **Enhanced `SessionMeta` (schema v2)** — sessions now store rich
  metadata: `project_path`, `worktree_path`, `branch`, `base_branch`,
  `repo_remote`, `head_sha`, `title`, `tags`, `pr_url`, `pr_status`,
  `token_count`, `cost`, `summary`. All new fields are optional;
  schema v1 files are read with permissive defaults. Added
  `SessionMeta.fromJson` factory for consistent deserialization and
  `SessionStore.updateMeta()` for mid-session metadata writes.
  Timestamps now consistently use UTC.
- **Model registry & picker** — curated `ModelRegistry` catalog of 10 models
  across Anthropic, OpenAI, Mistral, and Ollama with capability, cost, and speed
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
  `AgentRunner` with real Ollama (`qwen3:1.7b`). Tagged `@e2e`,
  skipped by default, run with `dart test --run-skipped -t e2e`.
  Retry wrapper handles small-model non-determinism.
- **Tool call intent indicator** — the UI now shows
  `▶ Tool: write_file (preparing…)` as soon as the LLM begins generating
  a tool call, rather than waiting for the full arguments to stream.
  Tool calls progress through visible phases: preparing → running → done
  (or denied/error). Eliminates the "hanging spinner" feel during large
  tool argument generation.
- **`ToolCallStart` LLM chunk** — Anthropic and OpenAI clients now yield
  a `ToolCallStart` chunk at `content_block_start` / first tool delta,
  surfacing the tool name before arguments finish streaming.
- **Mistral LLM provider** — fourth provider alongside Anthropic, OpenAI,
  and Ollama. Uses OpenAI-compatible API with Mistral-specific base URL.
  Configurable via `MISTRAL_API_KEY` env var or `mistral.api_key` in
  config.yaml.
- **Agent Skills** (`agentskills.io` spec) — discover and activate reusable
  skill definitions from `.glue/skills/` (project-local),
  `~/.glue/skills/` (global), and extra paths via config/env. Skill parser
  validates YAML frontmatter. `skill` tool lists or activates skills.
  `/skills` slash command opens a two-pane `SplitPanelModal` browser.
  Configurable via `skills.paths` in config.yaml or `GLUE_SKILLS_PATHS`
  env var.
- **Browser tool infrastructure** — `BrowserManager` with pluggable
  `BrowserProvider` abstraction for Chrome DevTools Protocol connections.
  Five provider implementations: local Chrome, Docker container,
  Browserbase (cloud), Browserless (cloud), and Steel (cloud).
  `BrowserConfig` with auto-detection priority chain.
- **PDF text extraction** — `web_fetch` now handles PDF URLs with a
  two-stage pipeline: (1) direct text extraction from PDF bytes, (2) OCR
  fallback via Mistral Pixtral or OpenAI GPT-4o vision models for
  scanned/image-heavy PDFs.
- **GitHub Actions CI/CD** — six workflows: Dart checks (analyze, format,
  test), multi-OS matrix (Ubuntu/macOS/Windows), docs build validation,
  nightly e2e integration tests, release tag builds, and auto-labeling.
  Dependabot configured for Dart and GitHub Actions dependency updates.

### Changed

- Web search and browser automation support are constructed lazily during
  startup. `ServiceLocator.create()` now wires memoized lazy factories into
  `WebSearchTool` and `WebBrowserTool`, so `SearchRouter`, browser provider
  selection, and `BrowserManager` are only built on first valid tool use.
- **Model catalog refreshed against live provider availability (April 2026).**
  - **Mistral default → `devstral-latest`** (agentic coding model). Added
    `mistral-medium-latest`. Kept `mistral-large-latest`, `mistral-small-latest`.
  - **Ollama default → `qwen3-coder:30b`** (community consensus, 256K
    context, dedicated tool-call parser). Recommended list: `qwen3-coder:30b`,
    `qwen3.6:35b`, `gemma4:26b`, `devstral-small-2:24b`, `qwen2.5-coder:32b`,
    `qwen3:8b`. Six popular non-agentic families (`mistral:7b`, `gemma3:12b`,
    `codellama:13b`, `codegemma:7b`, `starcoder2:15b`, `deepseek-coder:33b`)
    included as `recommended: false` with notes explaining why they're
    not suitable for tool loops.
  - **Groq default → `openai/gpt-oss-120b`** (reasoning + coding). Added
    `gpt-oss-20b`, `llama-3.1-8b-instant`. Kept `llama-3.3-70b-versatile`.
  - **Slash-bearing catalog keys slugified**: `groq/openai/gpt-oss-120b`
    → `groq/gpt-oss-120b` (upstream `openai/gpt-oss-120b` now lives in
    `api_id`). Same treatment for Groq `gpt-oss-20b` and OpenRouter's
    three slash-keyed entries.
- **Resize preserves scroll position.** `UserResize` no longer snaps the
  transcript back to the tail; the render pipeline clamps any out-of-range
  offset after the viewport changes.
- **`Ctrl+End` jumps to the bottom** and resumes follow-tail. Plain `End`
  stays reserved for the line editor (cursor-to-end-of-line).
- **`/status` is now a hidden alias of `/info`.** One command in help +
  autocomplete; muscle memory for `/status` keeps working.
- **Release workflow overhaul** — five-way matrix
  (`linux-x64 / linux-arm64 / macos-x64 / macos-arm64 / windows-x64.exe`),
  per-asset `.sha256`, aggregated `SHA256SUMS`, smoke-test of every binary,
  prerelease auto-flag for tags containing `-`.
- **GH Action version audit.** `actions/cache v4 → v5` (Node 24);
  everything else already on current major.
- Status bar reformatted: bold mode indicator on left, model/mode/
  cwd as right-aligned segments with `│` separators.
- `GlueConfig.load()` no longer accepts `cliProvider` parameter
  (provider inferred from model). Removed `--provider` flag (frees
  `-p` for print mode).
- Terminal parser now decodes **CSI modifier parameters** (`;3` = Alt,
  `;5` = Ctrl) from extended arrow key sequences.
- Terminal parser handles **ESC + byte** sequences for Alt+char and
  Alt+Backspace (macOS Terminal convention: ESC prefix = Alt modifier).
- **Eager tool call emission** — `AgentToolCall` events are emitted during
  LLM streaming (not after stream end), so auto-approved tools can start
  executing while the model may still be finishing the response.
- **Dart analyzer hardening** — expanded `analysis_options.yaml` with
  `always_use_package_imports`, `strict-casts`, `strict-raw-types`,
  `avoid_dynamic_calls`, `prefer_const_constructors`, `unawaited_futures`,
  `discarded_futures`, and other safety/style rules on top of
  `package:lints/recommended.yaml`. Converted all relative imports to
  `package:glue/` imports across 51 files. Applied `dart fix` auto-fixes
  for const correctness, unnecessary lambdas, and parentheses.
- Default model strings removed from `GlueConfig` — `_defaultModel()` now
  delegates to `ModelRegistry.defaultModelId()`.
- Subagent updates use a grouped data model (`_SubagentGroup`) instead
  of individual conversation entries — reduces output noise during
  multi-agent orchestration.

### Fixed

- **Spinner no longer stuck after cancel.** `_cancelAgentImpl` now stops
  the spinner before flipping mode; `_cancelBashImpl` mirrors the pattern
  defensively.
- **Tool phase no longer stuck on `awaiting approval` after cancel** —
  approval-modal-open cancels now transition to `cancelled` too.
- **Cancel no longer corrupts conversation** — cancelling (Escape) while
  a tool was executing left the conversation with `tool_use` blocks but
  no matching `tool_result` messages, causing the next API call to fail
  with a 400 error. `ensureToolResultsComplete()` now injects synthetic
  `[cancelled by user]` results for any unmatched tool calls.
- **Unused `callId` parameter** in `_ConversationEntry.toolResult` — was
  accepted but silently discarded; removed the dead parameter.
- `/model` switch now updates `_config` (provider + model) via `copyWith`,
  fixing stale config bug where session metadata and subagent spawning
  read outdated values.
- **ANSI codes in split panel highlight** — reverse-video selection
  highlight in `SplitPanelModal` now strips ANSI escape sequences before
  applying highlight.
- **Skill discovery trailing-slash safety** — skill directory paths ending
  with `/` no longer produce empty skill names.
- **Exit message styling** — exit prompt now shows the yellow diamond brand
  mark with session ID.
- Sema scripting skill documentation examples corrected (8 runtime
  errors fixed in documented code).

### Removed

- **`codestral-latest` from Mistral catalog** — FIM-lineage model;
  enumerates tools but narrates instead of calling them in agent loops.
  Replaced by `devstral-latest`.
- **`qwen/qwen3-coder` from Groq catalog** — Groq no longer serves this
  model; the entry would 404. Replaced by `openai/gpt-oss-120b`.
- **`llama3.2:latest` from Ollama catalog** — general chat model,
  not coding/tool-focused.
- **`devstral:latest` from Ollama catalog** — replaced by the pinned
  `devstral-small-2:24b` (known version, known SWE-bench scores).
- **Interaction modes** (`code` / `architect` / `ask`), plan-mode UI,
  `GLUE_INTERACTION_MODE` env var.
- **OTEL / Langfuse / DevTools observability sinks** —
  `~/.glue/logs/spans-YYYY-MM-DD.jsonl` is the single local trace log
  now.

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
