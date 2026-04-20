# Architecture Overview

The Glue CLI is built in Dart. The codebase is organized into these main modules:

| Module        | Path                     | Description                                                                         |
| ------------- | ------------------------ | ----------------------------------------------------------------------------------- |
| App           | `lib/src/app/`           | Top-level event loop, state, render coordination                                    |
| Agent         | `lib/src/agent/`         | Core agent loop, tool dispatch, prompt assembly, subagent manager                   |
| Catalog       | `lib/src/catalog/`       | Bundled + remote + local model/provider catalog, `ModelRef` parsing                 |
| Commands      | `lib/src/commands/`      | Slash command registry and built-in commands                                        |
| Config        | `lib/src/config/`        | `~/.glue/config.yaml` loading, env var resolution, permission modes                 |
| Core          | `lib/src/core/`          | Service locator, environment helpers                                                |
| Credentials   | `lib/src/credentials/`   | Credential store (env vars + `credentials.json`)                                    |
| Input         | `lib/src/input/`         | Line editor, file expansion, autocomplete                                           |
| LLM           | `lib/src/llm/`           | Wire-protocol clients: Anthropic native, OpenAI HTTP, Ollama NDJSON; `LlmFactory`   |
| Observability | `lib/src/observability/` | Local JSONL spans + debug controller                                                |
| Orchestrator  | `lib/src/orchestrator/`  | Permission gate, tool-permission policies                                           |
| Providers     | `lib/src/providers/`     | Adapters that map catalog providers to LLM clients (Anthropic, OpenAI-compatible)   |
| Rendering     | `lib/src/rendering/`     | Markdown rendering, ANSI utilities                                                  |
| Session       | `lib/src/session/`       | Session manager (lifecycle on top of storage)                                       |
| Shell         | `lib/src/shell/`         | Command execution: host + Docker executors, shell modes                             |
| Skills        | `lib/src/skills/`        | Skill discovery (project + global + custom paths), `SKILL.md` parser, skill tool    |
| Storage       | `lib/src/storage/`       | Session persistence (`meta.json`, `conversation.jsonl`, `state.json`), config store |
| Terminal      | `lib/src/terminal/`      | Raw terminal I/O, key parsing                                                       |
| Tools         | `lib/src/tools/`         | Built-in tool implementations (web fetch, search, browser, subagents)               |
| UI            | `lib/src/ui/`            | TUI panels, modals, status line                                                     |
| Web           | `lib/src/web/`           | Web fetch, search, browser automation backends                                      |

## Entry Point

The entry point is `bin/glue.dart`, which delegates to `lib/src/app.dart`.

::: info
For detailed API documentation of each module, see the [API Reference](/api/).
:::
