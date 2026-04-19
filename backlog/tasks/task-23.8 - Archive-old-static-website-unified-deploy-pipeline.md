---
id: TASK-23.8
title: Archive old static website/ + unified deploy pipeline
status: To Do
assignee: []
created_date: '2026-04-19 00:39'
labels:
  - website-2026-04
  - infra
dependencies:
  - TASK-23.1
  - TASK-23.2
  - TASK-23.3
  - TASK-23.4
  - TASK-23.5
  - TASK-23.7
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
parent_task_id: TASK-23
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Once all routes are covered by the unified VitePress site, archive the static `website/` directory and consolidate the deploy pipeline.

**Files:**
- Move `website/` content (the bits not migrated) to `website/_archived/` OR delete entirely
- Update deploy scripts / GitHub Actions to build from the unified VitePress project (likely `devdocs/` or renamed `site/`)
- Update root `CLAUDE.md` + `README.md` with new site location
- Audit `website/` for favicons, images, meta tags, OG images — migrate to VitePress before archiving

**Depends on:** W1–W7 (all content must be migrated first).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `website/` no longer contains live pages (archived or deleted)
- [ ] #2 Single deploy pipeline produces `getglue.dev`
- [ ] #3 Deploy validated on staging URL or local preview
- [ ] #4 Root `CLAUDE.md` + `README.md` updated with new location
- [ ] #5 Favicons, images, meta tags, OG images preserved in VitePress
- [ ] #6 CI workflow updated if relevant
<!-- AC:END -->
