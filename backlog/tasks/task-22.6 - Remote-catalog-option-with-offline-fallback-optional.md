---
id: TASK-22.6
title: Remote catalog option with offline fallback (optional)
status: Done
assignee: []
created_date: '2026-04-19 00:36'
updated_date: '2026-04-19 04:02'
labels:
  - model-provider-2026-04
  - optional
dependencies:
  - TASK-22.1
documentation:
  - cli/docs/plans/2026-04-19-model-provider-config-redesign.md
parent_task_id: TASK-22
priority: low
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Allow a hosted catalog source so bundled entries can be updated without a Glue release.

**This task is OPTIONAL** — MP1–MP6 ship without it. Only implement if/when remote catalog is actually needed.

**Catalog config section:**
```yaml
catalog:
  source: remote
  remote_url: https://raw.githubusercontent.com/helgesverre/glue/main/catalog/models.yaml
  refresh: never | manual | daily
  cache_path: ~/.glue/cache/models.yaml
  fallback: bundled
```

**Merge order:** bundled → cached remote → `~/.glue/models.yaml` (user overrides) → project-local overrides (future).

**Files:**
- Modify: `cli/lib/src/config/catalog/` from MP1 — add remote fetch with cache
- Create: `cli/lib/src/config/catalog/remote_fetcher.dart` — HTTP fetch with short timeout

**Hard rules:**
- Startup ALWAYS works offline — remote fetch never blocks the app
- Short timeout; failed refresh silently falls back to cached/bundled (unless `--debug`)
- Remote catalog CANNOT inject credentials — strip `auth` / `api_key` fields during ingest
- User `~/.glue/models.yaml` overrides all remote entries

**Depends on:** MP1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Startup always works offline — remote fetch never blocks
- [ ] #2 Failed refresh silently falls back to cached/bundled (unless `--debug`)
- [ ] #3 Remote catalog cannot inject credentials (fields stripped on ingest — tested with malicious payload)
- [ ] #4 User `~/.glue/models.yaml` overrides all remote entries
- [ ] #5 Merge order tested: bundled → cached_remote → local_overrides
- [ ] #6 Tests cover offline startup, stale cache, remote credential-injection attempt
<!-- AC:END -->
