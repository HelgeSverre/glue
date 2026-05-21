# Contributing

Thanks for contributing to Glue.

This repository is a Dart monorepo. Most code changes happen under `cli/` or `packages/`.

## Prerequisites

- [Dart SDK](https://dart.dev/get-dart) 3.12+
- [`just`](https://github.com/casey/just) for the repo shortcuts used throughout this project
- Node.js if you are working on `website/`

## Repository Layout

```text
cli/                       User-facing binary (bin/glue.dart) + TUI, commands, doctor
packages/
  glue_core/               Pure data types and contracts (SessionEvent, ContentPart, ...)
  glue_strategies/         Strategy interfaces + built-in host/docker executors, workspaces
  glue_runtimes/           Cloud runtime adapters (daytona, sprites, modal)
  glue_harness/            Agent loop, LLM clients, provider adapters, tools, MCP, observability
  glue_server/             ACP server + event mapping
website/                   Unified marketing + docs site (VitePress), served at getglue.dev
docs/                      Reference docs, plans, design notes, model catalog source
```

See `CLAUDE.md` for a deeper architectural overview.

## Development Setup

From the repository root:

```sh
# CLI dependencies (also pulls in path-deps from packages/)
cd cli
dart pub get
cd ..
```

If you are working on the website, install its dependencies as well:

```sh
cd website
npm install
cd ..
```

## Common Commands

From the repository root (uses `just` submodules):

```sh
just              # list available recipes
just build        # monorepo build (CLI binary + website)
just test         # monorepo tests across all packages + cli
just check        # monorepo quality gate (gen-check + analyze + test, per package)
just format       # format every package + cli
just clean        # clean build artifacts everywhere
```

Per-package shortcuts:

```sh
just cli::build
just cli::test
just cli::check
just cli::e2e            # Ollama-backed e2e suite (requires qwen3:1.7b)
just cli::integration    # Network-backed integration suite
just glue_harness::test
just glue_strategies::test
just glue_runtimes::test
just website::build
```

Live cloud runtime suites (require credentials):

```sh
just daytona     # DAYTONA_API_KEY
just sprites     # SPRITES_TOKEN
just modal       # modal CLI + login
```

For CLI-focused work, most commands are run from `cli/`:

```sh
cd cli

dart run bin/glue.dart                    # run from source
just build                                # build AOT binary → ../dist/glue (with version metadata)

# quality gate
dart format --set-exit-if-changed .
dart analyze --fatal-infos                # zero-warning bar
dart test

# single test file
dart test test/llm/anthropic_client_test.dart

# model catalog maintenance
just gen          # regenerate bundled model catalog + version + share assets
just gen-check    # verify generated files are up to date
```

## Before Opening a Pull Request

Run the relevant validation for your change.

### For most CLI changes

```sh
cd cli
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Or simply:

```sh
just cli::check
```

### For changes inside `packages/`

Run that package's quality gate (each package ships its own justfile):

```sh
just glue_harness::check
just glue_strategies::check
# etc.
```

If your change touches contracts in `glue_core` or `glue_strategies` that ripple
through other packages, prefer `just check` to catch cross-package regressions.

### For generated model catalog changes

If you touch model catalog source in `docs/reference/models.yaml`, also run:

```sh
cd cli
just gen
just gen-check
```

### For monorepo-wide changes

If your change affects multiple packages or the website, run from the repo root:

```sh
just check
```

## Pull Request Guidelines

Keep pull requests focused, reviewable, and easy to validate.

1. Keep changes scoped to a single problem where practical.
2. Add or update tests for behavior changes.
3. Update documentation for user-facing changes.
4. Regenerate derived files when required (`just gen` / `just gen-check`).
5. Write a clear PR description that explains:
    - the problem
    - the approach
    - any tradeoffs or follow-up work

## Code Style Notes

For CLI code in `cli/`:

- Use `package:glue/` imports (enforced by `always_use_package_imports`).
- Prefer small, targeted diffs.
- Match existing patterns and naming in the surrounding code.
- Treat `dart analyze --fatal-infos` as a zero-warning bar.
- Sealed classes (`AgentEvent`, `LlmChunk`, `TerminalEvent`) — pattern match with switch/case destructuring.
- Prefer functional collection idioms (`.where`, `.map`, `.toList`, `Map.fromEntries`) over imperative loops for pure filter/transform/aggregate code.

For user-facing stdout from a `Command<int>`, follow `docs/design/cli-output-formatting.md` —
brand markers (`brandDot`, `markerOk/Warn/Error/Info`), the `*_format.dart` extraction pattern,
and `styledOrPlain()` for TTY/`NO_COLOR` safety.

## Reporting Issues

When opening an issue, include:

- expected behavior
- actual behavior
- reproduction steps
- environment details such as OS, Dart version, shell, and provider configuration if relevant

## Need More Context?

See:

- [`README.md`](README.md) for the top-level project overview
- [`cli/README.md`](cli/README.md) for CLI-specific details
- [`CLAUDE.md`](CLAUDE.md) for repository architecture and workflow guidance used by coding agents
