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

Glue is a terminal-native coding agent CLI built in Dart. It streams LLM responses, executes tools, and renders everything in a responsive TUI that never blocks.

## Features

- **Multi-provider LLM support** — Anthropic, OpenAI, and Ollama out of the box
- **Streaming tool use** — read/write/edit files, run shell commands, grep, list directories
- **Multi-shell support** — respects `$SHELL` with bash/zsh/fish/pwsh flag mapping and interactive/login modes
- **Docker sandbox** — run agent commands in ephemeral containers with configurable mounts and auto host fallback
- **Subagents** — spawn child agents (single or parallel) with collapsible grouped output
- **Session management** — persist and resume conversations (`--resume` / `--continue`)
- **`@file` references** — inline file contents into prompts with recursive fuzzy autocomplete
- **Responsive TUI** — 60fps async rendering with scroll regions, markdown tables, and animated status spinner
- **Bash mode** — `!` prefix for shell passthrough with background job management
- **Readline input** — Emacs keybindings, word-level navigation (Alt+Left/Right), history
- **YAML config** — `~/.glue/config.yaml` with CLI and env-var overrides
- **Mascot** — animated Glue Blob splash screen with liquid physics simulation

## Install

Requires [Dart SDK](https://dart.dev/get-dart) >= 3.4 and [just](https://github.com/casey/just).

```bash
just install    # compile AOT binary → ~/.local/bin/glue
```

Or run directly without installing:

```bash
dart run bin/glue.dart
```

## Usage

```bash
glue                                    # start a new session
glue -p anthropic -m claude-sonnet-4-6  # choose provider & model
glue --resume                           # open session picker
glue --continue                         # resume most recent session
glue --help                             # show all options
```

### CLI flags

| Flag         | Short | Description                                    |
| ------------ | ----- | ---------------------------------------------- |
| `--help`     | `-h`  | Show usage information                         |
| `--version`  | `-v`  | Print version                                  |
| `--provider` | `-p`  | LLM provider (`anthropic`, `openai`, `ollama`) |
| `--model`    | `-m`  | LLM model to use                               |
| `--resume`   |       | Start with session picker open                 |
| `--continue` |       | Resume most recent session                     |

### Configuration

Config is resolved in order: **CLI flags → env vars → `~/.glue/config.yaml` → defaults**.

Environment variables: `GLUE_PROVIDER`, `GLUE_MODEL`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GLUE_SHELL`, `GLUE_SHELL_MODE`, `GLUE_DOCKER_ENABLED`, `GLUE_DOCKER_IMAGE`, `GLUE_DOCKER_SHELL`, `GLUE_DOCKER_MOUNTS`.

Default models per provider:

| Provider  | Default model       |
| --------- | ------------------- |
| anthropic | `claude-sonnet-4-6` |
| openai    | `gpt-4.1`           |
| ollama    | `llama3.2`          |

### Shell configuration

By default, glue uses `$SHELL` (or `sh` if unset) in non-interactive mode. Override via config or env vars:

```yaml
# ~/.glue/config.yaml
shell:
  executable: zsh            # bash, zsh, fish, pwsh, sh
  mode: interactive          # non_interactive | interactive | login
```

Interactive mode loads your rc files (`~/.bashrc`, `~/.zshrc`, etc.), giving access to aliases and shell functions. Login mode loads profile files.

### Docker sandbox

Run all agent shell commands inside ephemeral Docker containers for isolation:

```yaml
# ~/.glue/config.yaml
docker:
  enabled: true
  image: ubuntu:24.04        # container image
  shell: sh                  # shell inside container
  fallback_to_host: true     # fall back if Docker unavailable
  mounts:                    # always-mounted directories
    - /path/to/shared/libs
    - /path/to/data:ro       # read-only mount
```

Or via environment: `GLUE_DOCKER_ENABLED=1 GLUE_DOCKER_IMAGE=alpine:latest glue`

The current working directory is always mounted at `/work` inside the container. Additional directories can be mounted per-session (persisted in session state).

## Justfile commands

```bash
just            # list available commands
just build      # compile AOT native binary (→ ./glue)
just install    # build + symlink to ~/.local/bin/glue
just run        # build and run interactively
just test       # run tests (pass args: just test test/llm/)
just analyze    # static analysis
just check      # analyze + test
just docs       # generate dartdoc API docs
just docs-serve # generate and serve dartdoc locally
just release    # bump version, build, tag
just clean      # remove compiled binary
```

## Testing

```bash
dart test                              # unit tests (452+ tests)
dart test --run-skipped -t e2e         # e2e integration tests
```

E2E tests exercise the full agent loop (LLM → tool call → tool execution → LLM response) headlessly via `AgentRunner`, no terminal required. They require Ollama running locally:

```bash
ollama pull qwen2.5:7b                 # one-time setup
dart test --run-skipped -t e2e         # run e2e tests
```

> **Note:** `qwen2.5:7b` is the smallest model that reliably supports Ollama tool calling. `gemma3` variants do not support tools. Small models are non-deterministic — e2e tests use a retry wrapper (3 attempts).

## Tools

The agent has access to these tools:

| Tool                       | Description                               |
| -------------------------- | ----------------------------------------- |
| `read_file`                | Read file contents                        |
| `write_file`               | Create or overwrite a file                |
| `edit_file`                | Apply targeted find-and-replace edits     |
| `bash`                     | Run shell commands (configurable timeout) |
| `grep`                     | Search file contents with regex           |
| `list_directory`           | List directory entries                    |
| `spawn_subagent`           | Spawn a child agent for a subtask         |
| `spawn_parallel_subagents` | Run multiple subagents concurrently       |

## Architecture

```
Terminal (raw I/O, ANSI parsing, mouse/resize events)
  ├─ Layout (scroll regions, output/overlay/status/input zones)
  ├─ ScreenBuffer (virtual cells, diff-flush)
  └─ Input parsing (CSI sequences, Alt/Ctrl modifiers, SGR mouse)
LineEditor (readline-style input, history, word navigation)
App (event bus, state machine, render loop @ 60fps)
  ├─ AgentCore (LLM streaming, tool loop, parallel tool calls)
  │    ├─ Tools (read_file, write_file, edit_file, bash, grep, list_directory)
  │    └─ AgentManager (subagent lifecycle, depth-limited recursion)
  ├─ CommandExecutor (shell abstraction)
  │    ├─ HostExecutor (native shell: bash/zsh/fish/pwsh via ShellConfig)
  │    └─ DockerExecutor (ephemeral containers, cidfile tracking)
  ├─ Rendering (BlockRenderer, MarkdownRenderer, ANSI utilities)
  ├─ Mascot (liquid simulation, goo explosion particle system)
  ├─ Modals (inline confirm, full-screen panel with scrolling)
  └─ Overlays (slash autocomplete, @file hints)
```

The TUI and agent core run on separate async tracks — the UI is always responsive because input events and agent events merge into a single render cycle via Dart streams.

## Keyboard shortcuts

| Shortcut              | Action                                   |
| --------------------- | ---------------------------------------- |
| `Enter`               | Submit input                             |
| `Ctrl+C`              | Cancel / double-tap to exit              |
| `Ctrl+U`              | Clear line before cursor                 |
| `Ctrl+K`              | Kill line after cursor                   |
| `Ctrl+W`              | Delete previous word                     |
| `Alt+Backspace`       | Delete previous word                     |
| `Alt+Left`            | Move cursor to previous word             |
| `Alt+Right`           | Move cursor to next word                 |
| `Ctrl+A` / `Home`     | Move to start of line                    |
| `Ctrl+E` / `End`      | Move to end of line                      |
| `Up` / `Down`         | Navigate history                         |
| `Tab`                 | Autocomplete                             |
| `PageUp` / `PageDown` | Scroll output                            |
| `!`                   | Enter bash mode (at start of empty line) |

## Brand

- **Yellow**: `#FACC15` — primary accent, prompt chevron, status highlights
- **Near-black**: `#0A0A0B` — terminal backgrounds, dark surfaces
- **Warm white**: `#FAFAFA` — primary text
- **Gold**: `#EAB308` — hover states, secondary accent
- **Amber**: `#F59E0B` — warnings, tool call highlights

The Glue Blob mascot is a cheerful, honey-yellow amorphous blob character that appears on the splash screen with a liquid physics simulation — click it too many times and it explodes into goo particles.
