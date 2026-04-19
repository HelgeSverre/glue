---
id: TASK-23.3
title: /models + /runtimes pages (strategic priority)
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
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Plan explicitly calls out adding `/models` and `/runtimes` **before broader polish** because these pages clarify product strategy.

**Files to create:** `models.md`, `runtimes.md`

**/models content:**
- Selected model = `provider/model` (e.g., `anthropic/claude-sonnet-4.6`, `groq/qwen/qwen3-coder`)
- Providers declare `adapter` (wire protocol) + `compatibility` (quirks profile)
- `adapter: openai` handles OpenAI-compatible APIs
- Credentials via env or `~/.glue/credentials.json` (0600 permissions)
- Bundled catalog updatable later (remote catalog optional)
- Compact YAML example (8–12 lines)
- Link to `/docs/using-glue/models-and-providers`
- **Must derive from `cli/docs/reference/models.yaml`** — use `ModelTable.vue` (W6) rather than hardcoded table

**/runtimes content:**
- Ladder: `host → Docker → cloud`
- Current Docker sandbox is concrete shipping thing — accurate isolation description (not implying full sandbox)
- Cloud runtimes (E2B / Modal / Daytona / SSH workers) labeled `planned` (see W10 status labels)
- Capability table (future) via `RuntimeMatrix.vue`

**Cross-reference alignment:**
- `/models` must stay consistent with Model/Provider Redesign (task-22 / MP) — link to those docs
- `/runtimes` must stay consistent with Runtime Boundary (task-26 / RB)

**Depends on:** W1 (shell), W6 (ModelTable component), W10 (feature status labels).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both pages exist with concrete content (not placeholders)
- [ ] #2 `/models` page includes compact YAML example
- [ ] #3 `/models` table is derived from `cli/docs/reference/models.yaml` via W6 component (no hardcoded duplicate)
- [ ] #4 `/runtimes` clearly marks cloud as `planned`, host + Docker as present
- [ ] #5 Docker isolation limits accurately described (not implying malware-safe sandbox)
- [ ] #6 Cross-links to `/docs/using-glue/models-and-providers` and Docker sandbox docs
<!-- AC:END -->
