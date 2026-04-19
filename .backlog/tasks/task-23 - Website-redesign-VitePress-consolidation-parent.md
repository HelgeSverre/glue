---
id: TASK-23
title: 'Website redesign: VitePress consolidation (parent)'
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
labels:
  - website-2026-04
  - parent
  - docs
dependencies: []
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repo currently has `website/` (static) and `devdocs/` (VitePress). Consolidate into a single VitePress shell for both marketing + docs. Avoid Astro until the visual system outgrows VitePress.

**Canonical source rules (per docs-site-source-of-truth plan):**
- Models: `cli/docs/reference/models.yaml` is canonical — website derives provider list + model tables, no hardcoded duplicates
- Config: `cli/docs/reference/config-yaml.md` — website snippets copied from tested examples
- Session logs: `cli/docs/reference/session-storage.md` + JSONL schema doc
- TUI: `cli/bin/glue_theme_demo.dart` + TUI behavior contract — prefer generated renders
- Install commands: single snippet (`docs/snippets/install.md`) included everywhere

**Sitemap:** `/`, `/why`, `/features`, `/models`, `/runtimes`, `/web`, `/sessions`, `/roadmap`, `/changelog`, `/brand`

**Docs reorg:** `/docs/{getting-started,using-glue,advanced,contributing}/*`

**Feature status labels** (per source-of-truth plan): `shipping` / `experimental` / `planned` — do NOT put planned features in the hero as if shipping.

**Subtasks:** W1–W10 (VitePress shell, marketing pages, product pages, /web+/sessions, roadmap/changelog/brand, Vue components, docs reorganization, archive old site, docs generation script, feature status labels+components).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Single VitePress build serves both marketing (`/`) and docs (`/docs/*`)
- [ ] #2 Every sitemap page exists (placeholder OK for first pass)
- [ ] #3 Docs reorganized per new structure
- [ ] #4 Old `website/` archived (moved to `_archived/` or deleted)
- [ ] #5 `justfile` has one build/deploy recipe for the unified site
- [ ] #6 Models page derives from `cli/docs/reference/models.yaml` (no hardcoded table)
- [ ] #7 Feature status labels present on roadmap + feature pages
<!-- AC:END -->
