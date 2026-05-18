# Runtimes

Glue picks where to run commands at startup. Tools (`bash`, `read_file`,
`write_file`, `edit_file`, `list_directory`, `grep`) and background jobs all
route through the chosen runtime, so the agent's prompt is identical
regardless of where work actually happens.

For the capability matrix and full background, see [**Runtimes →**](/runtimes).

## Available runtimes

| Runtime   | Status        | Use when                                                                 |
| --------- | ------------- | ------------------------------------------------------------------------ |
| `host`    | shipping      | Default. Fast feedback, direct access to your tools.                     |
| `docker`  | shipping      | Untrusted code, dependency installs, generated scripts.                  |
| `daytona` | shipping      | General-purpose cloud sandbox (REST API; US + EU).                       |
| `sprites` | shipping      | Persistent Fly.io sandbox; resumes by name; auto-sleeps when idle.       |
| `modal`   | shipping      | Modal sandbox tied to a Modal App; runaway-billing cap built in.         |

## Selecting a runtime

In precedence order:

1. `GLUE_RUNTIME=daytona` (env var)
2. `runtime: daytona` in `~/.glue/config.yaml`
3. Legacy fallback — `docker.enabled: true` selects Docker; otherwise host.

Per-runtime options live in matching top-level YAML sections (`daytona:`,
`sprites:`, `modal:`, `docker:`). Each adapter also reads its own env vars
(e.g. `DAYTONA_API_KEY`, `MODAL_APP`) — see the
[config reference](https://github.com/helgesverre/glue/blob/main/docs/reference/config-yaml.md) for the full table.

## Per-runtime guides

- [Docker sandbox](/docs/using-glue/docker-sandbox)
- [Daytona](/docs/using-glue/daytona)
- [Sprites](/docs/using-glue/sprites)
- [Modal](/docs/using-glue/modal)

## How it's wired

- `RuntimeFactory.create(...)` returns a `RuntimeSession` (executor +
  workspace + sandbox metadata).
- Cloud adapters register at startup via `register{Daytona,Sprites,Modal}Runtime()`
  in `cli/bin/glue.dart`.
- File tools and `ShellJobManager` route through the session's `Workspace`
  and `CommandExecutor` — there are no `dart:io` paths in the tool layer.

For implementation details, see
[`packages/glue_strategies/lib/src/runtime/runtime_factory.dart`](https://github.com/helgesverre/glue/blob/main/packages/glue_strategies/lib/src/runtime/runtime_factory.dart)
and the per-adapter `register*Runtime()` helpers in
[`packages/glue_runtimes/`](https://github.com/helgesverre/glue/tree/main/packages/glue_runtimes).
