# Interactive Mode

Glue runs as an interactive REPL. Type messages, use slash commands, or enter bash mode. The agent streams responses in real-time and can call tools in parallel.

## Slash Commands

| Command    | Aliases       | Description                                                 |
| ---------- | ------------- | ----------------------------------------------------------- |
| `/help`    |               | Show all commands and keybindings                           |
| `/clear`   |               | Clear conversation history                                  |
| `/exit`    | `/quit`, `/q` | Exit the application                                        |
| `/model`   |               | Open the model picker, or fuzzy-switch by name (`/model X`) |
| `/models`  |               | Browse and switch models across all providers               |
| `/info`    | `/status`     | Show session info (model, tokens, cwd)                      |
| `/tools`   |               | List all available tools                                    |
| `/history` |               | Browse history; fork by index or query (`/history <q>`)     |
| `/resume`  |               | Open the session picker, or resume by ID/query              |
| `/debug`   |               | Toggle debug mode (verbose logging to `~/.glue/logs/`)      |
| `/skills`  |               | Browse skills, or activate one by name (`/skills <name>`)   |
| `/approve` |               | Toggle approval mode (`confirm` ↔ `auto`)                   |

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
