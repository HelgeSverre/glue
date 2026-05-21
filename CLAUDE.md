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
- For any user-facing stdout from a `Command<int>`, follow `docs/design/cli-output-formatting.md` — brand markers (`brandDot`, `markerOk/Warn/Error/Info`), the `*_format.dart` extraction pattern, and `styledOrPlain()` for TTY/`NO_COLOR` safety.

## Common Commands

All commands assume working directory is `cli/` unless noted.

```sh
# Build & run
just build                                 # AOT binary → ../dist/glue (via `dart build cli`)
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

Glue is a terminal-native coding agent. The codebase is a Dart monorepo:

- `packages/glue_core/` — pure data types and contracts shared everywhere (`SessionEvent`, `ContentPart`, `WorkspaceMapping`, `RunningCommandHandle`).
- `packages/glue_strategies/` — strategy interfaces and built-in implementations (`CommandExecutor` + `HostExecutor` + `DockerExecutor`, `Workspace` + `LocalWorkspace`, `RuntimeFactory` + `RuntimeSession`, web search/browser providers).
- `packages/glue_runtimes/` — cloud runtime adapters (`daytona/`, `sprites/`, `modal/`) registered with `RuntimeFactory` from the cli surface. Shared bootstrap + FS transport live under `src/common/`.
- `packages/glue_harness/` — agent loop and supporting machinery: `AgentCore`/`AgentRunner`/`AgentManager`, `LlmClient` impls (`anthropic/`, `openai/`, `ollama/`) + `LlmFactory`, provider adapters (`AnthropicAdapter`, `OpenAiCompatibleAdapter`, `CopilotAdapter`), model catalog, tool implementations, `ServiceLocator`, MCP client, observability.
- `packages/glue_server/` — ACP server + `event_mapping` from `SessionEvent` to ACP updates.
- `cli/` — the user-facing binary (`bin/glue.dart`) and surface-only code: `lib/src/app.dart` (App controller), `lib/src/terminal/` + `lib/src/rendering/` + `lib/src/ui/` (TUI), `lib/src/input/` (LineEditor, file-ref expansion), `lib/src/commands/` (subcommands + slash registry), `lib/src/doctor/`, `lib/src/conversation/`.

Cross-cutting layers:

**Agent loop** (`glue_harness/agent/`): `AgentCore` runs the LLM↔tool ReAct loop, streaming `AgentEvent`s (sealed class — use switch/case pattern matching). `AgentRunner` executes agents headlessly. `AgentManager` spawns subagents.

**App controller** (`cli/lib/src/app.dart`): Event-driven architecture merging terminal input and agent events into a single stream. 60fps async rendering with scroll regions. Never blocks.

**LLM clients** (`glue_harness/llm/`): `LlmClient` interface with implementations for Anthropic (SSE), OpenAI/Mistral (SSE), and Ollama (NDJSON). `LlmFactory` creates clients from config. `MessageMapper` bridges Glue's internal message shape to each provider wire format.

**Provider adapters** (`glue_harness/providers/`): Higher-level provider abstraction layered on top of `llm/`. Handles auth (API key, OAuth device code for Copilot), model resolution, and compatibility quirks per provider.

**Model catalog** (`glue_harness/catalog/`): Parses `docs/reference/models.yaml` into an in-memory catalog. `models_generated.dart` is the bundled snapshot regenerated via `just gen` (checked by `just gen-check`).

**Runtimes** (`glue_strategies/shell/` + `glue_strategies/fs/` + `glue_strategies/runtime/` + `glue_runtimes/`): `CommandExecutor` + `Workspace` + `RuntimeSession` contracts in `glue_strategies`; built-in `host`/`docker` adapters there; `daytona`/`sprites`/`modal` adapters in `glue_runtimes` registered at startup from `cli/bin/glue.dart` via `register*Runtime()`. `RuntimeFactory.create` resolves the active runtime per session.

**Config & storage** (`glue_harness/config/`, `storage/`, `credentials/`, `session/`, `core/`): `GlueConfig` resolves CLI args → env vars → `~/.glue/config.yaml` → defaults. `CredentialStore` holds API keys/tokens. `SessionStore`/`SessionManager` persist conversation sessions. `core/environment.dart` centralizes GLUE_HOME path resolution.

**Rendering** (`cli/lib/src/terminal/` + `rendering/` + `ui/`): Raw terminal I/O and ANSI rendering; layout with output/overlay/status/input zones; markdown renderer. `ui/` holds higher-level interactive components — modals, docked panels, autocomplete overlays, responsive tables, theme tokens/recipes.

**Input** (`cli/lib/src/input/`): `LineEditor`, `TextAreaEditor`, file-reference expansion (`@file`), and streaming input handling.

**Commands** (`cli/lib/src/commands/`): Top-level CLI subcommands (`ConfigCommand`, `DoctorCommand`, `McpCommand`), slash-command registry, completions, and per-slash command classes (`/model`, `/runtime`, `/mcp`, …).

**Orchestration** (`glue_harness/orchestrator/`): Permission gating for tool execution (approval modes, allow/deny lists).

**Web** (`glue_harness/web/`): Split into `web/search/` (providers: Brave, DuckDuckGo, Firecrawl, Tavily) and `web/browser/` (local + remote providers: Anchor, Browserbase, Browserless, Docker, Hyperbrowser, Steel) plus `web/fetch/` (HTML→markdown, Jina reader, PDF/OCR, truncation).

**Doctor** (`cli/lib/src/doctor/`): Installation and config health checks surfaced by `glue doctor`, including a per-runtime block (host / docker / daytona / sprites / modal).

**Other key modules**: `glue_harness/skills/` (skill discovery and execution), `glue_harness/tools/` (web/subagent tools), `glue_harness/observability/` (tracing + OTLP/HTTP export via `otlp_http_trace_sink.dart` — emits a stable `session.id` resource attribute per Glue CLI process so observability backends following the OpenInference convention can group multiple traces from one invocation).

## Code Conventions

- **Imports**: Always use `package:glue/` imports (enforced by lint rule `always_use_package_imports`). Barrel export via `lib/glue.dart`.
- **Events/unions**: Sealed classes for `AgentEvent`, `LlmChunk`, `TerminalEvent` — pattern match with switch/case destructuring.
- **Streaming**: Use `Stream<T> async*` generators.
- **Tool interface**: `abstract class Tool` with `execute(Map<String, dynamic>) → Future<String>`.
- **Tests**: Mirror `lib/src/` structure in `test/`. E2E tests tagged `@Tags(['e2e'])` and network-backed integration tests tagged `@Tags(['integration'])` are both skipped by default — run explicitly with `just e2e` / `just integration`.
- **Linting**: Based on `package:lints/recommended.yaml` with strict additions (see `analysis_options.yaml`).
- **Functional over imperative**: Prefer `.where(...)`, `.map(...)`, `.toList()`, `.join('\n')`, `Map.fromEntries(...)` and small extensions like `sortBy` over `for`/`if` collection literals or `StringBuffer` loops when the code is a pure filter, transform, or aggregate. Mutation-heavy or multi-stage logic stays imperative.
- **Inline the chain**: When building a structured map literal, inline the `.map(...)` / `Map.fromEntries(...)` call directly at the value position rather than extracting `final properties = ...` / `final required = ...` locals — the literal stays the structural shape, and the chains read top-to-bottom alongside the keys they belong to.
- **Block body for map builders**: Methods that return a multi-key map literal (e.g. `toSchema`, `toJson`) should use a block body with `return { ... };` rather than an arrow expression body. The block makes intermediate steps and the literal's shape easier to scan.
- **SVG/banner geometry**: The `website/scripts/og/` and `website/scripts/badges/` generators must derive every position and width from named padding/font-metric constants — no hardcoded text x or `+ 26`-style magic offsets. If you change either generator, run the geometry debug snippet (see comments in `design-tokens.mjs`) before rendering, and visually inspect at least one descender-bearing headline and the largest icon size. Use the `svg-text-geometry` skill for the general pattern.

## CI

- **ci-monorepo-check.yml**: Runs on PR/push — formatting, analyze, tests
- **ci-matrix-os.yml**: Cross-platform tests (Ubuntu, macOS, Windows)
- **integration-e2e-nightly.yml**: Nightly Ollama e2e tests with qwen3:1.7b
