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

Environment variables: `GLUE_PROVIDER`, `GLUE_MODEL`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`.

Default models per provider:

| Provider  | Default model       |
| --------- | ------------------- |
| anthropic | `claude-sonnet-4-6` |
| openai    | `gpt-4.1`           |
| ollama    | `llama3.2`          |

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
