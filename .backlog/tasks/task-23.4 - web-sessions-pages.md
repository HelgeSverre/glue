---
id: TASK-23.4
title: /web + /sessions pages
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
**Files:** `web.md`, `sessions.md`

**/web content:** Target use cases — research, scraping, data extraction, browser automation, static-site inspection, suspicious-artifact isolation. Explicitly avoid promising stealth, bypassing, or abusive automation.

**/sessions content (aligned with R4 + M1 + SE):**
- Where sessions live (`~/.glue/sessions/<id>/`)
- How resume works
- JSONL base format (schema documented via SE parent task)
- How tool calls, outputs, errors, agent messages appear in logs
- Replay UI as future (marked `planned`)
- Messaging: "JSONL sessions beat mandatory telemetry for local-first debugging" — align with removal of OTel (task-11)

**Depends on:** W1. Content consistency with SE parent (task-24) schema docs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both pages exist with concrete content
- [ ] #2 `/web` lists use cases without stealth/bypass claims
- [ ] #3 `/sessions` accurately describes JSONL-first approach
- [ ] #4 `/sessions` cross-links to session schema docs (from SE parent)
- [ ] #5 Replay UI labeled `planned`
<!-- AC:END -->
