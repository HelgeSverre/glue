---
id: TASK-26.2
title: Document and normalize workspace path mapping
status: To Do
assignee: []
created_date: "2026-04-19 00:42"
updated_date: "2026-04-20 00:05"
labels:
  - runtime-boundary-2026-04
  - docs
milestone: m-2
dependencies: []
references:
  - cli/lib/src/shell/docker_config.dart
  - cli/lib/src/shell/docker_executor.dart
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
parent_task_id: TASK-26
priority: medium
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Today Docker mounts cwd at `/workspace` (universal convention shared with cloud runtimes). The path mapping is implicit in `DockerExecutor`. Write it down so remote runtimes can reuse the same model.

**Document (in code + docs):**

- Host cwd → runtime cwd mapping (Docker: `$PWD → /workspace`)
- Path translation rules (absolute paths outside cwd: reject? mount separately? error?)
- Writable vs read-only mounts
- Artifact output directory (where tools write artifacts — see SE4)
- Additional configurable mounts (`docker.mounts: ["/host:/container:ro"]`)

**Files:**

- Modify: `cli/docs/design/docker-sandbox.md` — add "Workspace path mapping" section
- Modify: `cli/docs/reference/config-yaml.md` — document `docker.mounts`
- Create: `cli/lib/src/shell/workspace_mapping.dart` — `WorkspaceMapping` type holding host cwd + runtime cwd + translation helpers
- Use `WorkspaceMapping` from `DockerExecutor`
- Tests: path translation for absolute paths inside/outside cwd, relative paths, symlinks

**Why now:** future remote runtimes (E2B, Modal) will do the same mapping. Writing it down once prevents three implementations diverging later.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 `WorkspaceMapping` type exists + used by `DockerExecutor`
- [ ] #2 Path translation rules documented (inside cwd, outside cwd, symlinks)
- [ ] #3 Configurable additional mounts (`docker.mounts`) documented
- [ ] #4 Artifact output directory documented
- [ ] #5 Docker sandbox docs accurately describe isolation limits (not implying malware-safe)
- [ ] #6 Tests cover path translation edge cases
<!-- AC:END -->
