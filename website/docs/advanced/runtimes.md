# Runtimes

See the full runtime page for the capability matrix and config examples:

[**Runtimes →**](/runtimes)

The short version:

- **Host** — commands run in your shell on your machine.
- **Docker** — ephemeral container, workspace mounted in. See
  [Docker Sandbox](/docs/using-glue/docker-sandbox).
- **Cloud** — planned; tracked by the runtime boundary plan in the repo.

Runtime selection happens through `CommandExecutor` and `ExecutorFactory`
in `cli/lib/src/shell/`.
