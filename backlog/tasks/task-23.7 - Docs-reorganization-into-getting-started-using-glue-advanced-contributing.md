---
id: TASK-23.7
title: >-
  Docs reorganization into getting-started / using-glue / advanced /
  contributing
status: To Do
assignee: []
created_date: '2026-04-19 00:38'
labels:
  - website-2026-04
  - docs
dependencies:
  - TASK-23.1
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Move existing `devdocs/guide/*.md` under four clear top-level sections and update sidebar config.

**Target docs structure:**
- `/docs/getting-started/{installation, quick-start, configuration}`
- `/docs/using-glue/{interactive-mode, models-and-providers, tools, sessions, file-references, worktrees, docker-sandbox}`
- `/docs/advanced/{runtimes, browser-automation, web-tools, mcp-integration, skills, subagents, troubleshooting}`
- `/docs/contributing/{development-setup, architecture, testing}`

**Files to modify:**
- Move existing `devdocs/guide/*.md` → `devdocs/docs/{getting-started,using-glue,advanced,contributing}/`
- Update sidebar config in `devdocs/.vitepress/config.ts`
- Fix internal links that break due to path changes
- Add stub pages for sitemap entries that don't yet exist (title + H1 + "coming soon")

**Depends on:** W1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All four sidebar sections present (getting-started, using-glue, advanced, contributing)
- [ ] #2 Every listed doc path has at least a stub with title + H1
- [ ] #3 No broken internal links (`vitepress build` succeeds)
- [ ] #4 Sidebar nav uses consistent labels
- [ ] #5 Redirects from old `/guide/*` paths if feasible (or release note)
<!-- AC:END -->
