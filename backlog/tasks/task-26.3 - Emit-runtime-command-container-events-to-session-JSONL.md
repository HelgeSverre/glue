---
id: TASK-26.3
title: Emit runtime command/container events to session JSONL
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - runtime-boundary-2026-04
  - observability
dependencies:
  - TASK-24.1
  - TASK-24.3
  - TASK-26.1
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-26
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wire runtime command/container lifecycle into the session JSONL event stream (SE schema).

**Events to emit** (names defined by SE1):
- `runtime.command.started` — with `runtime_id`, `cwd`, `command`, `args`
- `runtime.command.output` — streaming stdout/stderr chunks (large output → artifact per SE4)
- `runtime.command.completed` — with `exit_code`, `duration_ms`
- `runtime.command.failed` — with error reason
- `runtime.command.cancelled` — when user aborts
- `runtime.container.started` — Docker container start, with `image`, `container_id`
- `runtime.container.stopped` — with duration, cleanup reason

**Files:**
- Modify: `cli/lib/src/shell/shell_job_manager.dart` — emit command events via the session event sink
- Modify: `cli/lib/src/shell/host_executor.dart` + `docker_executor.dart` — emit container events (Docker only)
- Integration: events routed through the session event sink from SE2

**Depends on:** SE1 (event types), SE3 (full coverage), RB1 (handle abstraction so remote runtimes can emit the same events).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Host shell runs emit `runtime.command.{started,output,completed,failed,cancelled}` events
- [ ] #2 Docker runs additionally emit `runtime.container.{started,stopped}` events
- [ ] #3 Command events include `runtime_id` and cwd mapping (via RB2)
- [ ] #4 Long command output goes to artifact (via SE4), referenced from the command.output event
- [ ] #5 Cancellation via `handle.kill()` (RB1) emits `runtime.command.cancelled`
- [ ] #6 Tests cover each event type for both host and Docker
<!-- AC:END -->
