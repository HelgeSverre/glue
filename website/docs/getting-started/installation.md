# Installation

## Quick install

The fastest way to get Glue is a prebuilt binary from GitHub Releases.

<InstallSnippet />

### macOS via Homebrew

```bash
brew install helgesverre/tap/glue
```

### Windows

Download `glue-windows-x64.exe` from the [latest GitHub release](https://github.com/helgesverre/glue/releases/latest) and place it somewhere on your `PATH`.

```bash
brew install helgesverre/tap/glue
```

### Windows

Download `glue-windows-x64.exe` from the [latest GitHub release](https://github.com/helgesverre/glue/releases/latest) and place it somewhere on your `PATH`.

## Prerequisites

To run Glue you need:

- **Git** — required for worktree support.
- **API key** for at least one LLM provider (Anthropic, OpenAI, Gemini, Mistral, Groq, OpenRouter, GitHub Copilot via OAuth device-code, or a local Ollama instance — no key needed for Ollama or Copilot).

To build from source you also need the **Dart SDK 3.12+** — available at [dart.dev/get-dart](https://dart.dev/get-dart). If you already have the Flutter SDK installed, the Dart SDK is included. Verify with `dart --version`.

## Install from Source

Clone the repository and install using `just` or run directly with Dart:

```bash
# Clone the repository
git clone https://github.com/helgesverre/glue.git
cd glue

# Install (option A: using just) — compiles → dist/glue, symlinks ~/.local/bin/glue
just cli::install

# Install (option B: run directly with Dart)
dart run cli/bin/glue.dart
```

## Verify the Installation

After installing, confirm that Glue is available on your path:

```bash
glue --version
```

You should see the installed version printed to your terminal. If the command is not found, make sure that Dart's global package bin directory is in your `PATH`.

## Launch Glue in a Project

Navigate to any project directory and launch an interactive session:

```bash
cd my-project
glue
```

::: info
Glue operates in the context of your current working directory. Always `cd` into the project you want to work on before launching.
:::

## Where Glue stores its files

All personal state — config, credentials, sessions, logs — lives under a
single directory we call `GLUE_HOME`. By default it's `~/.glue/`:

| OS               | Path                    |
| ---------------- | ----------------------- |
| macOS            | `/Users/<you>/.glue/`   |
| Linux            | `/home/<you>/.glue/`    |
| Windows (native) | `C:\Users\<you>\.glue\` |

The directory is created on first run. Override with the `GLUE_HOME`
environment variable if you want it somewhere else (dotfiles, per-project).
See [Configuration](./configuration) for the full layout.

## Next Steps

With Glue installed, head to the [Quick Start](./quick-start) guide to configure your API key and send your first prompt.

## See also

- [Quick Start](./quick-start) -- set up your API key and run your first session
- [Configuration](./configuration) -- global config and environment overrides
