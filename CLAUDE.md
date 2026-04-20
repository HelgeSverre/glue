# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

Monorepo with three components:

- `cli/` — Main Glue CLI application (Dart). This is where most development happens.
- `website/` — Unified marketing + docs site (VitePress), served at getglue.dev
- `docs/` — Canonical reference material (models.yaml, plans, design docs)

## CLI Command Surface Conventions

When adding user-facing commands, prefer these surfaces consistently:

- **Top-level CLI subcommands** (`glue <noun> <verb>`) for non-interactive, scriptable, setup, diagnostic, and filesystem-oriented workflows.
  - Existing: `glue completions install`, `glue config init|show`, `glue doctor`
- **Slash commands** (`/command`) for interactive TUI actions inside a running Glue session.
  - Examples: `/model`, `/resume`, `/provider`, `/config`
- **Global flags** on the root `glue` command for cross-cutting concerns: `--version`, `--where` (paths report), `--print`/`-p`, `--json`, `--model`, `--resume`/`-r`, `--continue`, `--debug`.

Naming guidance:

- Prefer **noun namespaces** for extensible CLI areas: `glue config init`, `glue config show`, `glue doctor`.
- Avoid adding one-off top-level verbs when the feature naturally belongs under an existing noun namespace.
- Keep interactive slash command behavior and non-interactive CLI behavior aligned where practical, but do not force them to share the same exact grammar if that harms UX.
- If introducing a new command family, document the reasoning in `docs/plans/` first when the surface area is non-trivial.

## Common Commands

All commands assume working directory is `cli/` unless noted.

```sh
# Build & run
dart compile exe bin/glue.dart -o glue    # AOT binary
just build                                 # Same as above via justfile
dart run bin/glue.dart                     # Run from source

# Quality gate (run before committing)
dart format --set-exit-if-changed .
dart analyze --fatal-infos                 # Zero warnings policy
dart test
just check                                 # gen-check + analyze + test
just gen-check                             # Fail if bundled model catalog is stale

# Regenerate bundled model catalog from docs/reference/models.yaml
just gen                                   # dart run tool/gen_models.dart

# Single test file
dart test test/llm/anthropic_client_test.dart

# E2E tests (requires Ollama + qwen3:1.7b)
just e2e                                   # dart test --run-skipped -t e2e

# Network-backed integration tests (live DuckDuckGo, Hyperbrowser, etc.)
just integration                           # dart test --run-skipped -t integration

# Monorepo shortcuts (from repo root, requires just)
just check          # Full quality gate across cli + website
just cli::check     # CLI only: gen-check + analyze + test
just cli::test      # CLI tests only
```

## Architecture

Glue is a terminal-native coding agent. Source lives under `cli/lib/src/`. The main layers:

**Agent loop** (`agent/`): `AgentCore` runs the LLM↔tool ReAct loop, streaming `AgentEvent`s (sealed class — use switch/case pattern matching). `AgentRunner` executes agents headlessly. `AgentManager` spawns subagents. `ContentPart` models multimodal message parts.

**App controller** (`app.dart` + `app/` part files): Event-driven architecture merging terminal input and agent events into a single stream. 60fps async rendering with scroll regions. Never blocks.

**LLM clients** (`llm/`): `LlmClient` interface with implementations for Anthropic (SSE), OpenAI/Mistral (SSE), and Ollama (NDJSON). `LlmFactory` creates clients from config. `MessageMapper` bridges Glue's internal message shape to each provider wire format.

**Provider adapters** (`providers/`): Higher-level provider abstraction layered on top of `llm/`. Handles auth (API key, OAuth device code for Copilot), model resolution, and compatibility quirks per provider (`AnthropicAdapter`, `OpenAiCompatibleAdapter`, `CopilotAdapter`, `CopilotTokenManager`).

**Model catalog** (`catalog/`): Parses `docs/reference/models.yaml` into an in-memory catalog. `models_generated.dart` is the bundled snapshot regenerated via `just gen` (checked by `just gen-check`). `RemoteCatalogFetcher` + `CatalogRefreshService` can pull updates at runtime.

**Shell execution** (`shell/`): `CommandExecutor` abstraction — `HostExecutor` (runs via user's `$SHELL`) and `DockerExecutor` (ephemeral containers). `ExecutorFactory` selects with auto-fallback.

**Config & storage** (`config/`, `storage/`, `credentials/`, `session/`, `core/`): `GlueConfig` resolves CLI args → env vars → `~/.glue/config.yaml` → defaults. `CredentialStore` holds API keys/tokens. `SessionStore`/`SessionManager` persist conversation sessions. `core/environment.dart` centralizes GLUE_HOME path resolution.

**Rendering** (`terminal/` + `rendering/` + `ui/`): Raw terminal I/O and ANSI rendering; layout with output/overlay/status/input zones; markdown renderer. `ui/` holds higher-level interactive components — modals, docked panels, autocomplete overlays (slash, `@file`, shell), responsive tables, theme tokens/recipes.

**Input** (`input/`): `LineEditor`, `TextAreaEditor`, file-reference expansion (`@file`), and streaming input handling.

**Commands** (`commands/`): Top-level CLI subcommands (`ConfigCommand`, `DoctorCommand`), slash-command registry and completions.

**Orchestration** (`orchestrator/`): Permission gating for tool execution (approval modes, allow/deny lists).

**Web** (`web/`): Split into `web/search/` (providers: Brave, DuckDuckGo, Firecrawl, Tavily — routed via `SearchRouter`) and `web/browser/` (local + remote providers: Anchor, Browserbase, Browserless, Docker, Hyperbrowser, Steel) plus `web/fetch/` (HTML→markdown, Jina reader, PDF/OCR extraction, truncation).

**Doctor** (`doctor/`): Installation and config health checks surfaced by `glue doctor`.

**Other key modules**: `skills/` (skill discovery and execution), `tools/` (web/subagent tools), `observability/` (tracing, OTEL, Langfuse).

## Code Conventions

- **Imports**: Always use `package:glue/` imports (enforced by lint rule `always_use_package_imports`). Barrel export via `lib/glue.dart`.
- **Events/unions**: Sealed classes for `AgentEvent`, `LlmChunk`, `TerminalEvent` — pattern match with switch/case destructuring.
- **Streaming**: Use `Stream<T> async*` generators.
- **Tool interface**: `abstract class Tool` with `execute(Map<String, dynamic>) → Future<String>`.
- **Tests**: Mirror `lib/src/` structure in `test/`. E2E tests tagged `@Tags(['e2e'])` and network-backed integration tests tagged `@Tags(['integration'])` are both skipped by default — run explicitly with `just e2e` / `just integration`.
- **Linting**: Based on `package:lints/recommended.yaml` with strict additions (see `analysis_options.yaml`).

## CI

- **ci-monorepo-check.yml**: Runs on PR/push — formatting, analyze, tests
- **ci-matrix-os.yml**: Cross-platform tests (Ubuntu, macOS, Windows)
- **integration-e2e-nightly.yml**: Nightly Ollama e2e tests with qwen3:1.7b

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_backlog_instructions()` to load the tool-oriented overview. Use the `instruction` selector when you need `task-creation`, `task-execution`, or `task-finalization`.

- **First time working here?** Read the overview resource IMMEDIATELY to learn the workflow
- **Already familiar?** You should have the overview cached ("## Backlog.md Overview (MCP)")
- **When to read it**: BEFORE creating tasks, or when you're unsure whether to track work

These guides cover:

- Decision framework for when to create tasks
- Search-first workflow to avoid duplicates
- Links to detailed guides for task creation, execution, and finalization
- MCP tools reference

You MUST read the overview resource to understand the complete workflow. The information is NOT summarized here.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->
