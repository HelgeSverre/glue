# Interactive Mode

Glue runs as an interactive REPL. Type messages, use slash commands, or enter bash mode. The agent streams responses in real-time and can call tools in parallel.

## Slash Commands

| Command    | Aliases       | Description                                            |
| ---------- | ------------- | ------------------------------------------------------ |
| `/help`    |               | Show all commands and keybindings                      |
| `/clear`   |               | Clear conversation history                             |
| `/exit`    | `/quit`, `/q` | Exit the application                                   |
| `/model`   |               | Show or switch the current model                       |
| `/info`    | `/status`     | Show session metadata (model, tokens, cwd)             |
| `/tools`   |               | List all available tools                               |
| `/history` |               | Show input history (last 10 by default)                |
| `/resume`  |               | Open session picker to restore a conversation          |
| `/models`  |               | List available models from the current provider        |
| `/debug`   |               | Toggle debug mode (verbose logging to `~/.glue/logs/`) |
| `/skills`  |               | Browse available skills                                |

## Keybindings

| Key                   | Action                                                               |
| --------------------- | -------------------------------------------------------------------- |
| `Ctrl+A`              | Move to start of line                                                |
| `Ctrl+E`              | Move to end of line                                                  |
| `Ctrl+U`              | Clear entire line                                                    |
| `Ctrl+W`              | Delete previous word                                                 |
| `Alt+Left`            | Move cursor one word left                                            |
| `Alt+Right`           | Move cursor one word right                                           |
| `Up` / `Down`         | Navigate input history                                               |
| `Tab`                 | Accept autocomplete suggestion                                       |
| `PageUp` / `PageDown` | Scroll output                                                        |
| `Shift+Tab`           | Cycle permission mode (confirm -> accept-edits -> YOLO -> read-only) |
| `Escape`              | Cancel current generation                                            |
| `Ctrl+C`              | Cancel generation (double-tap to exit)                               |

## See also

- [SlashCommands](/api/commands/slash-commands)
- [LineEditor](/api/input/line-editor)
