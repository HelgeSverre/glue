---
id: TASK-3
title: Multi-model consensus command ("/debate" or similar)
status: To Do
assignee: []
created_date: "2026-04-18 23:57"
updated_date: "2026-04-20 00:05"
labels:
  - feature
  - slash-command
  - llm
  - design
milestone: m-3
dependencies: []
references:
  - cli/IDEAS.md
priority: low
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Add a slash command that sends the same prompt to multiple models and/or providers simultaneously, then synthesizes a best-of answer. Name TBD — working title `/debate`; alternatives to consider: `/council`, `/consult`, `/jury`, `/consensus`.

Usage shape: `/debate "question here"` → fans out to N configured models (e.g., claude-opus + gpt-4 + qwen3), streams each response in parallel, then runs a synthesizer pass (one of the models, or a dedicated "judge" model) that produces a consolidated final answer citing where models agreed/disagreed.

Open design questions (decide during implementation):

- Config: which models participate? Global setting or per-invocation?
- UI: parallel panels or sequential with headers?
- Synthesis prompt: who acts as judge? Show raw responses too, or only synthesis?
- Cost: warn user before fanning out, given token multiplier

Source: `cli/IDEAS.md`

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Slash command registered (final name chosen)
- [ ] #2 Fans out a single prompt to N configured models in parallel
- [ ] #3 Streams each model's response with clear attribution
- [ ] #4 Synthesis pass produces a consolidated answer
- [ ] #5 Configuration mechanism for which models participate
- [ ] #6 Cost warning shown before fan-out (approx token × N)
- [ ] #7 Unit tests for fan-out orchestration
- [ ] #8 Docs in `devdocs/` explaining usage and configuration
<!-- AC:END -->
