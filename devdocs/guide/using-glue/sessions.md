# Sessions & Resume

Every conversation is automatically saved. You can resume any past session without losing context.

## Storage

Sessions are stored in `~/.glue/sessions/{timestamp}-{id}/` with two files:

| File                 | Contents                                                        |
| -------------------- | --------------------------------------------------------------- |
| `meta.json`          | Session ID, working directory, model, provider, start/end times |
| `conversation.jsonl` | Line-delimited event log (messages, tool calls, results)        |

## Resuming a Session

| Method            | Description                          |
| ----------------- | ------------------------------------ |
| `glue --resume`   | Open interactive session picker      |
| `glue --continue` | Auto-resume the most recent session  |
| `/resume`         | Open session picker during a session |

::: tip
Use `glue --continue` to pick up exactly where you left off. This is useful when you need to restart your terminal or switch machines.
:::

## See also

- [SessionStore](/api/storage/session-store)
- [SessionState](/api/storage/session-state)
- [SessionId](/api/storage/session-id)
