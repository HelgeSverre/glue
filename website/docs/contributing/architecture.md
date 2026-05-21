# Architecture Overview

Glue is a Dart monorepo. The user-facing binary lives in `cli/`; the rest
of the codebase is split into reusable packages under `packages/`.

## Packages

| Package           | Path                        | Description                                                                                                         |
| ----------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `glue_core`       | `packages/glue_core/`       | Pure data types and contracts: `SessionEvent`, `ContentPart`, `WorkspaceMapping`, `RunningCommandHandle`            |
| `glue_strategies` | `packages/glue_strategies/` | Strategy interfaces + built-in impls: `CommandExecutor` (host/docker), `Workspace`, `RuntimeFactory`, web providers |
| `glue_runtimes`   | `packages/glue_runtimes/`   | Cloud runtime adapters (`daytona/`, `sprites/`, `modal/`); shared bootstrap + FS transport                          |
| `glue_harness`    | `packages/glue_harness/`    | Agent loop, LLM clients, providers, tools, MCP client, config, sessions, doctor                                     |
| `glue_server`     | `packages/glue_server/`     | ACP server + `SessionEvent` → ACP update mapping                                                                    |
| `cli`             | `cli/`                      | Binary entry (`bin/glue.dart`), App controller, terminal/rendering/UI, slash commands                               |

## Modules

| Module        | Location                                           | Description                                                                                                    |
| ------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| App           | `cli/lib/src/app.dart` + `lib/src/app/`            | Top-level event loop, state, render coordination                                                               |
| Agent         | `glue_harness/lib/src/agent/`                      | Core agent loop, tool dispatch, prompt assembly, subagent manager                                              |
| Catalog       | `glue_harness/lib/src/catalog/`                    | Bundled + remote + local model/provider catalog, `ModelRef` parsing                                            |
| Commands      | `cli/lib/src/commands/`                            | Slash command registry and built-in commands (`/model`, `/runtime`, `/mcp`, …)                                 |
| Config        | `glue_harness/lib/src/config/`                     | `~/.glue/config.yaml` loading, env-var resolution, permission modes                                            |
| Core          | `glue_harness/lib/src/core/`                       | Service locator, environment helpers                                                                           |
| Credentials   | `glue_strategies/lib/src/credentials/`             | Credential store (env vars + `credentials.json`)                                                               |
| Doctor        | `cli/lib/src/doctor/`                              | `glue doctor` health checks; per-runtime sections for host/docker/cloud                                        |
| Input         | `cli/lib/src/input/`                               | Line editor, file expansion, autocomplete                                                                      |
| LLM           | `glue_strategies/lib/src/llm/`                     | Wire-protocol clients: Anthropic native, OpenAI HTTP, Ollama NDJSON; `LlmFactory`                              |
| MCP           | `glue_strategies/lib/src/mcp_client/`              | MCP client pool, stdio/HTTP/WebSocket transports, OAuth                                                        |
| Observability | `glue_harness/lib/src/observability/`              | Local JSONL spans + debug controller                                                                           |
| Orchestrator  | `glue_harness/lib/src/orchestrator/`               | Permission gate, tool-permission policies                                                                      |
| Providers     | `glue_strategies/lib/src/providers/`               | Adapters that map catalog providers to LLM clients                                                             |
| Rendering     | `cli/lib/src/rendering/`                           | Markdown rendering, ANSI utilities                                                                             |
| Runtimes      | `glue_strategies/` + `glue_runtimes/`              | `CommandExecutor` + `Workspace` + `RuntimeSession`; built-in host/docker; cloud adapters daytona/sprites/modal |
| Session       | `glue_harness/lib/src/session/`                    | Session manager (lifecycle on top of storage)                                                                  |
| Skills        | `glue_harness/lib/src/skills/`                     | Skill discovery (project + global + custom paths), `SKILL.md` parser                                           |
| Storage       | `glue_harness/lib/src/storage/`                    | Session persistence (`meta.json`, `conversation.jsonl`, `state.json`)                                          |
| Terminal      | `cli/lib/src/terminal/`                            | Raw terminal I/O, key parsing                                                                                  |
| Tools         | `glue_harness/lib/src/agent/tools.dart` + `tools/` | Built-in tool implementations (bash, files, web, subagents, skills)                                            |
| UI            | `cli/lib/src/ui/`                                  | TUI panels, modals, status line                                                                                |
| Web           | `glue_strategies/lib/src/web/`                     | Web fetch, search, browser automation backends                                                                 |

## Entry Point

The entry point is `cli/bin/glue.dart`. It registers cloud runtime adapters
(`registerDaytonaRuntime()`, `registerSpritesRuntime()`, `registerModalRuntime()`)
with `RuntimeFactory`, then delegates to `cli/lib/src/app.dart` for the
interactive TUI or to a CLI subcommand handler.

::: info
For detailed API documentation of each module, see the [API Reference](/api/).
:::
