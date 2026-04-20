# TODO: redo this readme from scratch.

# Glue

**The coding agent that holds it all together.**

A terminal-native AI coding agent built in Dart — multi-model, multi-agent, fast.

## Packages

| Directory              | Description                                                         |
| ---------------------- | ------------------------------------------------------------------- |
| [`cli/`](cli/)         | Glue TUI — the main CLI application                                 |
| [`website/`](website/) | Unified marketing + docs site (VitePress) — served at `getglue.dev` |
| [`docs/`](docs/)       | Canonical reference material (`models.yaml`, plans, design docs)    |

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
just build       # monorepo build (cli + unified site)
just test        # monorepo tests (cli)
just check       # monorepo quality gate (cli + site)
just clean       # monorepo cleanup

just cli::build  # cli-only build
just cli::test   # cli-only tests
just cli::check  # cli-only check

just site-dev    # serve the unified getglue.dev site locally
just site-build  # build the unified site (output: website/.vitepress/dist)
just site-check  # site quality gate (build + any additional checks)
```

Command scope:

- Root `just ...` recipes are monorepo-wide defaults.
- `just cli::...` targets only the CLI package.
- `just site-*` wraps the `website/` module — marketing + docs share one
  pipeline. The prior static `website/` is archived under
  [`_archived/website-2026-04/`](_archived/website-2026-04/).

## License

MIT
