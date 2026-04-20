---
id: TASK-33
title: "Slash command grammar: lock in conventions across all commands"
status: To Do
assignee: []
created_date: "2026-04-20 00:00"
updated_date: "2026-04-20 00:32"
labels:
  - cli
  - ux
  - commands
  - design
milestone: m-0
dependencies: []
references:
  - cli/lib/src/commands/builtin_commands.dart
  - cli/lib/src/commands/slash_commands.dart
documentation:
  - docs/plans/2026-04-20-slash-command-conventions.md
priority: medium
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Glue's 16 slash commands have drifted into 7 inconsistent shapes (simple-action, simple-info, simple-toggle, simple-panel, panel-or-query, subcommand, target-arg). Before adding more, lock in a single grammar covering every existing and plausible future command.

**The plan (`docs/plans/2026-04-20-slash-command-conventions.md`) already produces:**

- Full audit of the 16 commands.
- Proposed grammar based on industry convention: _verb-first flat for hot-path actions; one noun namespace (`/session`) for inspection/admin_.
- Migration map for what each command becomes.
- Adversarial review.
- External research across Claude Code, Amp, OpenCode, Codex, Copilot CLI, Droid, Gemini CLI, Aider.

**Identified problems to resolve:**

- `/session` and `/resume` split the same domain with different no-args behavior.
- `/info` duplicates `/session`'s no-args behavior.
- `/models` duplicates `/model`'s no-args behavior.
- `/provider` and `/session` both use subcommands but bare behavior differs (panel vs. info).
- `/open` breaks the "bare = panel" pattern.

**This task = implementation:**

1. Adopt the grammar from the plan as canonical.
2. Migrate existing commands per the migration map.
3. Add deprecation aliases (or hidden aliases, à la `/q` → `/exit`) for muscle memory.
4. Update `/help` and autocomplete to reflect the grammar.
5. Document the grammar somewhere durable (likely `docs/reference/slash-commands.md` or website docs).

**Coordinates with:**

- **TASK-20** (lazy slash registration / `/help` tier reorg) — overlaps on `/help`. Resolve which task owns help reorganization once the grammar is decided.
- **Future `/rename`** (session title reevaluation task) — must conform to whatever grammar this lands.

**Out of scope (this task):**

- Adding new commands beyond what the grammar/migration explicitly requires.
- The `/debate` multi-model consensus command (TASK-3) — separate concern.

See full plan for grammar rules and migration table.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Grammar from the plan is implemented in `SlashCommandRegistry` (or equivalent) with a documented rule per token position.
- [ ] #2 All 16 existing commands migrated per the plan's migration map; no shape inconsistency remains.
- [ ] #3 Deprecated/removed command names resolve via hidden aliases for at least one release cycle (no immediate breakage for muscle memory).
- [ ] #4 `/help` output reflects the new grammar and command groupings.
- [ ] #5 Autocomplete still discovers everything (including aliases for hidden ones).
- [ ] #6 Public docs (website + `docs/reference/`) describe the grammar with examples.
- [ ] #7 Tests cover: each migrated command, alias resolution, help output ordering.
- [ ] #8 TASK-20 is either marked superseded or scoped to a remaining concrete change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->

**CLAUDE.md "CLI Command Surface Conventions" (added 2026-04-20)** now constrains this work at a higher level: slash commands cover _interactive TUI actions_ only; non-interactive / scriptable / setup / diagnostic flows go to top-level CLI subcommands under noun namespaces (e.g. `glue config init`, `glue doctor`). This task's grammar must therefore be scoped to the interactive slash surface and explicitly _not_ try to subsume CLI subcommand grammar — though the plan's noun-namespace pattern (e.g. `/session info|copy|rename`) deliberately mirrors the CLI side for muscle-memory parity, which the convention encourages ("aligned where practical").

<!-- SECTION:NOTES:END -->
