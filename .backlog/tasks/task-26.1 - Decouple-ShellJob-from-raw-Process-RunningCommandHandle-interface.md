---
id: TASK-26.1
title: Decouple ShellJob from raw Process (RunningCommandHandle interface)
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - runtime-boundary-2026-04
  - refactor
dependencies: []
references:
  - cli/lib/src/shell/shell_job_manager.dart
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
parent_task_id: TASK-26
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ShellJob` currently stores a `Process` directly. That makes remote command handles awkward — remote runtimes don't produce local `Process` objects.

**Introduce:**
```dart
abstract class RunningCommandHandle {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  Future<void> kill();
}
```

**Refactor:**
- `ShellJob` stores `RunningCommandHandle`, not `Process`
- Local/Docker commands wrap `Process` in a `ProcessCommandHandle` adapter
- Future remote runtimes implement `RunningCommandHandle` without a local `Process`

**Files:**
- Create: `cli/lib/src/shell/running_command_handle.dart` — interface + `ProcessCommandHandle` adapter
- Modify: `cli/lib/src/shell/shell_job_manager.dart` — store handle, not Process
- Modify: `cli/lib/src/shell/host_executor.dart` + `docker_executor.dart` — return handles
- Tests: `test/shell/shell_job_manager_test.dart` — kill calls handle's `kill()`, not raw Process

**Explicit non-goal:** do NOT build the full `ExecutionRuntime` interface yet. Just replace the `Process` field with the handle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `RunningCommandHandle` interface exists with stdout/stderr/exitCode/kill
- [ ] #2 `ProcessCommandHandle` adapter wraps `dart:io` Process for host/Docker
- [ ] #3 `ShellJob` stores the handle, not a raw Process
- [ ] #4 Background job kill calls `handle.kill()`, not `process.kill()`
- [ ] #5 Host and Docker behavior unchanged (no user-visible regression)
- [ ] #6 Tests verify handle lifecycle
<!-- AC:END -->
