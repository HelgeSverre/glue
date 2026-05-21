# Development Setup

## Prerequisites

- Dart SDK 3.12+
- Git
- [just](https://github.com/casey/just) command runner (recommended)

## Clone and Install

```bash
git clone https://github.com/helgesverre/glue.git
cd glue
dart pub get    # resolves the whole pub workspace (cli + glue_*)
```

## Run from Source

```bash
# Run directly
dart run cli/bin/glue.dart

# Or build and install (from cli/)
cd cli && just install    # compiles → ../dist/glue, symlinks ~/.local/bin/glue
```

## Available Just Commands

The repo uses a [just](https://github.com/casey/just) module layout: root
recipes operate across the whole monorepo, and each package exposes its own
recipes under a `<package>::` namespace (e.g. `just cli::install`).

### From the repo root

```bash
just build          # Monorepo build pass (CLI binary + unified site)
just check          # Monorepo quality gate (all packages)
just test           # Monorepo test pass
just clean          # Monorepo cleanup
```

### Per-package recipes (run from the repo root)

```bash
just cli::install   # Build CLI binary and symlink to ~/.local/bin
just cli::run       # Build and run interactively
just cli::test      # CLI unit tests
just cli::e2e       # CLI e2e tests (requires ollama + qwen3:1.7b)
just cli::analyze   # Static analysis on the CLI package
just cli::format    # Format CLI Dart files
just cli::check     # gen-check + analyze + test + layer hygiene (CLI)
just cli::gen       # Regenerate bundled model catalog + version constants
just cli::docs      # Generate API docs (→ cli/doc/api)
```

The same `<package>::` namespacing is available for `glue_core`,
`glue_strategies`, `glue_runtimes`, `glue_harness`, `glue_server`, and
`website` — run `just --list` from the repo root to see everything.

You can also `cd cli/` and run the unqualified recipes (`just install`,
`just e2e`, …) directly inside any package.

::: tip
Run `just check` (from the repo root) before submitting a pull request to run
the full monorepo quality gate.
:::

## Project Structure

The repo is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces): a
single `pubspec.lock` and `.dart_tool/` at the root are shared by every member
package. Each package's `pubspec.yaml` opts in with `resolution: workspace`.

```
glue/
  pubspec.yaml               # Workspace root (lists members)
  analysis_options.yaml      # Shared lint + analyzer config (each package includes it)
  cli/                       # Binary entry, App controller, TUI, slash commands
  packages/
    glue_core/               # Pure data types and contracts
    glue_strategies/         # Strategy interfaces + built-in impls (LLM, MCP, providers, web, credentials)
    glue_runtimes/           # Cloud runtime adapters (daytona, sprites, modal)
    glue_harness/            # Agent loop, config, sessions, doctor, tools
    glue_server/             # ACP server + SessionEvent → ACP mapping
  website/                   # Unified marketing + docs site (VitePress)
  docs/                      # Canonical reference material (models.yaml, plans, design)
  dist/glue                  # AOT binary output (gitignored, from `just cli::build`)
```
