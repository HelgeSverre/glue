---
id: TASK-26
title: "Runtime boundary: prep for remote runtimes (parent)"
status: To Do
assignee: []
created_date: "2026-04-19 00:34"
updated_date: "2026-04-20 00:05"
labels:
  - runtime-boundary-2026-04
  - parent
  - runtime
milestone: m-2
dependencies: []
references:
  - cli/lib/src/shell/command_executor.dart
  - cli/lib/src/shell/host_executor.dart
  - cli/lib/src/shell/docker_executor.dart
  - cli/lib/src/shell/shell_job_manager.dart
  - cli/lib/src/web/browser/browser_manager.dart
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Clarify the boundary between Glue and the place where work executes. Current runtimes: host shell, Docker shell, local/Docker browser backends, cloud browser providers. Future: E2B, Modal, Daytona, SSH workers.

**Explicit non-goal:** do NOT over-abstract prematurely. Keep existing host/Docker concrete. Only do the prep work that unblocks future remote runtime work; full `ExecutionRuntime` interface happens when a second non-Docker runtime ships.

**Prep work in scope:**

1. Decouple `ShellJob` from raw `Process` (introduce `RunningCommandHandle` interface)
2. Normalize workspace mapping (document Docker's `/workspace` mount + path translation rules)
3. Emit runtime command/container events to session JSONL (depends on SE parent)
4. Make browser endpoint acquisition runtime-aware without breaking existing providers
5. Add runtime capability table to docs and website

**Desired runtime ladder:** `host → Docker → remote container/runtime`. Each step answers: workspace location, command execution, file I/O, secrets, browser sessions, streaming, cancellation, artifact copy-back, cleanup.

**Capabilities to surface (for future capability-based UI):** `command_capture`, `command_streaming`, `background_jobs`, `filesystem_{read,write}`, `mount_host_paths`, `browser_cdp`, `artifacts`, `secrets`, `snapshots`, `internet`, `gpu`.

**Subtasks:** RB1–RB5.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Host and Docker behavior remain unchanged (no regression)
- [ ] #2 Background jobs no longer depend directly on `Process`
- [ ] #3 JSONL records where commands ran (via SE schema)
- [ ] #4 Docker sandbox docs accurately describe isolation limits (not implying full sandbox)
- [ ] #5 First remote runtime could be added without rewriting app/tool code
- [ ] #6 All RB1–RB5 subtasks complete
<!-- AC:END -->
