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
just test     # run all tests
just check    # analyze + test
just build    # compile CLI binary
```

## License

MIT
