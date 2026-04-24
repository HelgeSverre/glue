# Slash command rename audit

**Branch:** `refactor/c1-turn`
**Date:** 2026-04-24
**Status:** Phase A — proposal only. No code changes. Awaits user approval before Phase B (rename implementation).

## Context

The `refactor/c1-turn` handoff (`docs/plans/2026-04-24-handoff.md`) flagged an
audit of the slash-command surface as Task 3: _"17 commands today, audit for
ergonomics."_ Task 4 (`ArgCompleter` convention) has since landed — command
registration now lives in one clean file
(`cli/lib/src/runtime/commands/register_builtin_slash_commands.dart`) plus
`share_module.dart`, so any renames are localized to a small set of string
literals.

This document inventories the current commands, compares them with Claude Code
and OpenCode for naming inspiration, and proposes a shortlist of renames ranked
by value-vs-effort. The goal is a user-approved rename list the next
implementation session can execute in a single pass.

## Current commands

18 commands are registered (`/copy` just landed — the handoff's "17" is out of
date). Aliases in parentheses; hidden aliases (not shown in `/help`) in square
brackets.

| #   | Command     | Aliases       | Subcommands                                                       | Takes args | Interactive (panel)? | Description                                              |
| --- | ----------- | ------------- | ----------------------------------------------------------------- | ---------- | -------------------- | -------------------------------------------------------- |
| 1   | `/help`     | —             | —                                                                 | no         | panel                | Show commands + keybindings                              |
| 2   | `/clear`    | —             | —                                                                 | no         | immediate            | Clear conversation history                               |
| 3   | `/exit`     | `quit`, [`q`] | —                                                                 | no         | immediate            | Exit Glue                                                |
| 4   | `/tools`    | —             | —                                                                 | no         | immediate            | List available tools                                     |
| 5   | `/copy`     | —             | —                                                                 | no         | immediate            | Copy last response to clipboard                          |
| 6   | `/debug`    | —             | —                                                                 | no         | immediate            | Toggle debug mode                                        |
| 7   | `/approve`  | —             | —                                                                 | no         | immediate            | Toggle approval mode (confirm ↔ auto)                    |
| 8   | `/model`    | `models`      | —                                                                 | optional   | panel / direct       | No args = picker; arg = switch by query                  |
| 9   | `/session`  | —             | `copy`                                                            | optional   | immediate            | Show session info; `/session copy` copies ID             |
| 10  | `/history`  | —             | —                                                                 | optional   | panel / direct       | Browse/fork history; arg = fork by index/query           |
| 11  | `/resume`   | —             | —                                                                 | optional   | panel / direct       | Resume session; arg = switch by ID/query                 |
| 12  | `/rename`   | —             | —                                                                 | yes        | immediate            | Rename current session                                   |
| 13  | `/skills`   | —             | —                                                                 | optional   | panel / direct       | Browse/activate skill                                    |
| 14  | `/share`    | —             | —                                                                 | optional   | immediate            | Export session (html, markdown, gist)                    |
| 15  | `/provider` | —             | `list`, `add`, `remove`\|`rm`, `test`                             | optional   | panel / direct       | Manage providers                                         |
| 16  | `/paths`    | [`where`]     | —                                                                 | no         | immediate            | Show Glue data paths                                     |
| 17  | `/config`   | —             | `init`                                                            | optional   | external editor      | Open config.yaml in `$EDITOR`; `/config init` bootstraps |
| 18  | `/open`     | —             | `home`, `session`, `sessions`, `logs`, `skills`, `plans`, `cache` | yes        | external             | Open a Glue directory in file manager                    |

Registration is implemented in:

- `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` —
  commands 1–17.
- `cli/lib/src/share/share_module.dart` — command 14 (`/share`) lives with its
  controller by design.

`/help` content is generated from the registry, so rename edits don't need a
help-text sync. Tests referencing command names by string literal live in
`cli/test/commands/{slash_autocomplete_test,slash_autocomplete_integration_test,builtin_commands_test}.dart`.

## Competitor comparison

### Claude Code — built-in commands (selected)

Claude Code's surface is large and trends toward namespace-first commands
(`/add-dir`, `/pr-comments`, `/release-notes`, `/setup-bedrock`,
`/setup-vertex`, `/autofix-pr`, `/install-github-app`, `/install-slack-app`).
For the overlap with Glue's surface:

| Claude Code    | Purpose                                                    |
| -------------- | ---------------------------------------------------------- |
| `/help`        | Show commands                                              |
| `/clear`       | Clear context                                              |
| `/exit`        | Exit                                                       |
| `/copy`        | Copy response                                              |
| `/model`       | Switch model                                               |
| `/config`      | Open config                                                |
| `/export`      | Export conversation (vs. Glue's `/share`)                  |
| `/resume`      | Resume a session                                           |
| `/rename`      | Rename current session                                     |
| `/agents`      | Manage subagents                                           |
| `/debug`       | (bundled skill) debugging playbook — **not** Glue's toggle |
| `/memory`      | Manage memory (CLAUDE.md)                                  |
| `/permissions` | Manage permissions                                         |
| `/review`      | Code review skill                                          |
| `/status`      | Session status                                             |
| `/cost`        | Token/cost breakdown                                       |
| `/skills`      | Manage skills                                              |

Naming conventions in Claude Code:

- Flat command names, no subcommand tree. `/add-dir` not `/dir add`.
- Verbs preferred over nouns (`/rename`, `/clear`, `/resume`).
- Actions on a resource often get a dedicated verb command rather than a
  subcommand (`/clear` not `/session clear`).

### OpenCode

A much smaller surface:

| OpenCode | Purpose                 |
| -------- | ----------------------- |
| `/init`  | Initialize project      |
| `/undo`  | Revert changes          |
| `/redo`  | Restore                 |
| `/share` | Share conversation link |
| `/help`  | Help                    |

OpenCode's `/share` matches Glue's naming. `/init` there means project bootstrap
(not config init), so there's no collision to worry about.

### Takeaways

- Both tools favor flat verbs and avoid deep subcommand trees.
- `/copy`, `/clear`, `/exit`, `/model`, `/rename`, `/resume`, `/help`, `/skills`,
  `/share`, `/config` are all directly overlapping and consistent with Glue's
  naming — no rename pressure from alignment.
- Glue's `/session`, `/paths`, `/approve`, `/tools`, `/provider`, `/debug`
  (toggle), and `/open` are Glue-specific and have no clear competitor
  equivalent.

## Proposed rename table

Columns: current → proposed → rationale → breaking? (alias kept) → priority.

| #   | Current                                  | Proposed                                                                                                                   | Rationale                                                                                                                                                                                                                                                                                                 | Breaking?                                                                                                                        | Priority                                                                    |
| --- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------ | --------- | --------- |
| A   | `/rename`                                | `/rename` (no change) — **but** add `/session rename` as a sibling subcommand that delegates to the same controller method | `/rename` is ambiguous on read — "rename what?". `/session rename <title>` makes the target explicit. Keep `/rename` as top-level for ergonomics (short-name users will keep typing it).                                                                                                                  | No; alias kept                                                                                                                   | Medium                                                                      |
| B   | `/session copy`                          | `/session id` (show + offer copy) — or keep `copy`, add `/session new` and `/session rename` as siblings                   | `copy` is fine but buried. Making `/session` a real noun namespace (`copy`, `rename`, `info`, `new`) improves discoverability via help text listing subcommands. Alternatively: drop `/session copy` and expose dedicated `/copy-session-id` top-level — rejected, too narrow.                            | No; `copy` subcommand preserved                                                                                                  | Low (cosmetic)                                                              |
| C   | `/models` alias                          | Drop                                                                                                                       | Plural adds no value; `/model` already accepts a query arg so `/models` is not doing "list models" — that's what `/model` with no args does. The alias shipped only for discoverability; after six months of use, drop it.                                                                                | Breaking for typed `/models`; no alias replacement                                                                               | Low                                                                         |
| D   | `/paths` + hidden `where`                | Promote `/where` to the primary name, make `/paths` the hidden alias                                                       | `/where` matches the `glue --where` root flag and the `buildWhereReport()` function name — consistency across surfaces. `/paths` is generic; `/where` is distinct and memorable.                                                                                                                          | Not breaking; primary flips, alias flips                                                                                         | Medium                                                                      |
| E   | `/config` (bare = edit) + `/config init` | Keep `/config` (bare = edit) + `/config init` (no change)                                                                  | Considered `/config edit` for symmetry with `glue config init                                                                                                                                                                                                                                             | show`, but `/config`alone meaning "open in editor" is more ergonomic than requiring an explicit subcommand. CLI`glue config init | show` is non-interactive and needs explicit verbs; interactive TUI doesn't. | n/a                                        | No change |
| F   | `/provider` + subcommands                | Keep as-is. No top-level `/add-provider`, `/test-provider` aliases                                                         | Noun namespace is working. Top-level verbs would dilute the command list. `/provider list                                                                                                                                                                                                                 | add                                                                                                                              | remove                                                                      | test` is a tight, well-scoped sub-grammar. | n/a       | No change |
| G   | `/exit` / `/quit` / `/q`                 | Keep `/exit` primary, `/quit` alias, drop hidden `/q`                                                                      | `q` is a vim-ism; collides with normal typing on first keystroke after `/`. Actively harmful for discoverability of any future `/q*` commands. `/quit` is a harmless synonym (visible).                                                                                                                   | Breaking for `/q` typists; no alias                                                                                              | Medium                                                                      |
| H   | `/debug`                                 | Make it accept optional `on`/`off`: `/debug [on\|off]`                                                                     | Today `/debug` is a bare toggle that returns "Debug mode: true/false". Awkward in scripts + requires checking state first. Accept optional arg; no arg = toggle (preserves current behavior).                                                                                                             | No; additive                                                                                                                     | Low                                                                         |
| I   | `/approve`                               | Keep. Consider `/approve [confirm\|auto\|autoedit\|yolo]` to match Shift+Tab cycle                                         | Same rationale as `/debug`. Today's bare toggle cycles; adding an explicit mode arg makes the command scriptable.                                                                                                                                                                                         | No; additive                                                                                                                     | Low                                                                         |
| J   | `/history` vs `/resume`                  | Keep both. Clarify descriptions to disambiguate                                                                            | `/history` forks (branches off a prior message in the current session). `/resume` switches to a different saved session. The verbs are fine but the current `/help` descriptions ("Browse history or fork by index/query" vs "Resume a session") don't draw the distinction sharply. Tighten the strings. | No                                                                                                                               | Low (copy change)                                                           |
| K   | `/open`                                  | Keep as noun-first (`/open <target>`)                                                                                      | Considered splitting to `/open-config`, `/open-logs`, etc. Rejected — `/open` as a primitive with a completer is cleaner and already works.                                                                                                                                                               | n/a                                                                                                                              | No change                                                                   |
| L   | `/tools`                                 | Keep                                                                                                                       | Matches user mental model; no competitor does better.                                                                                                                                                                                                                                                     | n/a                                                                                                                              | No change                                                                   |
| M   | `/copy`                                  | Keep                                                                                                                       | Just landed; matches Claude Code.                                                                                                                                                                                                                                                                         | n/a                                                                                                                              | No change                                                                   |
| N   | `/clear`                                 | Keep                                                                                                                       | Universal.                                                                                                                                                                                                                                                                                                | n/a                                                                                                                              | No change                                                                   |
| O   | `/help`                                  | Keep                                                                                                                       | Universal.                                                                                                                                                                                                                                                                                                | n/a                                                                                                                              | No change                                                                   |
| P   | `/skills`                                | Keep                                                                                                                       | Matches Claude Code.                                                                                                                                                                                                                                                                                      | n/a                                                                                                                              | No change                                                                   |
| Q   | `/share`                                 | Keep                                                                                                                       | Matches OpenCode; lives in its own module.                                                                                                                                                                                                                                                                | n/a                                                                                                                              | No change                                                                   |

## Recommendation

### Top picks (meaningful UX wins)

1. **D. Promote `/where` to primary, demote `/paths` to hidden alias.**
   Lowest risk, clearest win. Consistency with `glue --where` at the CLI
   layer and the existing `buildWhereReport()` name. One string swap in one
   file. No behavior change. **Priority: Medium.**

2. **G. Drop the hidden `/q` alias.**
   Single-letter aliases are a trap as the command surface grows.
   `/quit` remains as a visible synonym. One-line deletion. **Priority:
   Medium.**

3. **A. Add `/session rename` as a sibling to `/session copy`.**
   Keeps `/rename` working (ergonomic), but makes the session-namespace more
   cohesive and discoverable. Small controller change (new subcommand case),
   no breaking change to `/rename`. **Priority: Medium.**

### Worth doing only if the team wants to tighten

4. **H+I. Accept explicit `on/off` args on `/debug` and `/approve`.**
   Purely additive. Makes the commands scriptable (useful in headless mode),
   and the bare form still toggles. **Priority: Low.**

5. **C. Drop the `/models` alias.**
   Six months post-ship, the plural alias is dead weight. If the project is
   pre-1.0 (it is) this is the cheapest time to remove it. **Priority: Low.**

### Explicitly not worth doing (pure bikeshedding)

- Splitting `/config` into `/config edit` / `/config init`. Current shape is
  tighter.
- Top-level `/add-provider`, `/test-provider` aliases. Noun namespace wins.
- Splitting `/open` into `/open-config`, `/open-logs`. Current shape is
  cleaner.
- Renaming `/rename` → `/session rename` only. The top-level ergonomic form
  is worth keeping.
- Renaming `/history`, `/resume` — the verbs are fine; only description copy
  needs tightening (J).

### Ranked by value / effort

| Rank | Change                                  | Value  | Effort | Verdict      |
| ---- | --------------------------------------- | ------ | ------ | ------------ |
| 1    | D. `/where` primary                     | Medium | Tiny   | Do           |
| 2    | G. Drop `/q`                            | Medium | Tiny   | Do           |
| 3    | A. Add `/session rename`                | Medium | Small  | Do           |
| 4    | J. Tighten `/history` + `/resume` copy  | Low    | Tiny   | Do (free)    |
| 5    | H+I. `/debug on/off`, `/approve <mode>` | Low    | Small  | Optional     |
| 6    | C. Drop `/models` alias                 | Low    | Tiny   | Optional     |
| 7    | B. Flesh out `/session` subcommands     | Low    | Medium | Skip for now |

## Non-goals

Explicitly out of scope for this audit and any follow-up implementation:

- Migrating to a noun-verb grammar (`/model switch`, `/skill activate`, etc.).
  That's a larger UX decision and deserves its own plan.
- Adding entirely new commands (`/cost`, `/status`, `/memory`, `/undo`, etc.).
  Out of scope — this is a rename pass, not a feature add.
- Adding subcommands that don't already exist in a controller
  (e.g. inventing `/session new` when no "new session" controller method
  exists). The audit is limited to surface-level name changes and the one
  aliasing (`/session rename` → existing `renameSession` method).
- Touching the top-level `glue <noun> <verb>` CLI grammar. That surface is
  governed by the CLAUDE.md "CLI Command Surface Conventions" section and is
  a separate discussion.

## Implementation sketch (Phase B preview, not yet approved)

If the user approves picks 1–4 above, Phase B is a ~30-minute diff:

1. `register_builtin_slash_commands.dart`:
   - Swap `name: 'paths'` / `hiddenAliases: ['where']` →
     `name: 'where'` / `hiddenAliases: ['paths']` (or visible alias if we
     want to keep `/paths` discoverable).
   - Delete `'q'` from the `exit` command's `hiddenAliases` list.
   - Tighten `/history` and `/resume` description strings.
2. `session_controller.dart`:
   - `sessionAction()` switch: add `case 'rename':` that delegates to
     `renameSession(rest.join(' '))`.
   - Update usage-error message from `"Try: /session copy"` to
     `"Try: /session copy|rename"`.
3. `cli/test/commands/*`:
   - Update any string literals matching the renames.
4. Optional picks 5–6 in the same commit or follow-up.

All work stays within the file-ownership boundary described in the Task 3
dispatch plan: registration file + `share_module.dart` + controller name-string
paths + tests + this doc.
