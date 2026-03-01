# Glue CLI — Agent Guidelines

## Commands

- **Analyze:** `dart analyze`
- **Test all:** `dart test`
- **Single test:** `dart test test/slash_autocomplete_test.dart`
- **E2E tests:** `dart test --run-skipped -t e2e` (requires Ollama + `qwen2.5:7b`)
- **Run:** `dart run bin/glue.dart`

## Architecture

Dart 3.4+ terminal TUI app. `App` (lib/src/app.dart) is the main controller wiring terminal I/O, agent loop, and rendering. `AgentCore` runs the LLM↔tool ReAct loop emitting `AgentEvent`s. LLM providers (Anthropic/OpenAI/Ollama) implement `LlmClient` in lib/src/llm/. `AgentManager`+`AgentRunner` handle headless subagent execution. `GlueConfig` resolves settings from CLI args → env vars → ~/.glue/config.yaml → defaults. Layout divides terminal into output/overlay/status/input zones.

Command execution uses `CommandExecutor` abstraction (`lib/src/shell/`): `HostExecutor` runs commands via the user's shell (respects `$SHELL`, configurable via `GLUE_SHELL`); `DockerExecutor` runs commands in ephemeral Docker containers with bind-mounted directories. `ExecutorFactory` selects the executor based on config with automatic host fallback. `SessionState` persists session-scoped Docker mounts.

Key directories: `agent/` (core loop, runner, manager), `llm/` (provider clients, SSE/NDJSON decoders, tool schemas), `terminal/` (raw terminal I/O, layout), `rendering/` (block renderer, markdown, ANSI utils), `ui/` (modal, autocomplete), `input/` (line editor), `shell/` (command execution, Docker sandbox, shell config), `storage/` (session state, config store), `config/`, `commands/`, `tools/`.

## Code Style

- Use `package:lints/recommended.yaml`. Run `dart analyze` — zero warnings policy.
- Use `package:glue/` imports everywhere (enforced by `always_use_package_imports` lint). Barrel export via lib/glue.dart.
- Sealed classes for event/chunk unions (`AgentEvent`, `LlmChunk`, `TerminalEvent`). Pattern match with `switch`/`case` destructuring.
- Private fields with underscore prefix. Named constructors and factory constructors preferred.
- No comments unless complex logic. No over-engineering — minimal changes only.
- Streaming uses `Stream<T> async*` generators. Tool interface: `abstract class Tool` with `execute(Map<String, dynamic>) → Future<String>`.
- Tests in test/ mirroring lib/src/ structure. Use `package:test`. TDD: write failing test first.

## Testing

- Unit tests: `dart test` (452+ tests, all should pass)
- E2E integration tests: `dart test --run-skipped -t e2e` — requires Ollama running locally with `qwen2.5:7b` pulled (`ollama pull qwen2.5:7b`)
- E2E tests use `AgentRunner` to exercise the full agent loop (LLM → tool call → tool execution → LLM response) headlessly, no terminal required
- E2E tests are tagged `@Tags(['e2e'])` and skipped by default via `dart_test.yaml`
- Small models are non-deterministic; e2e tests use a retry wrapper (3 attempts) for tool-calling tests
- Note: `qwen2.5:7b` refuses to call a tool named "bash" (safety training); other tools work reliably

## TUI Mockups

- Store TUI prototypes as executable shell scripts in `mockups/descriptive-name.sh`
- `chmod +x` so the user can run them in another terminal to preview layouts
- Use ANSI escape codes to render borders, colors, reverse-video selection, etc.
- Name mockups descriptively: `mockups/skills-panel.sh`, `mockups/settings-panel.sh`, etc.
