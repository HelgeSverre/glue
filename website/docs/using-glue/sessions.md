# Sessions & Resume

Every conversation is automatically saved. You can resume any past session without losing context.

## Storage

Sessions are stored in `~/.glue/sessions/{timestamp}-{id}/` with these files:

| File                     | Contents                                                                                |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `meta.json`              | Session ID, working directory, model, provider, start/end times                         |
| `conversation.jsonl`     | Line-delimited event log (messages, tool calls, results)                                |
| `state.json`             | Mutable per-session state (e.g. Docker mounts in use)                                   |
| `runtime.mbox`           | Cloud-runtime only: agent's workspace changes as a `git format-patch` mbox              |
| `runtime.mbox.meta.json` | Cloud-runtime only: sidecar with runtime ID, sandbox ID, bootstrap SHA, capture metadata |

For cloud runtimes (Daytona, Sprites, Modal), the `runtime.mbox` is written
at session shutdown and can be applied back to your host workspace. See
[Session Patches](/docs/using-glue/session-patches) for the full workflow.

## Resuming a Session

`--resume` (or `-r`) is a flag — when given a positional value, Glue
normalizes it to an internal `--resume-id=<id>`. The forms below all work:

| Method                                    | Description                                  |
| ----------------------------------------- | -------------------------------------------- |
| `glue --resume`                           | Open the session picker at startup           |
| `glue -r`                                 | Same, short form                             |
| `glue --resume <session-id>`              | Resume a specific session by its ID          |
| `glue --resume <session-id> "new prompt"` | Resume a session and immediately send prompt |
| `glue --continue`                         | Auto-resume the most recent session          |
| `/resume`                                 | Open the session picker during a session     |
| `/resume <id-or-query>`                   | Resume by ID or fuzzy query during a session |

::: tip
Use `glue --continue` to pick up exactly where you left off. This is useful when you need to restart your terminal or switch machines.
:::

## See also

- [SessionStore](/api/storage/session-store)
- [SessionState](/api/storage/session-state)
- [SessionManager](/api/session/session-manager)
