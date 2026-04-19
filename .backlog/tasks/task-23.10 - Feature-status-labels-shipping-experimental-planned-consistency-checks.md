---
id: TASK-23.10
title: Feature status labels (shipping/experimental/planned) + consistency checks
status: To Do
assignee: []
created_date: '2026-04-19 00:39'
labels:
  - website-2026-04
  - content-quality
dependencies:
  - TASK-23.6
documentation:
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Keep website honest about what actually ships today. Introduce three canonical status labels and automated checks.

**Labels:** `shipping` / `experimental` / `planned`

**Where to apply:**
- Roadmap page (W5)
- Features page (W2)
- Product pages (/models, /runtimes, /web, /sessions)
- Any "comparison" or "capability" table

**Example mappings (decide per feature during implementation):**
- Docker shell runtime → `shipping` or `experimental` depending on stability
- Cloud runtimes → `planned`
- JSONL sessions → `shipping` (with schema expansion `planned`)
- Model catalog refresh → `planned`
- Web/browser tooling → `shipping` or `experimental` by backend
- ACP web UI → `planned`

**Consistency checks (add as CI step or pre-deploy script):**
- Every model shown on `/models` exists in `cli/docs/reference/models.yaml`
- Every provider shown on `/models` exists in `models.yaml`
- Every JSONL event example shown anywhere exists in the session schema doc
- Generated docs are up to date (rerun of generator produces no diff)
- Planned features are NOT marked as shipping (grep for known feature names + status)

**Hard rule (from docs-site-source-of-truth plan):** Do NOT put planned features in the hero as if they are complete.

**Depends on:** W6 (`FeatureStatus.vue` component).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Three label classes defined + rendered by `FeatureStatus.vue`
- [ ] #2 Roadmap + feature pages + product pages use labels consistently
- [ ] #3 Consistency check script exists (in `tool/` or CI workflow)
- [ ] #4 Check: every model/provider on /models exists in `models.yaml`
- [ ] #5 Check: generated docs are up to date
- [ ] #6 Check: no planned features labeled shipping
- [ ] #7 Hero copy does not imply planned features are shipping
<!-- AC:END -->
