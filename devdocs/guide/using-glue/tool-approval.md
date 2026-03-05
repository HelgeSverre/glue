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

## Permission Modes

Glue has four permission modes that control how tool calls are approved. Cycle through them with `Shift+Tab` during a session, or set a default via the `GLUE_PERMISSION_MODE` environment variable.

| Mode                | Label        | Behavior                                                    |
| ------------------- | ------------ | ----------------------------------------------------------- |
| `confirm`           | confirm      | Ask for confirmation on untrusted tools (default)           |
| `acceptEdits`       | accept-edits | Auto-approve file edits, still ask for shell commands       |
| `ignorePermissions` | YOLO         | Auto-approve everything — no confirmations at all           |
| `readOnly`          | read-only    | Deny all mutating tools — they are not even sent to the LLM |

::: warning
The `ignorePermissions` mode disables all safety checks. The agent can run arbitrary shell commands, overwrite files, and make network requests without any confirmation. Only use this mode in disposable environments or when you fully trust the task.
:::

## See also

- [PermissionMode](/api/config/permission-mode)
