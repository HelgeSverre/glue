---
id: TASK-23.1
title: VitePress shell + config unification
status: To Do
assignee: []
created_date: '2026-04-19 00:38'
labels:
  - website-2026-04
  - infra
dependencies: []
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decide file layout, theme, nav, sidebar, search, and deploy once. Foundation for every other W subtask.

**Files to inspect/modify:**
- `devdocs/` — current VitePress structure, theme, config
- `website/` — static content to migrate
- `devdocs/.vitepress/config.ts` — extend for marketing routes
- Theme override for marketing layout (full-width hero, room for terminal demo component)

**Decide:** keep serving `getglue.dev` from `devdocs/` dist, or rename `devdocs/` → `site/`. Document the choice.

**Nav/sidebar separation:** marketing pages live in top nav; docs live in left sidebar. One VitePress site, two navigational surfaces.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One VitePress project serves both `/` (marketing) and `/docs/*` (docs)
- [ ] #2 Nav (top) clearly separated from sidebar (docs)
- [ ] #3 Marketing layout supports full-width hero (no split-column)
- [ ] #4 Build command documented in `justfile` and top-level `README.md`
- [ ] #5 `vitepress dev` renders without errors
- [ ] #6 Path decision (devdocs vs site) documented
<!-- AC:END -->
