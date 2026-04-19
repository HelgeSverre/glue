# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

Monorepo with three components:
- `cli/` — Main Glue CLI application (Dart). This is where most development happens.
- `website/` — Unified marketing + docs site (VitePress), served at getglue.dev
- `docs/` — Canonical reference material (models.yaml, plans, design docs)

## Common Commands

All commands assume working directory is `cli/` unless noted.

```sh
# Build & run
dart compile exe bin/glue.dart -o glue    # AOT binary
dart run bin/glue.dart                     # Run from source

# Quality gate (run before committing)
dart format --set-exit-if-changed .
dart analyze --fatal-infos                 # Zero warnings policy
dart test

# Single test file
dart test test/llm/anthropic_client_test.dart

# E2E tests (requires Ollama + qwen3:1.7b)
dart test --run-skipped -t e2e

# Monorepo shortcuts (from repo root, requires just)
just check          # Full quality gate
just cli::check     # CLI only: format + analyze + test
just cli::test      # CLI tests only
```

## Architecture

Glue is a terminal-native coding agent. The main layers:

**Agent loop** (`agent/`): `AgentCore` runs the LLM↔tool ReAct loop, streaming `AgentEvent`s (sealed class — use switch/case pattern matching). `AgentRunner` executes agents headlessly. `AgentManager` spawns subagents.

**App controller** (`app.dart` + `app/` part files): Event-driven architecture merging terminal input and agent events into a single stream. 60fps async rendering with scroll regions. Never blocks.

**LLM providers** (`llm/`): `LlmClient` interface with implementations for Anthropic (SSE), OpenAI/Mistral (SSE), and Ollama (NDJSON). `LlmFactory` creates clients from config.

**Shell execution** (`shell/`): `CommandExecutor` abstraction — `HostExecutor` (runs via user's `$SHELL`) and `DockerExecutor` (ephemeral containers). `ExecutorFactory` selects with auto-fallback.

**Config** (`config/`): `GlueConfig` resolves: CLI args → env vars → `~/.glue/config.yaml` → defaults.

**Rendering** (`terminal/` + `rendering/`): Raw terminal I/O, ANSI rendering, layout with output/overlay/status/input zones, markdown renderer.

**Other key modules**: `skills/` (skill discovery and execution), `web/` (browser automation and search providers), `tools/` (web tools, subagent tools), `storage/` (session persistence), `observability/` (tracing, OTEL, Langfuse).

## Code Conventions

- **Imports**: Always use `package:glue/` imports (enforced by lint rule `always_use_package_imports`). Barrel export via `lib/glue.dart`.
- **Events/unions**: Sealed classes for `AgentEvent`, `LlmChunk`, `TerminalEvent` — pattern match with switch/case destructuring.
- **Streaming**: Use `Stream<T> async*` generators.
- **Tool interface**: `abstract class Tool` with `execute(Map<String, dynamic>) → Future<String>`.
- **Tests**: Mirror `lib/src/` structure in `test/`. E2E tests tagged `@Tags(['e2e'])`, skipped by default.
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
