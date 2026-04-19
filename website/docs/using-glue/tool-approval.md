# Tool Approval

Tools that modify your codebase (`write_file`, `edit_file`, `bash`) require explicit approval. Read-only tools are auto-approved.

## Approval Modal

When a destructive tool is called, Glue shows a confirmation modal with three options:

- **Yes** — approve this specific call
- **No** — deny this call; the agent gets an error and can try something else
- **Always** — permanently trust this tool (saved to `~/.glue/preferences.json`)

::: info Note
You can configure permanent tool trust in `~/.glue/preferences.json`. Use with caution — the agent can run arbitrary shell commands.
:::

## Approval Modes

Glue has two approval modes:

| Mode      | Behavior                                                       |
| --------- | -------------------------------------------------------------- |
| `confirm` | Ask for confirmation on untrusted tools (default)              |
| `auto`    | Auto-approve everything — no confirmations at all              |

Toggle between them at runtime with `Shift+Tab` or the `/approve` slash command. Set the default via config or env var:

```yaml
# ~/.glue/config.yaml
approval_mode: confirm   # confirm | auto
```

```bash
export GLUE_APPROVAL_MODE=auto
```

::: warning
`auto` mode disables all confirmation prompts. The agent can run arbitrary shell commands, overwrite files, and make network requests without prompting. Only use it in disposable environments or when you fully trust the task.
:::
