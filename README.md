# Glue

```
        .__
   ____ |  |  __ __   ____
  / ___\|  | |  |  \_/ __ \
 / /_/  >  |_|  |  /\  ___/
 \___  /|____/____/  \___  >
/_____/                  \/
```

**The coding agent that holds it all together.**

A terminal-native AI coding agent built in Dart — multi-model, multi-agent, fast.

## Packages

| Directory              | Description                         |
| ---------------------- | ----------------------------------- |
| [`cli/`](cli/)         | Glue TUI — the main CLI application |
| [`website/`](website/) | Marketing site and documentation    |
| [`agents/`](agents/)   | Architecture specs and design docs  |

## Quick Start

```bash
cd cli
dart pub get
just build    # compile AOT binary → ./glue
just install  # symlink to ~/.local/bin/glue
```

Set your API key and go:

```bash
export ANTHROPIC_API_KEY=sk-...
glue
```

See [`cli/README.md`](cli/README.md) for full usage, configuration, and architecture docs.

## Development

```bash
just build      # monorepo build (cli + devdocs + website validation)
just test       # monorepo tests (cli + website validation)
just check      # monorepo quality gate (cli + devdocs + website)
just clean      # monorepo cleanup

just cli-build  # fast cli-only build
just cli-test   # fast cli-only tests
just cli-check  # fast cli-only check
```

Command scope:

- Root `just ...` recipes are monorepo-wide defaults.
- `just cli::...` (or `just cli-*`) targets only the CLI package.
- `just infra::...` remains opt-in for local Docker infrastructure workflows.

## License

MIT
