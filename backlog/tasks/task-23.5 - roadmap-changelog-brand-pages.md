---
id: TASK-23.5
title: /roadmap + /changelog + /brand pages
status: To Do
assignee: []
created_date: '2026-04-19 00:38'
labels:
  - website-2026-04
  - content
dependencies:
  - TASK-23.1
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
parent_task_id: TASK-23
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Files:** `roadmap.md`, `changelog.md`, `brand.md`

**/roadmap sections (per plan):**
- **Now:** simplify config, remove plan mode, improve TUI reference behavior
- **Next:** model catalog refresh, Docker runtime polish, web extraction flows
- **Later:** cloud runtimes, replay UI, provider marketplace/catalog
- Do NOT include dates unless a real release plan exists

**/changelog:** generated from `cli/CHANGELOG.md` or manually curated (decide during implementation).

**/brand:** logos, colors, screenshots, naming guidance.

**Depends on:** W1. Coordinate with W10 (feature status labels) so roadmap labels are consistent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Three pages exist
- [ ] #2 Roadmap uses `shipping`/`experimental`/`planned` labels (from W10)
- [ ] #3 No dates in roadmap unless a real release plan exists
- [ ] #4 Changelog format decided + documented
- [ ] #5 Brand page covers logos, colors, screenshots, naming
<!-- AC:END -->
