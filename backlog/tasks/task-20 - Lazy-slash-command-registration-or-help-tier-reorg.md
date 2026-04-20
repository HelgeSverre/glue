---
id: TASK-20
title: Lazy slash command registration (or /help tier reorg)
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-20 00:05'
labels:
  - simplification-2026-04
  - cli
  - perf
milestone: m-4
dependencies: []
references:
  - cli/lib/src/commands/builtin_commands.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The slash command registry is eager and visible in hot-path discovery. Rare commands don't need to be registered on every startup.

**Target:** tier commands `common` vs `rare`. Eagerly register `common`; register `rare` only when user invokes `/help` or types a prefix that matches.

**Common commands (keep eager):** `/model`, `/session`, `/new`, `/help`, `/quit`, `/info`, `/approve` (if retained per R3).

**Rare candidates (identify during execution):** debug dumps, version info, admin-style commands.

**Fallback scope:** If there's no measurable startup cost, demote this task to "reorganize `/help` by tier" — same UX improvement without architectural change.

**Files:**
- `cli/lib/src/commands/builtin_commands.dart`
- `cli/lib/src/commands/` registry implementation
- Autocomplete source (`cli/lib/src/ui/slash_autocomplete.dart`) — must force registration when scanning for prefix matches
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Common commands eagerly registered (verifiable via spy)
- [ ] #2 ≥5 rare commands moved to lazy registration — OR this task demoted to /help tier reorg
- [ ] #3 `/help` shows all commands (forces registration if lazy)
- [ ] #4 Tab autocomplete on `/` still discovers everything
- [ ] #5 No user-visible regression
- [ ] #6 `dart test` green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**2026-04-20 sweep:** Likely superseded by TASK-33 (slash command grammar lock-in). Moved to Deferred milestone pending TASK-33 outcome — if TASK-33 lands a `/help` reorg, this task is closeable; otherwise it can be revived as a remaining concrete change.
<!-- SECTION:NOTES:END -->
