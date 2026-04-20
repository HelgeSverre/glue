---
id: TASK-38
title: Slash command argument autocomplete (post-space filtering)
status: To Do
assignee: []
created_date: "2026-04-20 00:08"
updated_date: "2026-04-20 00:32"
labels:
  - cli
  - ux
  - autocomplete
milestone: m-0
dependencies: []
references:
  - cli/lib/src/commands/slash_commands.dart
  - cli/lib/src/ui/slash_autocomplete.dart
  - cli/lib/src/app.dart
documentation:
  - docs/plans/2026-04-19-slash-arg-autocomplete.md
priority: medium
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

After the user types `/<cmd> ` (space), the slash dropdown should keep working and filter the command's arguments instead of dismissing. Works for enumerable args (`/open`, `/provider`) and curated dynamic sets (`/skills`, optionally `/model`).

**Per the plan (`docs/plans/2026-04-19-slash-arg-autocomplete.md`, v2 — swarm-reviewed):**

1. Data model: add `SlashArgCandidate` + `SlashArgCompleter` typedef and a nullable `completeArg` field on `SlashCommand`.
2. Overlay: two modes — `name` (current) and `arg` (new). Arg mode activates when buffer is `/<knownCmd> <partial>` and the command has a `completeArg`. Splice-in-place on accept (mirrors `ShellAutocomplete`).
3. Wire-up: completers attached in `App._initCommands()` after `BuiltinCommands.create(...)` returns — closures capture `this` and read live state. **No new callbacks added through `BuiltinCommands.create`.**
4. Per-command completers live as small private methods on `App`.

**Scope (v2):**

- **In:** `/open` (static), `/provider` (2-level), `/skills` (registry list).
- **Conditionally in:** `/model` — only if matching semantics fix (multi-segment match + min-chars gate + result cap) lands; otherwise defer.
- **Out:** `/history`, `/resume` — session IDs in a dropdown are user-hostile; existing panels solve discovery.

**Coordinates with TASK-33** (slash command grammar) — argument completion grammar should match whatever subcommand surface TASK-33 settles on. Schedule together or schedule TASK-33 first.

**Out of scope:**

- Cursor-not-at-end argument completion (current constraint).
- Async / network-backed completers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 `SlashArgCandidate` + `SlashArgCompleter` types exist on `SlashCommand` registry.
- [ ] #2 Arg-mode autocomplete activates after the first space following a known command name.
- [ ] #3 Backspace across the trailing space reverts to name-mode.
- [ ] #4 Tab/Enter splices the candidate in place; trailing space appended when `candidate.continues` is true.
- [ ] #5 `/open`, `/provider`, `/skills` all have argument completers.
- [ ] #6 `/model` decision documented: shipped (with three matching fixes) or deferred (to a follow-up task).
- [ ] #7 Tests cover: activation transitions, alias resolution (`/q ` hits `/exit`'s completer), whitespace edges, mode-transition behavior.
<!-- AC:END -->
