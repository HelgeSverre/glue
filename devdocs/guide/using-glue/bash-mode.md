# Bash Mode

Prefix your input with `!` to run shell commands directly, bypassing the LLM. The prompt changes to `! ` to indicate bash mode. Press `Backspace` on an empty line to exit back to normal mode.

## Synchronous Commands

```bash
! git status
! dart test
! ls -la src/
```

## Background Jobs

Prefix with `& ` (ampersand + space) to run commands in the background. The shell returns immediately and you can keep chatting.

```bash
! & dart compile exe bin/main.dart

# Job lifecycle events are printed as they happen:
[job 1] started: dart compile exe bin/main.dart
[job 1] exited (0)
```

## Limits

| Limit                       | Default                                      |
| --------------------------- | -------------------------------------------- |
| Synchronous command timeout | 30 seconds (configurable)                    |
| Output line cap             | 50 lines (`bash.max_lines` in config)        |
| Background job timeout      | None -- runs until completion or manual kill |

::: tip
Use background jobs for long-running tasks like compilation or test suites so you can continue chatting while they run.
:::

## See also

- [HostExecutor](/api/shell/host-executor)
- [ShellJobManager](/api/shell/shell-job-manager)
- [ShellConfig](/api/shell/shell-config)
