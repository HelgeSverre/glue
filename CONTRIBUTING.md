# Contributing

Thanks for contributing to Glue.

This repository is a monorepo with three main parts:

- `cli/` — the main Glue CLI and TUI application (Dart)
- `website/` — the docs and marketing site
- `docs/` — canonical reference material such as model metadata and design docs

Most code changes happen in `cli/`.

## Prerequisites

- [Dart SDK](https://dart.dev/get-dart) 3.4+
- [`just`](https://github.com/casey/just) for the repo shortcuts used throughout this project
- Node.js if you are working on `website/`

## Development Setup

From the repository root:

```sh
# CLI dependencies
cd cli
dart pub get

# Back to repo root
cd ..
```

If you are working on the website, install its dependencies as well:

```sh
cd website
npm install
cd ..
```

## Repository Layout

```text
cli/      Main Glue application
website/  Docs and marketing site
docs/     Reference docs, plans, and model catalog source
```

## Common Commands

From the repository root:

```sh
just              # list available recipes
just build        # monorepo build
just test         # monorepo tests
just check        # monorepo quality gate
```

For CLI-focused work, most commands are run from `cli/`:

```sh
cd cli

dart run bin/glue.dart                     # run from source
dart compile exe bin/glue.dart -o glue    # build AOT binary

# quality gate
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test

# model catalog maintenance
just gen          # regenerate bundled model catalog
just gen-check    # verify generated catalog is up to date

# OTLP protobuf bindings (only needed if you change observability protos)
just proto-gen
```

Useful repo-level shortcuts:

```sh
just cli::build
just cli::test
just cli::check
just cli::e2e
just integration
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

### For OTEL/protobuf exporter changes

If you touch generated OTLP bindings or the proto sources under `cli/tool/proto/`, also run:

```sh
cd cli
just proto-gen
```

### For generated model catalog changes

If you touch model catalog source in `docs/`, also run:

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
4. Regenerate derived files when required.
5. Write a clear PR description that explains:
    - the problem
    - the approach
    - any tradeoffs or follow-up work

## Code Style Notes

For CLI code in `cli/`:

- Use `package:glue/` imports.
- Prefer small, targeted diffs.
- Match existing patterns and naming in the surrounding code.
- Treat `dart analyze --fatal-infos` as a zero-warning bar.

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
