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

Glue is a terminal-native coding agent CLI built in Dart. It streams LLM responses, executes tools (file read/write, shell commands, grep), and renders everything in a responsive TUI that never blocks.

## Run

```bash
dart run bin/glue.dart
```

```bash
dart run bin/glue.dart --help
dart run bin/glue.dart --model claude-sonnet-4-20250514
```

## Architecture

```
Terminal (raw I/O, ANSI)
  └─ Layout (scroll regions, zones)
       └─ ScreenBuffer (virtual cells, diff-flush)
  └─ LineEditor (readline-style input)
App (event bus, state machine, render loop)
  └─ AgentCore (LLM streaming, tool loop)
       └─ Tools (read_file, write_file, bash, grep, list_directory)
```

The TUI and agent core run on separate async tracks — the UI is always responsive because input events and agent events merge into a single render cycle via Dart streams.

## Brand

- Amber/gold: `#F5A623` — primary accent
- Deep charcoal: `#1A1A2E` — background
- Warm white: `#F0E6D3` — text
