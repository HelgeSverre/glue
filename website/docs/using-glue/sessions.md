# Sessions & Resume

Every conversation is automatically saved. You can resume any past session without losing context.

## Storage

Sessions are stored in `~/.glue/sessions/{timestamp}-{id}/` with three files:

| File                 | Contents                                                        |
| -------------------- | --------------------------------------------------------------- |
| `meta.json`          | Session ID, working directory, model, provider, start/end times |
| `conversation.jsonl` | Line-delimited event log (messages, tool calls, results)        |
| `state.json`         | Mutable per-session state (e.g. Docker mounts in use)           |

## Resuming a Session

| Method                        | Description                                  |
| ----------------------------- | -------------------------------------------- |
| `glue --resume <session-id>`  | Resume a specific session by its ID          |
| `glue --continue`             | Auto-resume the most recent session          |
| `/resume`                     | Open the session picker during a session     |
| `/resume <id-or-query>`       | Resume by ID or fuzzy query during a session |

::: tip
Use `glue --continue` to pick up exactly where you left off. This is useful when you need to restart your terminal or switch machines.
:::

## See also

- [SessionStore](/api/storage/session-store)
- [SessionState](/api/storage/session-state)
- [SessionManager](/api/session/session-manager)
