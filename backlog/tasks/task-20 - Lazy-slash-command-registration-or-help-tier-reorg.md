---
id: TASK-20
title: Lazy slash command registration (or /help tier reorg)
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:02'
labels:
  - simplification-2026-04
  - cli
  - perf
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
