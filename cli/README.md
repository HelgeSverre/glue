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
glue -m claude-sonnet-4-6               # choose model
glue --resume                           # open session picker
glue --resume 1740654600000-abc         # resume a specific session
glue --resume 1740654600000-abc "pick up from here"  # resume + send prompt
glue --continue                         # resume most recent session
glue completions install                # install shell completions for current shell
glue --help                             # show all options
```

### CLI flags

| Flag         | Short | Description                                                        |
|--------------|-------|--------------------------------------------------------------------|
| `--help`     | `-h`  | Show usage information                                             |
| `--version`  | `-v`  | Print version                                                      |
| `--print`    | `-p`  | Print response to stdout without interactive mode                  |
| `--model`    | `-m`  | LLM model to use                                                   |
| `--debug`    | `-d`  | Enable debug mode (verbose logging)                                |
| `--resume`   | `-r`  | Open session picker, or resume a session when given an ID / query |
| `--continue` |       | Resume most recent session                                         |

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

Environment variables: `GLUE_PROVIDER`, `GLUE_MODEL`, `GLUE_DEBUG`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
`MISTRAL_API_KEY`, `GLUE_SHELL`, `GLUE_SHELL_MODE`, `GLUE_DOCKER_ENABLED`, `GLUE_DOCKER_IMAGE`, `GLUE_DOCKER_SHELL`,
`GLUE_DOCKER_MOUNTS`, `BRAVE_API_KEY`, `TAVILY_API_KEY`, `FIRECRAWL_API_KEY`.

Default models per provider:

| Provider  | Default model       |
|-----------|---------------------|
| anthropic | `claude-sonnet-4-6` |
| openai    | `gpt-4.1`           |
| mistral   | `devstral-latest`   |
| ollama    | `qwen3-coder:30b`   |

Ollama hardware-tier suggestions:

| Hardware                  | Suggested pull                          |
|---------------------------|-----------------------------------------|
| 16 GB laptop / CPU-only   | `ollama pull qwen3:8b`                  |
| 12–24 GB GPU (mainstream) | `ollama pull qwen3-coder:30b` (default) |
| 32 GB dense-only GPU      | `ollama pull devstral-small-2:24b`      |
| 48 GB+ workstation        | `ollama pull qwen3-coder-next:80b`      |

Ollama tags default to Q4_K_M. For higher fidelity on large tool schemas, pull `:size-q5_K_M` (~1.2× memory),
`:size-q6_K` (~1.5×), or `:size-q8_0` (~2×) and select the tag in `/model`.

### Shell configuration

By default, glue uses `$SHELL` (or `sh` if unset) in non-interactive mode. Override via config or env vars:

```yaml
# ~/.glue/config.yaml
shell:
  executable: zsh # bash, zsh, fish, pwsh, sh
  mode: interactive # non_interactive | interactive | login
```

Interactive mode loads your rc files (`~/.bashrc`, `~/.zshrc`, etc.), giving access to aliases and shell functions.
Login mode loads profile files.

### Docker sandbox

Run all agent shell commands inside ephemeral Docker containers for isolation:

```yaml
# ~/.glue/config.yaml
docker:
  enabled: true
  image: ubuntu:24.04 # container image
  shell: sh # shell inside container
  fallback_to_host: true # fall back if Docker unavailable
  mounts: # always-mounted directories
    - /path/to/shared/libs
    - /path/to/data:ro # read-only mount
```

Or via environment: `GLUE_DOCKER_ENABLED=1 GLUE_DOCKER_IMAGE=alpine:latest glue`

The current working directory is always mounted at `/workspace` inside the container. Additional directories can be
mounted per-session (persisted in session state).

### Debug logging

Enable verbose debug logging with `--debug` / `-d`, `GLUE_DEBUG=1`, or the `/debug` slash command at runtime. Local span
records are written to `~/.glue/logs/spans-YYYY-MM-DD.jsonl`.

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

E2E tests exercise the full agent loop (LLM → tool call → tool execution → LLM response) headlessly via `AgentRunner`,
no terminal required. They require Ollama running locally:

```bash
ollama pull qwen3:1.7b                 # one-time setup
dart test --run-skipped -t e2e         # run e2e tests
```

> **Note:** `qwen3:1.7b` is the expected Ollama model for the current e2e suite. Small models are non-deterministic —
> e2e tests use a retry wrapper (3 attempts).

## Tools

The agent has access to these tools:

| Tool                       | Description                                                                            |
|----------------------------|----------------------------------------------------------------------------------------|
| `read_file`                | Read file contents                                                                     |
| `write_file`               | Create or overwrite a file                                                             |
| `edit_file`                | Apply targeted find-and-replace edits                                                  |
| `bash`                     | Run shell commands (configurable timeout)                                              |
| `grep`                     | Search file contents with regex                                                        |
| `list_directory`           | List directory entries                                                                 |
| `spawn_subagent`           | Spawn a child agent for a subtask                                                      |
| `spawn_parallel_subagents` | Run multiple subagents concurrently                                                    |
| `web_fetch`                | Fetch URL content as markdown, handles PDFs with OCR fallback                          |
| `web_search`               | Search the web via Brave, Tavily, or Firecrawl backends                                |
| `web_browser`              | Browser automation via Chrome DevTools Protocol (screenshots, navigation, interaction) |
| `skill`                    | List or activate Agent Skills from agentskills.io-compatible definitions               |

## Architecture

```
Terminal (raw I/O, ANSI parsing, mouse/resize events)
  ├─ Layout (scroll regions, output/overlay/status/input zones)
  ├─ ScreenBuffer (virtual cells, diff-flush)
  └─ Input parsing (CSI sequences, Alt/Ctrl modifiers, SGR mouse)
LineEditor (readline-style input, history, word navigation)
App (event bus, state machine, render loop @ 60fps)
  ├─ AgentCore (LLM streaming, tool loop, parallel tool calls)
  │    ├─ Tools (read_file, write_file, edit_file, bash, grep, list_directory,
  │    │         web_fetch, web_search, web_browser, skill, subagents)
  │    └─ AgentManager (subagent lifecycle, depth-limited recursion)
  ├─ CommandExecutor (shell abstraction)
  │    ├─ HostExecutor (native shell: bash/zsh/fish/pwsh via ShellConfig)
  │    └─ DockerExecutor (ephemeral containers, cidfile tracking)
  ├─ Web (fetch, search, browser automation)
  │    ├─ Fetch (HTML-to-markdown, PDF text extraction, OCR fallback via Mistral/OpenAI)
  │    ├─ Search (Brave, Tavily, Firecrawl backends via SearchRouter)
  │    └─ Browser (CDP automation: local Chrome, Docker, Browserless, Browserbase, Steel, Anchor)
  ├─ Skills (agentskills.io-compatible skill loading)
  │    ├─ SkillRegistry (discover from ~/.glue/skills/ and .glue/skills/)
  │    └─ SkillParser (YAML frontmatter + markdown body)
  ├─ Observability (local-only spans)
  │    └─ Sink: FileSink (JSONL under ~/.glue/logs/)
  ├─ Rendering (BlockRenderer, MarkdownRenderer, ANSI utilities)
  ├─ Modals (inline confirm, full-screen panel with scrolling)
  └─ Overlays (slash autocomplete, @file hints)
```

The TUI and agent core run on separate async tracks — the UI is always responsive because input events and agent events
merge into a single render cycle via Dart streams.

## Keyboard shortcuts

| Shortcut              | Action                                   |
|-----------------------|------------------------------------------|
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
