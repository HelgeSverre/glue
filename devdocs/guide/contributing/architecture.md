# Architecture Overview

The Glue CLI is built in Dart. The codebase is organized into these main modules:

| Module        | Path                     | Description                                             |
| ------------- | ------------------------ | ------------------------------------------------------- |
| Agent         | `lib/src/agent/`         | Core agent loop, tool dispatch, prompt assembly         |
| Config        | `lib/src/config/`        | Configuration loading, model registry, permission modes |
| LLM           | `lib/src/llm/`           | Provider clients (Anthropic, OpenAI, Mistral, Ollama)   |
| Tools         | `lib/src/tools/`         | Built-in tool implementations                           |
| Shell         | `lib/src/shell/`         | Command execution, Docker sandbox, job management       |
| Web           | `lib/src/web/`           | Web fetch, search, browser automation                   |
| Storage       | `lib/src/storage/`       | Session persistence, config store                       |
| Observability | `lib/src/observability/` | Logging, OTLP, Langfuse integration                     |
| Skills        | `lib/src/skills/`        | Skill registry, parser, tool                            |
| UI            | `lib/src/ui/`            | Terminal rendering, modals, panels                      |
| Input         | `lib/src/input/`         | Line editor, file expansion, streaming input            |
| Commands      | `lib/src/commands/`      | Slash command registry                                  |
| Rendering     | `lib/src/rendering/`     | Markdown rendering, ANSI utilities                      |

## Entry Point

The entry point is `bin/glue.dart`, which delegates to `lib/src/app.dart`.

::: info
For detailed API documentation of each module, see the [API Reference](/api/).
:::
