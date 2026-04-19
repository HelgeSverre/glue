---
id: TASK-23.2
title: Home + /why + /features pages
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
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Files to create** under VitePress pages:
- `index.md` (home)
- `why.md`
- `features.md`

**Home content (per plan):**
- Headline: "A small terminal agent for real coding work."
- Subhead: "Glue edits files, runs tools, keeps resumable sessions, and can run work locally, in Docker, or later on remote runtimes."
- Primary CTA: install command; secondary: docs link
- Full-width terminal demo (NOT split column)
- "Core Loop" section: Ask → inspect → edit → run → verify → summarize
- Sections: "Run work where it belongs", "Bring your models", "Web and research", "Sessions", final CTA

**/why content:** terminal-native rationale, small surface area beats giant mode system, Docker/cloud for risky work, curated provider config, JSONL sessions beat mandatory telemetry.

**/features content:** terminal agent loop, file editing + command execution, model/provider selection, sessions + replay, Docker sandbox, web + extraction, subagents, skills/MCP. Each feature has one "when you use this" example.

**Tone rules (from plan):** no "10x", "autonomous developer", "magic", or generic AI assistant claims. Show commands/config/TUI; prefer examples over claims.

**Depends on:** W1 (VitePress shell), W6 (terminal demo Vue component).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Three pages render under `vitepress dev`
- [ ] #2 Home passes the "30 second explain" test (a fresh reader can describe Glue after reading the hero)
- [ ] #3 No "10x", "autonomous", or "magic" language anywhere
- [ ] #4 Terminal demo embedded on home (via W6 component once available)
- [ ] #5 `/why` and `/features` cover content lists from plan
- [ ] #6 Home install command sourced from shared snippet (W9)
<!-- AC:END -->
