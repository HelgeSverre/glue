# Slash Command Conventions — Research + Design Plan

> Status: research / design. No code changes in this plan. Supersedes and broadens the earlier `plan_session_resume_consolidation.md`.

## Goal

Glue's slash commands have drifted into three inconsistent shapes. Before adding more, lock in a **single grammar** that covers every existing command and every plausible future one.

Concretely, produce:

1. A full audit of today's 16 commands, classified by shape.
2. A proposed grammar ("one rule per token position") that covers all of them.
3. A migration map showing what each command becomes under the grammar.
4. An adversarial review covering UX, implementation, and backward-compat risk.
5. External research: how other coding-agent harnesses (Claude Code, Amp, OpenCode, Codex, Copilot CLI, Droid, Gemini CLI, Aider) structure their slash commands.

## 1. Current state audit

Registered commands live in `cli/lib/src/commands/builtin_commands.dart:28-161`. All 16:

| Command     | Aliases     | No-args behavior              | With-args behavior                       | Shape              |
| ----------- | ----------- | ----------------------------- | ---------------------------------------- | ------------------ |
| `/help`     | —           | Opens help panel              | n/a                                      | simple-panel       |
| `/clear`    | —           | Clears conversation           | n/a                                      | simple-action      |
| `/exit`     | `quit`, `q` | Exits                         | n/a                                      | simple-action      |
| `/model`    | —           | Opens model panel             | Switch by query                          | **panel-or-query** |
| `/models`   | —           | Opens model panel             | Same                                     | simple-panel       |
| `/info`     | `status`    | Shows session info inline     | n/a                                      | simple-info        |
| `/session`  | —           | **Shows session info inline** | `copy` → copy ID (only known subcommand) | **subcommand**     |
| `/tools`    | —           | Lists tools inline            | n/a                                      | simple-info        |
| `/history`  | —           | Opens history panel           | Fork by query                            | **panel-or-query** |
| `/resume`   | —           | Opens resume panel            | Resume by query                          | **panel-or-query** |
| `/debug`    | —           | Toggles debug                 | n/a                                      | simple-toggle      |
| `/skills`   | —           | Opens skills panel            | Activate by name                         | **panel-or-query** |
| `/approve`  | —           | Toggles approval              | n/a                                      | simple-toggle      |
| `/provider` | —           | Opens provider panel          | `list\|add\|remove\|test [id]`           | **subcommand**     |
| `/paths`    | `where`     | Shows paths inline            | n/a                                      | simple-info        |
| `/open`     | —           | Prints usage text             | `<target>` → opens folder                | **target-arg**     |

### Shapes currently in use

1. **simple-action** — `/clear`, `/exit`. No arguments, does a thing.
2. **simple-info** — `/info`, `/tools`, `/paths`. Prints inline status.
3. **simple-toggle** — `/debug`, `/approve`. Flips a boolean.
4. **simple-panel** — `/help`, `/models`. Opens a panel. Args ignored.
5. **panel-or-query** — `/model`, `/history`, `/resume`, `/skills`. Bare = panel, arg = fuzzy-matched action.
6. **subcommand** — `/session`, `/provider`. Explicit verbs after the noun. Bare behavior is inconsistent (`/session` shows info; `/provider` opens panel).
7. **target-arg** — `/open`. Bare prints usage; arg selects an enumerated target.

### The actual problems

- **`/session` and `/resume` split the same domain** with different no-args behavior. `/session` shows info; `/resume` opens a browser. Users have to remember two entry points for one noun.
- **`/info` duplicates `/session`'s no-args behavior.** Two commands for the same output.
- **`/models` duplicates `/model`'s no-args behavior.** Same output, different name.
- **`/provider` and `/session` both use subcommands, but bare behavior differs** (panel vs. info). No clear rule for which wins.
- **`/open` breaks the "bare = panel" pattern** by printing usage instead. It is the only enumerated-target command.

## 2. Command shapes we should keep

We have seven shapes. Three of them are structurally the same (simple-action, simple-info, simple-toggle — all "no args, one effect"), and **panel-or-query** is really a superset of **simple-panel** plus an optional inline shortcut.

Collapsed, there are really three shapes:

- **Leaf commands** — take no arguments, produce one effect. (`/help`, `/clear`, `/exit`, `/info`, `/tools`, `/paths`, `/debug`, `/approve`.)
- **Domain commands** — own a noun. Bare opens the primary panel for that noun; subcommands are explicit verbs; a query-shortcut form is optional but allowed. (`/model`, `/history`, `/resume`, `/skills`, `/session`, `/provider`.)
- **Target commands** — operate on an enumerated set where the arg is the target. (`/open`.)

The inconsistency lives inside the domain-command group.

## 3. Proposed grammar (revised after external research)

The industry convention is **verb-first flat for hot-path actions, with one noun namespace (`/session`) for current-session inspection and admin**. Grammar rules below.

```
/<verb>                          — hot-path state transitions (resume, new, fork, compact, clear)
/<noun> [<subcommand>] [<args>…] — inspection/admin (info, copy, rename, delete, stats)
```

### Rule A — Hot-path state transitions are **top-level verbs**, not subcommands

The common, frequently-typed actions stay as flat verbs:

- `/resume` — open session browser; `/resume <query>` jumps directly (current behavior, preserve).
- `/new` — start a fresh session. (Not implemented yet. Add.)
- `/fork` — clone current session into a new branch. (Not implemented yet. Add, or defer.)
- `/compact` — summarize current context. (Not implemented yet. Add if agent supports it, else defer.)
- `/clear` — wipe conversation (already exists).
- `/rename` — rename current session. (Not implemented yet. Defer.)
- `/export` — write current session to a file. (Not implemented yet. Defer.)

Rationale: 6 of 8 surveyed agents use flat verbs for these. Users coming from Claude Code, Codex, Copilot, OpenCode, or Aider have muscle memory for this shape. Fighting it costs more than it saves.

### Rule B — `/session` is the inspection/admin namespace for the **current** session

Everything under `/session <sub>` acts on the session the user is _in right now_. It never picks a different session (that's `/resume`).

Subcommands:

- `/session` bare → inline info (ID, model, token usage). Matches Copilot CLI exactly.
- `/session info` → explicit form of bare.
- `/session copy` → copy current session ID to clipboard. (Already exists; stays.)
- `/session rename <name>` → rename current. (Deferred, add later.)
- `/session delete` → delete current session and its files. (Deferred.)
- `/session export <path>` → export transcript. (Deferred.)

**`/session` does NOT open a browser panel.** Browsing/switching is `/resume`. This is the Copilot CLI split: verb for transitions, noun for inspection of the current one.

### Rule C — Other domains keep their current panel-or-query shape

`/model`, `/history`, `/skills`, `/provider` are domain panels, not session management. They don't map onto the verb/noun split above; they're each a picker for a catalog of things. Their current shape is fine:

- **Bare** opens the panel for that catalog.
- **With query** performs the dominant action: switch model, fork history, activate skill, provider subcommand.

Small cleanups under this rule:

- `/models` → hidden alias of `/model` (two visible commands for the same panel is noise).
- `/skills` stays plural as canonical — we're a catalog, not a single-skill tool. Singular `/skill` optional as hidden alias. (Revises open question 5 — see below.)
- `/provider` bare already opens panel. Keep as-is.

### Rule D — Leaf commands are still leaves

`/help`, `/clear`, `/exit`, `/info`, `/tools`, `/paths`, `/debug`, `/approve`, `/open` stay as-is under their current shape. These aren't session management or catalog pickers; they're one-shot utilities.

Only change: `/clear` might gain a sibling `/new` (Rule A), and `/info` might eventually become the "dashboard" while `/session` specifically shows session-level info. Today they overlap; Rule B puts `/session` firmly in the session-only box.

### Rule E — Aliases are compatibility redirects

One canonical name per concept. Aliases never diverge semantically.

- `/quit`, `/q` → `/exit` (already hidden).
- `/status` → `/info` (already hidden).
- `/where` → `/paths` (already hidden).
- `/models` → `/model` (make hidden alias; currently visible duplicate).
- `/continue` → `/resume` (industry convention; add as hidden alias to ease migration from Claude Code / OpenCode users).
- `/sessions` (plural) → `/resume` (plural-as-picker convention from OpenCode/Droid; add as hidden alias).

### What this _doesn't_ do

- Does not force everything into `/session <sub>`. The original plan did; the external evidence says that's wrong.
- Does not invent `/<noun> list` as a required form. Catalog commands stay bare-opens-panel.
- Does not remove `/resume` or fold it into `/session`. `/resume` is the canonical session-switching surface in 5 of 8 agents surveyed; keeping it is the correct decision.

## 4. Migration map (revised)

Each existing command, and what it becomes under the revised grammar:

| Today                   | Tomorrow                                                                                                                                                   | Change                                                                                                   |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `/help`                 | `/help`                                                                                                                                                    | unchanged (leaf)                                                                                         |
| `/clear`                | `/clear`                                                                                                                                                   | **bugfix**: actually wipe conversation history (today it doesn't). No semantic rename                    |
| `/exit` (+ `quit`, `q`) | same                                                                                                                                                       | unchanged (leaf)                                                                                         |
| `/info` (+ `status`)    | **hidden alias of `/session`**                                                                                                                             | deduplicate — today both call same impl                                                                  |
| `/tools`                | same                                                                                                                                                       | unchanged (leaf)                                                                                         |
| `/debug`                | same                                                                                                                                                       | unchanged (leaf, toggle)                                                                                 |
| `/approve`              | same                                                                                                                                                       | unchanged (leaf, toggle)                                                                                 |
| `/paths` (+ `where`)    | same                                                                                                                                                       | unchanged (leaf)                                                                                         |
| `/open`                 | same                                                                                                                                                       | unchanged (target-arg). Keep classification as target-arg, not leaf                                      |
| `/model`                | `/model` — bare opens panel; `/model <ref>` = switch                                                                                                       | unchanged                                                                                                |
| `/models`               | **hidden alias** of `/model`                                                                                                                               | deduplicate. Website docs updated in same PR                                                             |
| `/history`              | `/history` — bare opens panel; `/history <query>` = fork                                                                                                   | unchanged                                                                                                |
| `/skills`               | `/skills` — bare opens panel; `/skills <name>` = activate                                                                                                  | **unchanged**. `/skill` alias dropped (reserves future `/skill <sub>` namespace)                         |
| `/provider`             | `/provider` — routed via `SlashSubcommandRouter`; subs: `list`, `add`, `remove`/`rm`, `test`                                                               | routing consolidated; behavior unchanged                                                                 |
| `/resume`               | **unchanged** — bare opens session browser; `/resume <query>` = jump. Hidden alias `/continue`                                                             | Kept as top-level verb (industry convention). `/sessions` alias dropped (collides with `/open sessions`) |
| `/session`              | `/session` — routed via `SlashSubcommandRouter`; bare → inline info; subs: `info` (explicit alias), `copy`; reserve `rename`, `delete`, `export` for later | Contract formalized; matches actual code output                                                          |

**New commands to consider adding (Rule A):**

| New              | Purpose                                                              | Status                                      |
| ---------------- | -------------------------------------------------------------------- | ------------------------------------------- |
| `/new`           | Start fresh session (preserves scrollback; `/clear` resets terminal) | Add in Phase 2. 5/8 agents have this        |
| `/fork`          | Clone current session to a new thread                                | Add in Phase 3 if session model supports it |
| `/compact`       | Summarize context to save tokens                                     | Add in Phase 3 if runtime supports it       |
| `/rename <name>` | Rename current session                                               | Defer                                       |
| `/export <path>` | Export transcript                                                    | Defer                                       |

**New hidden aliases:**

- `/continue` → `/resume` (Claude Code / OpenCode muscle memory).
- `/sessions` → `/resume` (OpenCode / Droid plural-as-picker).
- `/models` → `/model` (dedupe).
- `/skill` → `/skills` (singular).

**Net effect by command count (after Phase 2):**

- Visible commands: 16 → 14 (`/models` hidden, `/info` folded into `/session`).
- Hidden aliases: 5 → 7 (adds `/continue`, `/models`; `/info` and `/status` now resolve to `/session`).
- `/session` has a formalized contract matching actual code output.
- `/resume` preserved verbatim.
- `/clear` is no longer a silent no-op.
- `/sessions` and `/skill` aliases **dropped** per review (collisions).
- `/new` deferred to Phase 3 behind a `SessionManager.startNewSession()` prerequisite.

### Why this plan is smaller than the original consolidation plan

The original plan proposed merging `/resume` into `/session`. External research says 5 of 8 comparable tools keep `/resume` as a verb. Merging would burn muscle memory for users coming from Claude Code, Codex, Copilot CLI, OpenCode, and Aider. The revised plan keeps `/resume` exactly as-is and instead formalizes `/session` as the "describe the current session" namespace — which is what it already does, just with a clearer contract.

## 5. External harness research

Surveyed Claude Code, Amp, OpenCode, Codex CLI, Copilot CLI, Droid, Gemini CLI, and Aider. Primary sources only (official docs and source).

### Per-tool findings

- **Claude Code** — verb-first, flat. `/clear`, `/compact`, `/resume` (alias `/continue`), `/rename`, `/branch`, `/rewind`, `/export`, `/copy`, `/context`, `/cost`. `/resume` no-args = picker; `/resume <name>` = direct jump. CLI flags: `claude -c` (most recent), `-r <id>`, `--resume` (picker), `--from-pr <n>`.
- **Amp (Sourcegraph)** — TUI slash set minimal (`/help`, `/new`). Thread ops live in command palette (Ctrl+O). Real session API is CLI noun-first: `amp threads new|list|continue|fork|share|compact`. Canonical noun is "thread" ("git branches for AI conversations").
- **OpenCode** — verb-first with aliases, one plural-noun exception. `/new` (= `/clear`), `/sessions` (= `/resume`/`/continue`), `/compact`, `/share`, `/unshare`, `/export`, `/redo`, `/undo`, `/exit`.
- **OpenAI Codex CLI** — fully verb-first, flat. `/new`, `/clear`, `/resume`, `/fork`, `/copy`, `/status`, `/review`, `/init`, `/model`, `/quit`. Clean split: `/new` = fresh conversation, `/clear` = fresh + clears terminal, `/fork` = clone current.
- **GitHub Copilot CLI** — mixed. Verbs for actions (`/clear`, `/new`, `/resume`, `/rename`, `/undo`); noun `/session` for _current-session info_; `/chronicle <sub>` is the lone noun-first-with-subs family (analytics).
- **Factory Droid** — `/sessions` opens a browser UI; actions happen inside the UI, not slash subcommands. Same pattern for `/commands`, `/droids`, `/mcp`, `/settings`.
- **Gemini CLI** — the only pure noun-first-with-subcommands session family: `/chat save|list|resume|delete|share <tag>`. Still ships `/resume` as top-level alias — implicitly admitting the noun form is verbose.
- **Aider** — verb-first, no session concept. `/clear`, `/reset`, `/save`, `/load`.

### Comparison

| Tool        | New                 | Resume/Browse                     | Fork               | Most-recent            | Style                        | Picker? |
| ----------- | ------------------- | --------------------------------- | ------------------ | ---------------------- | ---------------------------- | ------- |
| Claude Code | `/clear`            | `/resume`                         | `/branch`          | `claude -c`            | verb-first flat              | yes     |
| Amp         | `/new` + palette    | `amp threads list/continue`       | `amp threads fork` | `amp threads continue` | noun-first (CLI only)        | palette |
| OpenCode    | `/new`              | `/sessions`                       | —                  | `--continue`           | verb-first + plural alias    | yes     |
| Codex       | `/new`              | `/resume`                         | `/fork`            | `codex resume --last`  | verb-first flat              | yes     |
| Copilot     | `/new`              | `/resume`                         | —                  | `--continue`           | verb-first + `/session` info | yes     |
| Droid       | —                   | `/sessions`                       | —                  | —                      | noun-first browser           | yes     |
| Gemini      | UI                  | `/resume` or `/chat resume <tag>` | —                  | `gemini --resume`      | noun-first subs              | yes     |
| Aider       | `/clear` / `/reset` | `/load`                           | —                  | —                      | verb-first flat              | no      |

### Dominant conventions

**Verb-first flat wins for hot-path session actions.** 6 of 8 tools expose `/new`, `/resume`, `/clear`, `/fork` as independent verbs, not as subcommands of a noun. Codex and Claude Code — the two most polished — are purely verb-first.

**Shared vocabulary across tools:**

- `/new` (5/8) — fresh session
- `/clear` (5/8) — wipe history
- `/resume` (5/8) — picker + jump, often aliased `/continue`
- `/compact` (4/8) — summarize, sometimes `/summarize`
- `/fork` or `/branch` (3/8) — diverge
- `/rename`, `/export`, `/share`, `/copy`, `/undo`/`/redo`, `/rewind` — common utilities

**Plural noun as picker shortcut is emerging** (OpenCode `/sessions`, Droid `/sessions`). Claude Code and Codex do the same job via `/resume`.

**Most-recent vs browse consistently split between CLI flag and slash:** every CLI has `--continue`/`-c`/`--last` for most-recent; in-session `/resume` always opens the picker. No tool overloads `/resume` with both.

### Outliers

- **Gemini's `/chat save|list|resume|...`** exists because its model is _manual tagged checkpoints_, not auto-saved sessions. Subcommands disambiguate save-vs-load against a user-supplied tag. They still ship top-level `/resume` as escape hatch.
- **Amp's noun-first** is CLI-level, not slash-level. Slash stays minimal.
- **Copilot's `/chronicle <sub>`** is a specialized analytics domain, not session management.
- **Droid's `/sessions`** opens a full UI; actions live inside the UI, avoiding the noun-vs-verb question.

The pattern: noun-first-with-subcommands only appears when (a) the domain has many equal-weight operations on the same noun (Gemini's tagged checkpoints, Amp's shell-level thread ops) or (b) the noun opens a full UI (Droid). For the _common_ interactive actions (resume, fork, new, clear), every tool picks verbs.

### What this means for Glue

The grammar in section 3 was wrong in its bones. "Everything is a noun; bare noun opens the panel" is **not** the industry convention. Only Gemini goes that way, and even they ship a top-level verb alias because the noun form is verbose.

The dominant convention — and the one Glue should adopt — is:

- **Verbs for state transitions** (`/new`, `/resume`, `/fork`, `/compact`, `/clear`, `/rename`, `/export`).
- **One noun namespace (`/session`) for inspection + admin of the current session** (info, copy, delete, stats). Everything under `/session <sub>` is about _the current one_, not about picking a different one.
- **`/resume` stays verb-first** and is the canonical session-switching surface. Does picker bare; accepts query inline.
- **CLI flags for most-recent:** `glue -c` / `glue --continue` for most-recent, `glue --resume` for picker.

Section 3 is rewritten below to reflect this.

## 6. Open questions

1. **Should `/resume <query>` fuzzy-match session names, or require an ID prefix?**
   - Current implementation accepts any query. Fine — preserves behavior.
   - Recommendation: no change.

2. **Add `/new` now or defer?**
   - Pro now: 5/8 agents have it; closes the "how do I start fresh" question cleanly.
   - Pro defer: overlap with `/clear`. Need a clear semantic split: `/clear` = wipe history in same session; `/new` = start a brand-new session entry.
   - Recommendation: **add now**, with explicit split documented in `/help`.

3. **`/fork` and `/compact` — now or later?**
   - Depends on session model + runtime support. If `SessionManager` already knows how to branch a session, `/fork` is cheap. `/compact` requires prompt-side summarization — nontrivial.
   - Recommendation: **defer both** to Phase 3. They're not broken; they're missing. Ship the grammar first.

4. **CLI parity flags.**
   - External research: every agent has `--continue`/`-c` for most-recent and `--resume` for picker.
   - Glue currently has its own resume flags (check `bin/glue.dart`). If missing, align to this convention.
   - Recommendation: **add in Phase 5** if not present.

5. **Singular vs plural nouns.**
   - Survey shows both: `/sessions` (OpenCode, Droid) and `/session` (Copilot info-form) both exist. No winner.
   - Recommendation: follow existing Glue names (`/skills`, `/models` plural as catalogs; `/session`, `/provider` singular as admin). Add hidden aliases for the opposite form.

6. **Does `/session` need a `list` subcommand at all, given `/resume` is the browser?**
   - No. `/session` is about the current session. Listing other sessions is `/resume`'s job.
   - Drop `/session list` from the plan. Keep `info`, `copy`, `rename`, `delete`, `export`.

## 7. Migration phases (final, post-review)

### Phase 1 — Grammar lock-in (this plan)

Done. External research + adversarial review integrated. Open questions 2 and 6 closed.

### Phase 2 — Bugfix + `/session` router

Narrow, low-risk scope. Nothing about new sessions. Nothing about `/new`.

1. **Fix `/clear`** (`cli/lib/src/app/command_helpers.dart:3-10`). Add `app.agent.clearConversation()` and reset `tokenCount`. One-line bug fix. Add a test.
2. **Extract `SlashSubcommandRouter`** in `cli/lib/src/commands/slash_commands.dart`. Shape: `{name, description, aliases, handler}` entries + default handler. Methods: `dispatch(args)`, `usage()`, `candidates(partial)`.
3. **Migrate `/session` to the router.** Subcommands: `info` (explicit alias of bare), `copy`. Default handler = `info`. Unknown subcommand → router's usage string.
4. **Migrate `/provider` to the router.** Subcommands: `list`, `add`, `remove` (alias `rm`), `test`. Default handler = `list`.
5. **Update `arg_completers.dart` `sessionSubcommands`** to match router (`info`, `copy`). Router owns the canonical set; completer reads from it.
6. **Add hidden aliases**: `/continue` → `/resume`, `/models` → `/model`. (Drop `/sessions` and `/skill` per review.)
7. **Fold `/info`** into `/session` as a hidden alias. Remove duplicate registration.
8. **Website docs update** in the same PR: `website/docs/using-glue/interactive-mode.md:13` — `/models` no longer first-class; `/info` no longer listed separately.

Files touched:

- `cli/lib/src/commands/slash_commands.dart` — add `SlashSubcommandRouter`.
- `cli/lib/src/commands/builtin_commands.dart` — re-register `/session`, `/provider`, add aliases, drop `/info`.
- `cli/lib/src/app/command_helpers.dart` — fix `/clear`; `_sessionActionImpl` and `_runProviderCommandImpl` become thin wrappers over the router (or router construction moves into these impls).
- `cli/lib/src/commands/arg_completers.dart` — `sessionSubcommands` includes `info`; subcommand completers pull from router.
- `cli/test/commands/slash_commands_test.dart` — router tests.
- `cli/test/commands/builtin_commands_test.dart` — alias resolution, `/info` folding.
- `website/docs/using-glue/interactive-mode.md` — docs update.

No callback-surface changes to `BuiltinCommands.create`. No new commands yet.

### Phase 2.5 — `/new` design spike (gate before Phase 3)

**Prerequisite:** design and implement `SessionManager.startNewSession()` with the full state-reset checklist (agent cancellation, observability flush, store close/reopen, panel stack, `_titleGenerated`, etc.). Reviewer 2 enumerated the list; implementation follows that. Document the orphaned-session behavior (old session stays on disk, reachable via `/resume`).

Ship this as its own plan or as a task under this plan — but don't fold the complexity into Phase 2.

### Phase 3 — New hot-path verbs (after 2.5 lands)

- `/new` — starts fresh session via `SessionManager.startNewSession()`. Help text frames by intent: "start a new conversation; the current one stays available via /resume". Registered in `_initCommands` via closure (not via `BuiltinCommands.create` callback).
- `/fork` — optional. `SessionManager.forkSession` exists (`session_manager.dart:181-233`); wiring is small. Help text: "branch from the current conversation". Ship if trivial; defer if it requires replay plumbing beyond what's there.
- `/compact` — defer. Needs summarization via `LlmClient`; not in scope yet.

### Phase 4 — `/resume <query>` completer (optional polish)

Recent-session-id suggestions for `/resume ` arg autocomplete. Only ship if reading a recent-sessions list is cheap (in-memory index, not disk per keystroke). Otherwise drop from scope — `/resume`'s panel is already the discovery surface.

### Phase 5 — CLI parity

Tiny: add `abbr: 'c'` to `--continue` in `bin/glue.dart:48`. Confirm `--resume <id>` direct-jump works at startup. No new flags. Website docs line about `glue -c` gains a short form.

### What's explicitly NOT in any phase

- Removing `/resume`. It stays.
- Turning `/session` into a browser. Inspection-only.
- Browsing commands (like `/history`, `/skills`, `/model`) getting subcommand routers. Only `/session` and `/provider` need them today.

## 8. Acceptance criteria (final)

### Per phase

**Phase 2 (bugfix + router):**

- `/clear` actually wipes `agent._conversation` and resets `agent.tokenCount`. Verified by a test that sends a message, runs `/clear`, then checks `agent._conversation.isEmpty` and `tokenCount == 0`.
- `SlashSubcommandRouter` has tests covering: dispatch, alias resolution, default handler, unknown-sub usage string, completer candidates.
- `/session` and `/provider` use the router. Removing `_sessionActionImpl`'s hand-rolled switch doesn't change observable behavior.
- `/session` bare output contract matches what the code actually prints: model, cwd, token count, message count, tool count, approval mode, auto-approve set. (Session ID added as optional improvement.)
- `/info` no longer appears as a top-level command; `/info` and `/status` resolve to `/session` via alias.
- Hidden aliases work: `/continue` → `/resume`, `/models` → `/model`. (And existing: `/quit`, `/q`, `/status`, `/where`.)
- `website/docs/using-glue/interactive-mode.md` updated in the same PR to reflect the aliased state.
- No callback added to `BuiltinCommands.create`.

**Phase 2.5 gate:**

- `SessionManager.startNewSession()` exists and has tests covering: agent cancellation before new session starts, observability flush, store close, panel stack reset, state reset.
- No data loss on `/new` — old session still findable via `/resume` with its previous ID.

**Phase 3 (new verbs):**

- `/new` registered via `_initCommands` closure (not via `BuiltinCommands.create` callback). Help text frames intent, not implementation.
- `/fork` optional; only ships if the replay plumbing is already present.

**Phase 5 (CLI):**

- `glue -c` works as shorthand for `glue --continue`.

### Cross-cutting

- No visible command description duplicates another visible command's description.
- Autocomplete shows the router's canonical subcommand set — no drift between execute, usage string, and completer.
- Adversarial review findings are cross-referenced by section number in the relevant phase.

## 9. Adversarial review — findings and decisions

Three reviewers attacked the plan from UX, architecture, and migration angles. Every finding below is verified against the code.

### Blocker: `/clear` is already semantically broken

`cli/lib/src/app/command_helpers.dart:3-10`:

```dart
String _clearConversationImpl(App app) {
  app._blocks.clear();
  app._scrollOffset = 0;
  app._streamingText = '';
  app.terminal.clearScreen();
  app.layout.apply();
  return 'Cleared.';
}
```

It clears UI state and the terminal, but **never calls `app.agent.clearConversation()`** and never resets `agent.tokenCount`. The next user message goes to the LLM with the full prior conversation attached. Users think history is wiped; it isn't.

This invalidates the original Phase 2 framing. The plan said "`/clear` — wipe conversation history in _this_ session (current behavior)." The current behavior isn't what the description says.

**Decision: Phase 2 starts by fixing `/clear` — one-line bug fix. Only after that is it safe to introduce `/new` with a meaningful contrast.**

### Blocker: `/new` is not a cheap addition

`cli/lib/src/session/session_manager.dart:97-111` uses `_store ??= SessionStore(...)` — single-session by design. There is no `startNewSession()` primitive. A correct `/new` must:

1. Cancel `_agentSub` (`cli/lib/src/app/agent_orchestration.dart:208`) so an in-flight stream doesn't write into the old store.
2. Flush observability spans tied to the current session ID.
3. Close the current `SessionStore`.
4. Null `_store` so `ensureSessionStore` creates a fresh one.
5. Call `agent.clearConversation()`, reset `tokenCount`, `_titleGenerated`, `_autoApprovedTools` (policy question: reset or carry over?), `_turnSpan`, `_subagentGroups`, `_outputLineGroups`, `_earlyApprovedIds`, `_panelStack`.
6. Answer: what happens to the orphaned prior session on disk? Does `/resume` still find it?

`_resumeSessionImpl` at `session_runtime.dart:115-146` already got the superset wrong once. `/new` is its twin and needs the full list.

**Decision: `/new` is moved out of Phase 2 into its own prerequisite task (Phase 2.5). Phase 2 does NOT ship `/new`. It ships `/clear` fix, `/session` router cleanup, and nothing else user-visible. A separate design spike defines `SessionManager.startNewSession()`. Only after that does `/new` register.**

### Drop: hidden aliases that collide with shipped vocabulary

Three of the four proposed hidden aliases collide with real behavior or shipped names:

- **`/sessions`** → collides with `/open sessions` (`cli/lib/src/commands/arg_completers.dart:18` — `'sessions'` is a valid `/open` target meaning "open the sessions folder"). Users will type `/sessions` expecting the folder. Dropping.
- **`/skill`** (singular) → shadows the plausible future `/skill <name> [info|reload|deactivate]` namespace. Parallel to the plan's own `/session <sub>` design. Don't burn the name. Dropping.
- **`/continue`** → genuine muscle memory from Claude Code / OpenCode, no collision. **Keep**.
- **`/models`** → plural duplicate of `/model`. But it's currently _visible_ and documented at `website/docs/using-glue/interactive-mode.md:13`. Demoting is fine but requires a same-PR docs update. **Keep as hidden alias, docs update in same PR.**

**Decision: only `/continue` and `/models` become hidden aliases. Drop `/sessions` and `/skill`.**

### Fix: the `/info` vs `/session` duplication is real

Both commands call the same code path today:

- `/info` → `sessionInfo()` → `_buildSessionInfoImpl(app)` (`builtin_commands.dart:79`).
- `/session` bare → `_sessionActionImpl(app, [])` → `_buildSessionInfoImpl(app)` (`command_helpers.dart:102`).

Identical output. The plan claimed a "global dashboard vs session-specific" split that doesn't exist in code.

Two options:

1. **Make `/info` a hidden alias of `/session`** — simplest; removes duplication entirely.
2. **Build a real global dashboard** for `/info` (add paths, active providers, active skills, debug/approval state, recent sessions) — larger scope, but justifies keeping both.

**Decision: Option 1. `/info` becomes a hidden alias of `/session` (same canonical command). If someone later wants a richer `/info`, they file a new plan. Don't ship two visible commands with identical output.**

Open question 2 is now closed: `/info` folds into `/session`.

### Fix: `/session` bare's actual output contract

The plan's acceptance criterion claimed `/session` shows "ID, model, approval, provider." The actual output (`command_helpers.dart:58-80`) shows: model ref, cwd, token count, message count, tool count, approval mode, auto-approve set. It does NOT show session ID or provider name explicitly.

**Decision: rewrite the contract to match code. Optionally add session ID to the output (small win for `/session copy` discoverability — they'd see the ID they're about to copy). Provider is already implicit in the model ref.**

### Add: `SlashSubcommandRouter` before `/session` grows more subcommands

Today `_sessionActionImpl` (lines 82-106) and `_runProviderCommandImpl` (lines 285-323) are two hand-rolled switch statements. They disagree on:

- Default subcommand (`/session` → info; `/provider` → list).
- Error message format (`Unknown subcommand "..."` vs `Usage: /provider [...]`).
- Aliases (`/provider remove` = `/provider rm`; `/session` has no alias support).
- Trailing-args handling.

Arg-autocomplete replicates the subcommand table in `arg_completers.dart` — a third copy. Three sources of truth will drift.

**Decision: add a small `SlashSubcommandRouter` abstraction in Phase 2:**

```dart
class SlashSubcommand {
  final String name;
  final String description;
  final List<String> aliases;
  final String Function(List<String> rest) handler;
}

class SlashSubcommandRouter {
  final String commandName;
  final List<SlashSubcommand> subs;
  final String Function(List<String> rest)? defaultHandler;
  String dispatch(List<String> args) { … }
  String usage() { … }
  List<SlashArgCandidate> candidates(String partial) { … }
}
```

Migrate `/session` and `/provider` to it in Phase 2. The router becomes the single source for execution, usage string, and autocomplete candidates — closes the three-copies-drift problem.

### Fix: callback explosion in `BuiltinCommands.create` contradicts the autocomplete plan precedent

`builtin_commands.dart:5-25` already takes 19 callbacks. Every new command added so far has added a callback. The sibling plan `2026-04-19-slash-arg-autocomplete.md` explicitly went the other direction (attach behavior via `_initCommands` closures after `BuiltinCommands.create` returns). This plan was about to add `startNewSession`, `forkSession`, `compactSession` — three more callbacks — reversing that precedent.

**Decision: freeze `BuiltinCommands.create`'s callback surface at its current 19. New commands register in `_initCommands` via closures that capture `this`, matching the autocomplete plan's convention. Add a code comment documenting this.**

### Fix: Phase 5 is mostly already done

`bin/glue.dart:47-49` already has `--resume` (alias `-r`) and `--continue`. Missing: `-c` abbr on `--continue` and the no-value picker semantics for `--resume`.

`dart:args` can't cleanly mix option-with-value and flag semantics on one flag. Keep `--resume <id>` as an option for direct jump; the picker is already the bare `/resume` in-TUI — no new CLI flag needed.

**Decision: Phase 5 shrinks to: add `abbr: 'c'` to `--continue` in `bin/glue.dart:48`, update website docs. That's it.**

### Fix: `sessionSubcommands` completer update belongs in Phase 2, not Phase 4

`arg_completers.dart:108-110` defines `sessionSubcommands` as `{'copy': ...}`. When Phase 2 adds `info` (and eventually `rename`, `delete`, `export`), this map must grow in lockstep or `/session ` tab produces stale candidates. The plan had this in Phase 4.

**Decision: move the `sessionSubcommands` update into Phase 2. Any new subcommand ships with its completer entry in the same commit. Phase 4 narrows to "completers for `/resume <query>` recent-session-id suggestions" (optional, defer if it requires disk reads per keystroke).**

### Fix: docs update co-located with visible command changes

Demoting `/models` changes `website/docs/using-glue/interactive-mode.md:13`. Any PR that hides a visible command must update the website in the same PR.

**Decision: add to the acceptance criteria. No silent doc drift.**

### Smaller clarifications

- **`/open` taxonomy**: not a leaf. It's a target-arg command with subcommand-like dispatch. Section 2's three-shape collapse was too aggressive — keep target-arg as its own shape.
- **`/new` vs `/clear` user intent framing**: if `/new` eventually ships, its help text should lead with intent, not implementation: `/clear` = "try a different direction in this conversation"; `/new` = "done with this topic, start fresh".
- **`plan_session_resume_consolidation.md` reference in this plan's header**: that file was moved to this one. The reference is internal memory, not a live doc.

## 10. Non-goals

- Rewriting the panel system. Existing panels stay.
- Adding a scripting surface (`/session new && /model anthropic/sonnet-4-7`). Out of scope.
- Unifying slash commands with CLI flags. Separate surface, separate plan.
- Internationalization of command names. English only.

## Notes

This plan supersedes `plan_session_resume_consolidation.md` (research file, moved to this location). The original proposed folding `/resume` into `/session` as an alias, with `/session` becoming the canonical browser.

**Two rounds of research changed the plan significantly:**

1. **External research** across 8 major coding agents (Claude Code, Amp, OpenCode, Codex, Copilot CLI, Droid, Gemini CLI, Aider) showed that **verb-first flat is the dominant convention for hot-path session actions**. Keeping `/resume` as a verb matches 5/8 surveyed agents; folding it into `/session` matches 1/8 (Gemini, which even then ships `/resume` as a top-level alias).
2. **Adversarial review** uncovered a shipped bug (`/clear` doesn't actually clear), a shipped-vocabulary collision (`/sessions` conflicts with `/open sessions`), a future-namespace collision (`/skill` would shadow per-skill admin), a false contract claim (the `/session` output doesn't match what the plan's acceptance criteria said), and a phasing error (`/new` isn't trivial — `SessionManager` is single-session).

**Net decisions after both rounds:**

- Keep `/resume` as top-level verb (don't fold).
- Formalize `/session` as inspection-only for the current session.
- Fix `/clear` bug in Phase 2.
- Add only `/continue` and `/models` as hidden aliases. Drop `/sessions` and `/skill`.
- Fold `/info` into `/session` — they already call the same code.
- Extract `SlashSubcommandRouter` before `/session` grows more subcommands.
- Register new commands via `_initCommands` closures, matching the sibling autocomplete plan's precedent. Freeze `BuiltinCommands.create`'s callback surface.
- Defer `/new` behind a `SessionManager.startNewSession()` design spike.
- Collapse Phase 5 — most CLI flag work is already done.

**Plan status:** ready to start Phase 2 when the `/clear` bugfix is prioritized. Phase 3 (new verbs) gated on Phase 2.5 (`/new` design spike).
