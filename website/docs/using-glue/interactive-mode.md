# Interactive Mode

Glue runs as an interactive REPL. Type messages, use slash commands, or enter bash mode. The agent streams responses in real-time and can call tools in parallel.

## Slash Commands

| Command     | Description                                                              |
| ----------- | ------------------------------------------------------------------------ |
| `/approve`  | Toggle approval mode (confirm ↔ auto)                                    |
| `/clear`    | Clear conversation history                                               |
| `/config`   | Open config.yaml in `$EDITOR`, or initialize it with `/config init`      |
| `/copy`     | Copy the last assistant response to the clipboard                        |
| `/debug`    | Toggle debug mode (verbose logging)                                      |
| `/exit`     | Exit Glue                                                                |
| `/help`     | Show available commands and keybindings                                  |
| `/history`  | Browse history or fork by index/query                                    |
| `/mcp`      | Inspect MCP servers                                                      |
| `/model`    | Switch model (no args = picker, with arg = switch directly)              |
| `/open`     | Open a Glue directory in your file manager                               |
| `/paths`    | Show Glue data paths (config, sessions, logs, skills, plans, cache)      |
| `/provider` | Manage providers (list, add, remove, test)                               |
| `/recap`    | Summarize the current session in one line                                |
| `/rename`   | Rename the current session                                               |
| `/resume`   | Resume a session (panel or by ID/query)                                  |
| `/runtime`  | Show the active execution runtime                                        |
| `/session`  | Show current session info, or `/session copy` to copy ID                 |
| `/share`    | Export the current session as html, markdown, or gist                    |
| `/skills`   | Browse skills or activate one by name                                    |
| `/tools`    | List available tools                                                     |
| `/usage`    | Show token usage for this session (per role: main, subagent, title)      |

## Keybindings

| Key                   | Action                                    |
| --------------------- | ----------------------------------------- |
| `Ctrl+A`              | Move to start of line                     |
| `Ctrl+E`              | Move to end of line                       |
| `Ctrl+U`              | Clear entire line                         |
| `Ctrl+W`              | Delete previous word                      |
| `Alt+Left`            | Move cursor one word left                 |
| `Alt+Right`           | Move cursor one word right                |
| `Up` / `Down`         | Navigate input history                    |
| `Tab`                 | Accept autocomplete suggestion            |
| `PageUp` / `PageDown` | Scroll output                             |
| `Shift+Tab`           | Toggle approval mode (`confirm` ↔ `auto`) |
| `Escape`              | Cancel current generation                 |
| `Ctrl+C`              | Cancel generation (double-tap to exit)    |

## See also

- [SlashCommands](/api/commands/slash-commands)
- [LineEditor](/api/input/line-editor)
