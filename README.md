<h1 align="center">Glue</h1>

<p align="center"><strong>A small coding agent for the terminal.</strong></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square&labelColor=0a0a0b" alt="license MIT"></a>
  <img src="https://img.shields.io/badge/dart-3.4+-3b82f6?style=flat-square&labelColor=0a0a0b" alt="dart 3.4+">
  <img src="https://img.shields.io/badge/platform-macos%20%7C%20linux%20%7C%20windows-7a7a7a?style=flat-square&labelColor=0a0a0b" alt="platform macos linux windows">
  <img src="https://img.shields.io/badge/status-alpha-facc15?style=flat-square&labelColor=0a0a0b" alt="status alpha">
  <a href="https://getglue.dev"><img src="https://img.shields.io/badge/website-getglue.dev-facc15?style=flat-square&labelColor=0a0a0b" alt="getglue.dev"></a>
</p>

---

Edits files, runs shell, keeps resumable sessions — the usual things. The web tooling is a bit more developed than in most coding agents: browser automation, fetch with OCR fallback, search. That's because I use Glue for scraping and automation about as much as for coding. Runs on your host or in a Docker sandbox.

## Packages

| Directory              | Description                                                         |
| ---------------------- | ------------------------------------------------------------------- |
| [`cli/`](cli/)         | Glue CLI and TUI — the main application (Dart)                      |
| [`website/`](website/) | Unified marketing + docs site (VitePress) — served at `getglue.dev` |
| [`docs/`](docs/)       | Canonical reference material (`models.yaml`, plans, design docs)    |
| [`agents/`](agents/)   | Brand guide, architecture notes, and agent prototype material       |
| [`backlog/`](backlog/) | Backlog.md task and milestone tracking                              |

## Quick start

Requires [Dart SDK](https://dart.dev/get-dart) ≥ 3.4 and [just](https://github.com/casey/just).

```bash
cd cli
dart pub get
just build      # compile AOT binary → ./glue
just install    # symlink to ~/.local/bin/glue
```

Set an API key and launch:

```bash
export ANTHROPIC_API_KEY=sk-...
glue
```

Other providers work out of the box: OpenAI, Mistral, GitHub Copilot (OAuth device flow), and Ollama (local).

Non-interactive use:

```bash
glue -p anthropic -m claude-sonnet-4-6   # choose provider and model
glue --resume                            # session picker
glue --continue                          # resume most recent session
glue doctor                              # config and install health check
glue completions install                 # shell completions (zsh/bash/fish/pwsh)
```

See [getglue.dev](https://getglue.dev) for the full feature tour, provider setup, and examples.

## Development

The root `justfile` wraps the `cli/` and `website/` modules.

```bash
just              # list all recipes
just build        # monorepo build (CLI binary + site)
just test         # monorepo tests (CLI)
just check        # monorepo quality gate (CLI + site)
just clean        # monorepo cleanup

just cli::build   # CLI only: AOT binary
just cli::test    # CLI only: unit tests
just cli::check   # CLI only: gen-check + analyze + test
just cli::e2e     # e2e suite (requires Ollama + qwen3:1.7b)

just site-dev     # serve getglue.dev locally
just site-build   # build the unified site
just site-check   # site quality gate
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`cli/README.md`](cli/README.md) for deeper development guidance.
