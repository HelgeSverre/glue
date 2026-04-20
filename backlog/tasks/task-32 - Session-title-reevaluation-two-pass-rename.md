---
id: TASK-32
title: "Session title reevaluation: two-pass + /rename"
status: To Do
assignee: []
created_date: "2026-04-20 00:00"
updated_date: "2026-04-20 00:32"
labels:
  - session
  - llm
  - ux
milestone: m-0
dependencies: []
references:
  - cli/lib/src/app/event_router.dart
  - cli/lib/src/app/session_runtime.dart
  - cli/lib/src/session/session_manager.dart
  - cli/lib/src/storage/session_store.dart
  - cli/lib/src/llm/title_generator.dart
documentation:
  - docs/plans/2026-04-20-session-title-reevaluation-plan.md
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Glue currently generates a session title once from the first user message and never revisits it. That fails for vague openers like "help me debug this" — the actual task only becomes clear after the first turn.

Adopt a pragmatic two-pass design (not continuous rewriting):

1. **Pass 1 — fast initial title** generated as today, treated as _provisional_.
2. **Pass 2 — reevaluate** once the session has more evidence (after first assistant response + first tool batch, or after Nth turn — exact trigger TBD in plan).
3. **Stabilize** after pass 2; never auto-revise again unless the user invokes `/rename`.
4. **`/rename <new title>`** slash command sets the title manually.
5. **Manual rename is sticky** — once user-set, disable any future auto-title generation/reevaluation for that session.
6. **Never overwrite a user-set title.**
7. Avoid title churn from repeated background rewrites.

**Key design problem identified in plan:** `_titleGenerated` currently means both _"we attempted to generate a title"_ and _"the title should never be reconsidered"_. Decouple those — likely two flags: `titleAttempted` (rate-limit) and `titleLockedByUser` (user override).

**Coordinates with TASK-15** — title generation is already gated by `titleGenerationEnabled`. Reevaluation must respect the same flag (skip pass 2 when disabled).

**Out of scope:**

- Continuous live retitling on every turn.
- Resume-time backfill changes beyond what the two-pass design needs.

See `docs/plans/2026-04-20-session-title-reevaluation-plan.md` for full plan, including OpenCode reference.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 First-turn provisional title still generated as before (no regression on fast feedback).
- [ ] #2 Second pass triggers based on documented heuristic and writes a refined title to `meta.title`.
- [ ] #3 Second pass never runs after a user has invoked `/rename`.
- [ ] #4 `/rename <title>` slash command sets the session title and persists immediately.
- [ ] #5 User-set titles are never overwritten by any auto-generation pass.
- [ ] #6 When `titleGenerationEnabled` is false (TASK-15), neither pass runs.
- [ ] #7 No more than two auto-title generations occur per session lifetime (no churn).
- [ ] #8 Tests cover: provisional → refined transition, rename-then-no-reeval, disabled-flag short-circuit, resume-with-existing-title no-op.
<!-- AC:END -->
