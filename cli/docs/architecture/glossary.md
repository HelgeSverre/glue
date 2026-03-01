# Glue — Glossary

Canonical terminology for the Glue CLI and web UI. Use these terms consistently in code, UI strings, documentation, and agent instructions.

## Hierarchy

```
Project (registered directory / git root)
 └─ Session (resumable chat conversation, optionally with its own worktree/branch)
```

A project can have many sessions. Sessions are independent — different models, different tasks, different branches — they just happen to run against the same project directory.

## Core Concepts

### Project

A registered directory that sessions run against. Typically a git repository, but can be any local directory. A project has:

- A **name** (display name, e.g. `glue`)
- A **path** (local filesystem path, e.g. `~/code/glue`)
- **Detected metadata** (default branch from git, if applicable)
- **Settings overrides** (per-project overrides for provider, model, base branch, isolation mode, branch prefix)

The sidebar groups sessions by project. The project switcher filters visible sessions.

### Session

The primary unit of work. A session is a resumable agent conversation that combines:

- A **project directory** where the agent operates (or a git worktree within it)
- An **LLM provider and model** (e.g. `anthropic/claude-4-sonnet`)
- Optionally a **git branch** and **worktree** for isolation
- A **conversation history** (user messages, assistant responses, tool calls)
- A unique **ID** used for resumption
- **Metrics** (token count, estimated cost, timing)
- Optionally a **PR URL** and **status** for conductor-style lifecycle tracking

Sessions are fully independent from each other — one session may be writing docs using GPT-5 while another reviews a PR using Claude, both in the same project but on different branches.

UI strings: `+ new session`, `Archive session`, `Resume session`.

> **Note:** The Dart backend classes `SessionStore` and `SessionMeta` represent session data. `SessionMeta` stores identity, git context, metrics, and PR lifecycle. Conversation logs are stored separately in `conversation.jsonl`.

### Worktree

A git worktree created for session isolation. When a session uses a worktree, the agent operates in a separate working directory branched from a base branch, avoiding conflicts with the main working tree.

Worktrees live under `.worktrees/` relative to the project root.

A session may or may not use a worktree — it can also run directly in the project root (on the current branch).

### Git Branch

An optional git branch associated with a session. Branches are **not created by default** — the session runs on the current HEAD. The user can opt in to creating a branch at session creation time, using a configurable prefix (e.g. `glue/`, `feature/`).

After a few messages, Glue may propose renaming the auto-generated branch to something descriptive (e.g. `feat/screen-buffer-diffing`), shown as a rename toast in the sidebar.

## Session Metadata

Each session stores rich metadata in `meta.json` (see `SessionMeta` in `lib/src/storage/session_store.dart`):

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | int | Metadata schema version (current: 2) |
| `id` | string | Unique session identifier |
| `cwd` | string | Launch directory (where `glue` was invoked) |
| `project_path` | string? | Project root (git root or registered directory) |
| `model` | string | LLM model used |
| `provider` | string | LLM provider name |
| `start_time` | ISO 8601 | Session creation timestamp (UTC) |
| `end_time` | ISO 8601? | Session close timestamp (UTC) |
| `worktree_path` | string? | Git worktree path if isolated |
| `branch` | string? | Current git branch |
| `base_branch` | string? | Base branch for worktree/PR |
| `repo_remote` | string? | Git remote URL (e.g. origin) |
| `head_sha` | string? | Commit SHA at session start |
| `title` | string? | Display title (user-set or auto-generated) |
| `tags` | string[]? | User-defined tags for grouping/filtering |
| `pr_url` | string? | GitHub PR URL if created |
| `pr_status` | string? | PR status (open/merged/closed) |
| `token_count` | int? | Total tokens used |
| `cost` | double? | Estimated cost in USD |
| `summary` | string? | Auto-generated summary of work done |

## Lifecycle

### Active

A session that is currently running or ready to accept messages. Shown with a green pulsing dot in the sidebar.

### Idle

A session that exists but has no active agent loop running. Shown with a gray dot.

### Archived

A session that has been stopped and hidden from the default sidebar view. Archived sessions are preserved (logs, metadata) but no longer listed under "Active". When archiving a session with a worktree, the user may be prompted to delete the worktree (configurable via `onArchiveWorktree`: `ask` | `keep` | `delete`).

### Deleted

A session that has been permanently removed, along with its worktree (if any) and conversation history. This is destructive and irreversible.

## Settings Hierarchy

Settings resolve in layers (highest priority first):

1. **Session-level** — model/provider set for this specific conversation
2. **Project-level** — per-project overrides (in Settings → Per-Project Overrides)
3. **Global defaults** — user-wide defaults (in Settings → Global Defaults)
4. **App defaults** — hardcoded fallbacks

Overridable settings: `provider`, `model`, `isolationMode` (worktree vs project root), `baseBranch`, `branchPrefix`, `onArchiveWorktree`.

## CLI Resumption

### `glue --resume`

Opens an interactive session picker showing sessions filtered to the current project directory. Use `--all` to show sessions across all projects.

### `glue --resume <ID>`

Resumes a specific session by ID. Glue changes into the correct directory (project root or worktree path) automatically.

### `glue --continue`

Resumes the most recent session in the current project directory. If that session used a worktree, Glue silently changes into the worktree directory.

> **Note:** cwd-scoping for `--resume` is planned but not yet implemented. Current behavior shows all sessions regardless of cwd.

## UI Zones

### Rail (Left Sidebar)

Lists **sessions** grouped by project. Each session row shows: title/ID, branch, status dot, and relative time. Contains:

- Project switcher (with "All Projects" option)
- `+ New session` button
- Session list (active/idle/archived)
- Connection status footer with settings button

### Viewport (Center)

The main conversation area for the active session. Contains the output zone (messages), overlay zone (command palette, popups), status bar (yellow), and input zone (prompt textarea with slash completion).

### Sidecar (Right Sidebar)

Session details panel. Contains:

- **Header** — "Session" label with session ID (click to copy)
- **Info section** — key-value list: project, directory, worktree, branch, model, status, tokens, cost, messages, started, last active
- **Tool Calls** — collapsible list of tool invocations with status indicators

### Status Bar

The yellow bar between output and input zones. Shows session title, branch, provider/model, token count, and relative time.

## Permission Modes

The `PermissionMode` enum (in `lib/src/config/permission_mode.dart`) controls how tool calls are approved. The user cycles through modes with Shift+Tab; the current mode is shown in the status bar.

| Mode | Label | Behavior |
|------|-------|----------|
| `confirm` | `confirm` | Ask for confirmation on untrusted tools (default) |
| `acceptEdits` | `accept-edits` | Auto-approve file edits, still ask for shell commands |
| `ignorePermissions` | `YOLO` | Auto-approve everything — no confirmations |
| `readOnly` | `read-only` | Deny all mutating tools; they are not sent to the LLM |

Permission mode interacts with `ToolTrust` (in `lib/src/agent/tools.dart`):

| ToolTrust | Examples | Auto-approved in |
|-----------|----------|-----------------|
| `safe` | `read_file`, `grep`, `list_directory`, `skill`, `web_search` | All modes except `readOnly` |
| `fileEdit` | `write_file`, `edit_file` | `acceptEdits`, `ignorePermissions` |
| `command` | `bash` | `ignorePermissions` only |

## Skills

A **Skill** is a directory containing a `SKILL.md` file with YAML frontmatter (name, description) and markdown instructions. Skills follow the [agentskills.io](https://agentskills.io/specification) standard.

Skills are discovered at startup from three locations (first match wins):

1. `.glue/skills/` in the project directory (project-local)
2. `~/.glue/skills/` (global)
3. Extra paths from `skills.paths` in config or `GLUE_SKILLS_PATHS` env var

The `SkillRegistry` (in `lib/src/skills/skill_registry.dart`) discovers and indexes skills. The `skill` tool lets the LLM load a skill's full instructions into the conversation. Available skills are listed in the system prompt as `<available_skills>` XML. The `/skills` slash command opens a two-pane browser panel.

See `SkillMeta`, `SkillRegistry`, and `SkillTool` in `lib/src/skills/`.

## Web Tools

Three tools provide web access to the agent:

| Tool | Class | Purpose |
|------|-------|---------|
| `web_fetch` | `WebFetchTool` | Fetch a URL and return clean markdown. Handles HTML pages and PDF documents. |
| `web_search` | `WebSearchTool` | Search the web via configurable providers. Returns titles, URLs, and snippets. |
| `web_browser` | `WebBrowserTool` | Control a browser via Chrome DevTools Protocol for dynamic/JS-heavy pages. |

### Fetch pipeline (`lib/src/web/fetch/`)

`WebFetchClient` fetches a URL, detects content type, and converts to markdown:
- **HTML** — `HtmlExtractor` strips boilerplate, `HtmlToMarkdown` converts to markdown
- **PDF** — `PdfTextExtractor` uses `pdftotext` CLI with OCR fallback via `OcrClient` (Mistral/OpenAI vision)
- **Truncation** — `TokenTruncation` enforces a token budget on the output

An optional Jina Reader mode (`JinaReaderClient`) delegates fetching to the Jina Reader API.

### Search providers (`lib/src/web/search/`)

`SearchRouter` auto-detects the best available provider from configured API keys:
- **Brave** (`BraveSearchProvider`)
- **Tavily** (`TavilySearchProvider`)
- **Firecrawl** (`FirecrawlSearchProvider`)

### Browser backends (`lib/src/web/browser/`)

`BrowserManager` manages a session-scoped browser lifecycle. `BrowserEndpointProvider` implementations provision Chrome instances:
- **Local** — launch a local Chrome process
- **Docker** — spin up a headless Chrome container
- **Cloud** — Browserbase, Browserless, or Steel hosted sessions

Browser actions: `navigate`, `screenshot`, `click`, `type`, `extract_text`, `evaluate`.

Configuration lives in `WebConfig`, `PdfConfig`, and `BrowserConfig` (all in `lib/src/web/`).

## Observability

The observability subsystem traces LLM calls and tool executions as spans and routes them to pluggable backends. Core classes live in `lib/src/observability/`.

| Class | Role |
|-------|------|
| `Observability` | Central coordinator — starts/ends spans, routes to sinks |
| `ObservabilitySpan` | A span with trace ID, parent ID, name, kind, attributes, timing |
| `ObservabilitySink` | Abstract interface for span export |
| `ObservedLlmClient` | Wraps an `LlmClient` to emit `llm.stream` spans with token usage |
| `ObservedTool` | Wraps a `Tool` to emit `tool.<name>` spans with result length |
| `wrapToolsWithObservability()` | Helper to wrap all tools in a tool map |

### Sinks

| Sink | Backend | Config class |
|------|---------|-------------|
| `FileSink` | Append spans to a local JSONL file | (always available) |
| `OtelSink` | Export spans via OpenTelemetry HTTP/protobuf | `OtelConfig` |
| `LangfuseSink` | Export as Langfuse generations/traces | `LangfuseConfig` |

Auto-flush runs on a configurable interval (`flushIntervalSeconds`, default 30s). Configuration is in `ObservabilityConfig` (in `lib/src/observability/observability_config.dart`).

A `DebugController` toggles verbose debug output independently of telemetry export.

## Configuration

### `~/.glue/config.yaml`

User-edited global configuration file. See `docs/reference/config-yaml.md` for the full schema.

### `onArchiveWorktree`

Global setting controlling worktree cleanup when archiving a session:

- `ask` — prompt the user each time (default)
- `keep` — always keep the worktree
- `delete` — always delete the worktree (with safety check for uncommitted changes)

### `branchPrefix`

Global setting for the default git branch name prefix when creating a branch at session creation. Examples: `glue/`, `feature/`, `wip/`. Default: `glue/`.

### `isolationMode`

How a session is isolated from the project:

- `new-worktree` — create a new git worktree (recommended for git projects)
- `existing-worktree` — use an existing worktree
- `project-root` — run directly in the project root directory (no isolation)
