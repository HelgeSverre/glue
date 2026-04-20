---
id: TASK-40
title: getglue.dev website redesign
status: To Do
assignee: []
created_date: '2026-04-20 00:08'
labels:
  - website
  - marketing
  - docs
milestone: m-0
dependencies: []
references:
  - website/
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make getglue.dev explain Glue quickly to technical users: what it is, why it exists, how to install, how it differs from IDE assistants and heavier agent stacks, and how the moving parts (models, providers, runtimes, web tools, Docker, sessions) fit together.

**Per the plan (`docs/plans/2026-04-19-website-redesign-plan.md`):** consolidate around VitePress (homepage + docs) with custom Vue pages for the marketing surface. Move to Astro only if the site grows into a much larger visual system.

**Coordinates with:**
- The docs site source-of-truth task (sibling task) — content sourcing rules ship together.
- The recommended-models JSON emission already in main (`89d3fc9 feat(website): emit recommended-models JSON; dedup marketing page`) — first move toward the source-of-truth model.

See plan for full information architecture and page-by-page structure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VitePress structure adopted: custom homepage + docs under one tree.
- [ ] #2 Information architecture from plan implemented: install, architecture, runtimes, models, providers, web tools, Docker, sessions, replay.
- [ ] #3 Marketing pages render from source-of-truth files where applicable (no hand-copied catalog tables).
- [ ] #4 Old `website/` static pages either migrated or redirected.
- [ ] #5 Production deploy (getglue.dev) reflects the new structure.
<!-- AC:END -->
