# Glue CLI — Agent Guidelines

## Commands

- **Analyze:** `dart analyze`
- **Test all:** `dart test`
- **Single test:** `dart test test/slash_autocomplete_test.dart`
- **Run:** `dart run bin/glue.dart`

## Architecture

Dart 3.4+ terminal TUI app. `App` (lib/src/app.dart) is the main controller wiring terminal I/O, agent loop, and rendering. `AgentCore` runs the LLM↔tool ReAct loop emitting `AgentEvent`s. LLM providers (Anthropic/OpenAI/Ollama) implement `LlmClient` in lib/src/llm/. `AgentManager`+`AgentRunner` handle headless subagent execution. `GlueConfig` resolves settings from CLI args → env vars → ~/.glue/config.yaml → defaults. Layout divides terminal into output/overlay/status/input zones.

Key directories: `agent/` (core loop, runner, manager), `llm/` (provider clients, SSE/NDJSON decoders, tool schemas), `terminal/` (raw terminal I/O, layout), `rendering/` (block renderer, markdown, ANSI utils), `ui/` (modal, autocomplete), `input/` (line editor), `config/`, `commands/`, `tools/`.

## Code Style

- Use `package:lints/recommended.yaml`. Run `dart analyze` — zero warnings policy.
- Relative imports within lib/src/. Barrel export via lib/glue.dart.
- Sealed classes for event/chunk unions (`AgentEvent`, `LlmChunk`, `TerminalEvent`). Pattern match with `switch`/`case` destructuring.
- Private fields with underscore prefix. Named constructors and factory constructors preferred.
- No comments unless complex logic. No over-engineering — minimal changes only.
- Streaming uses `Stream<T> async*` generators. Tool interface: `abstract class Tool` with `execute(Map<String, dynamic>) → Future<String>`.
- Tests in test/ mirroring lib/src/ structure. Use `package:test`. TDD: write failing test first.
