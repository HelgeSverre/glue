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
- **Subagents** — spawn child agents (single or parallel) for complex tasks
- **Session management** — persist and resume conversations (`--resume` / `--continue`)
- **`@file` references** — inline file contents into prompts with fuzzy autocomplete
- **Responsive TUI** — async rendering with scroll regions, markdown output, and a readline-style editor
- **YAML config** — `~/.glue/config.yaml` with CLI and env-var overrides

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
glue                           # start a new session
glue -p anthropic -m claude-sonnet-4-6   # choose provider & model
glue --resume                  # open session picker
glue --continue                # resume most recent session
glue completions install       # install shell completions for current shell
glue --help                    # show all options
```

### CLI flags

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show usage information |
| `--version` | `-v` | Print version |
| `--provider` | `-p` | LLM provider (`anthropic`, `openai`, `ollama`) |
| `--model` | `-m` | LLM model to use |
| `--resume` | | Start with session picker open |
| `--continue` | | Resume most recent session |

### Shell completions

```bash
glue completions install
glue completions install --shell zsh
glue completions install --shell bash
glue completions install --shell fish
glue completions install --shell powershell
glue completions install --shell pwsh
glue completions uninstall
glue completions uninstall --shell zsh
```

`install` and `uninstall` auto-detect your shell by default. You can override it
with `--shell`.

Supported shells: `zsh`, `bash`, `fish`, and `powershell` (`pwsh` alias).
`sh` does not provide a standard programmable completion API and is not supported.

For PowerShell, Glue updates the profile returned by
`$PROFILE.CurrentUserAllHosts` when `pwsh`/`powershell` is available.

### Configuration

Config is resolved in order: **CLI flags → env vars → `~/.glue/config.yaml` → defaults**.

Environment variables: `GLUE_PROVIDER`, `GLUE_MODEL`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`.

Default models per provider:

| Provider | Default model |
|----------|--------------|
| anthropic | `claude-sonnet-4-6` |
| openai | `gpt-4.1` |
| ollama | `llama3.2` |

## Justfile commands

```bash
just            # list available commands
just build      # compile AOT native binary (→ ./glue)
just install    # build + symlink to ~/.local/bin/glue
just link       # install via dart pub global activate (JIT, slower startup)
just docs       # generate dartdoc and serve locally
just uninstall  # remove installed binary and symlink
just clean      # remove compiled binary
```

## Tools

The agent has access to these tools:

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_file` | Create or overwrite a file |
| `edit_file` | Apply targeted edits to a file |
| `bash` | Run shell commands |
| `grep` | Search file contents with regex |
| `list_directory` | List directory entries |
| `spawn_subagent` | Spawn a child agent for a subtask |
| `spawn_parallel_subagents` | Run multiple subagents concurrently |

## Architecture

```
Terminal (raw I/O, ANSI)
  └─ Layout (scroll regions, zones)
       └─ ScreenBuffer (virtual cells, diff-flush)
  └─ LineEditor (readline-style input)
App (event bus, state machine, render loop)
  └─ AgentCore (LLM streaming, tool loop)
       └─ Tools (read_file, write_file, edit_file, bash, grep, list_directory)
       └─ AgentManager (subagent lifecycle)
```

The TUI and agent core run on separate async tracks — the UI is always responsive because input events and agent events merge into a single render cycle via Dart streams.

## Brand

- Amber/gold: `#F5A623` — primary accent
- Deep charcoal: `#1A1A2E` — background
- Warm white: `#F0E6D3` — text
