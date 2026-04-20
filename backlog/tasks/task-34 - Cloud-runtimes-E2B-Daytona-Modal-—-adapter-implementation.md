---
id: TASK-34
title: Cloud runtimes (E2B / Daytona / Modal) — adapter implementation
status: To Do
assignee: []
created_date: "2026-04-20 00:08"
updated_date: "2026-04-20 00:32"
labels:
  - runtime
  - cloud
  - deferred
milestone: m-4
dependencies:
  - TASK-26
references:
  - cli/lib/src/shell/command_executor.dart
documentation:
  - docs/plans/2026-04-19-cloud-runtimes-plan.md
  - docs/plans/2026-04-19-runtime-boundary-plan.md
priority: low
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Implement at least one remote cloud sandbox runtime adapter (E2B, Daytona, Modal, Fly.io Sprites, Bunnyshell/hopx, or Northflank) so Glue can execute work outside the user's host and Docker.

**Status: deferred.** The plan (`docs/plans/2026-04-19-cloud-runtimes-plan.md`) marks itself `proposed — deferred`. Research is complete; workspace sync (Option D — git-first + persistence opt-in) and `/workspace` universal path are decided. Implementation is gated on:

- TASK-26 (runtime boundary prep, subtasks 26.1–26.5) landing first — `RunningCommandHandle` + JSONL runtime events make adapter work substantially cheaper.
- A real workload demanding a cloud runtime (GPU, untrusted code, long-running parallel agents).
- Daytona or E2B shipping a Dart SDK — would collapse the biggest single cost driver for either adapter.

Living in **Deferred** milestone so it's discoverable without polluting the active backlog. Promote out of Deferred when at least one of the gating conditions changes.

Plan reference: `docs/plans/2026-04-19-cloud-runtimes-plan.md` (full research + open questions + Option D rationale).

<!-- SECTION:DESCRIPTION:END -->
