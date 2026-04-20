---
id: TASK-26.5
title: Runtime capability table (docs + data for website)
status: To Do
assignee: []
created_date: "2026-04-19 00:42"
updated_date: "2026-04-20 00:05"
labels:
  - runtime-boundary-2026-04
  - docs
milestone: m-2
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
parent_task_id: TASK-26
priority: low
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Expose a structured capability table for each runtime. The UI and tools should use capability checks rather than runtime-name checks.

**Capabilities to surface:**

```yaml
capabilities:
  command_capture: true
  command_streaming: true
  background_jobs: true
  filesystem_read: true
  filesystem_write: true
  mount_host_paths: true
  browser_cdp: true
  artifacts: true
  secrets: true
  snapshots: false
  internet: true
  gpu: false
```

**Files:**

- Create: `cli/lib/src/shell/runtime_capabilities.dart` — enum + data class
- Add capability data for `host` and `docker` runtimes
- Create: `cli/docs/reference/runtimes.md` — the capability table as a markdown doc
- Website `/runtimes` (W3) + `RuntimeMatrix.vue` (W6) — consume from this doc

**Security and isolation documentation (per plan):** for each runtime, document network access, host mounts, secret injection, cleanup on cancel, artifact retention, max runtime duration, max output size, whether untrusted files can be opened. Docker is NOT a complete sandbox — say so explicitly.

**Depends on:** W3 (runtimes page), W6 (RuntimeMatrix component).

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 `RuntimeCapabilities` data class exists with all capabilities from plan
- [ ] #2 Host + Docker capability data populated
- [ ] #3 `cli/docs/reference/runtimes.md` documents the table
- [ ] #4 Security/isolation section per runtime: network, mounts, secrets, cleanup, retention, duration, output-size limits
- [ ] #5 Docker isolation described honestly (not implying malware-safe)
- [ ] #6 Website `/runtimes` page (W3) renders from this data via `RuntimeMatrix.vue`
<!-- AC:END -->
