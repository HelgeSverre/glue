# Bugs & Papercuts

Minor issues to batch-fix later.

---

### `/model` command doesn't update `_config`

**File:** `lib/src/app.dart` (line ~396)

`/model` swaps the `LlmClient` on `agent.llm` and updates the `_modelName` display string, but never updates `_config`. Anything that later reads `_config.model` will see the stale original model name. Low risk today since most display paths use `_modelName`, but will bite if `_config` gets used more broadly (e.g. session metadata, subagent spawning inheriting parent model).

**Fix:** Either update `_config` to a new `GlueConfig` with the new model, or derive `_modelName` from `_config` directly so there's a single source of truth.

---

### `/skills` command uses stale skills data

**File:** wherever `/skills` is handled (likely `lib/src/commands/` or `lib/src/app.dart`)

The `/skills` command displays the list of available skills, but the skills are loaded once at startup and not reloaded when the command is triggered. If the user adds, removes, or edits a skill file in `~/.glue/skills/` during a session, `/skills` will show stale data — missing new skills, showing deleted ones, or displaying outdated descriptions.

**Fix:** Re-scan the skills directory on every `/skills` invocation instead of reading from the cached in-memory list.

---

### Bash mode has no shell tab-completion

**File:** `lib/src/app.dart` (bash mode), `lib/src/input/line_editor.dart`

When in bash mode (`!` prefix), typing a command and pressing Tab does nothing useful — `LineEditor` emits `InputAction.requestCompletion` but the app only wires that to `SlashAutocomplete` / `AtFileHint`. The user's shell completions (commands, flags, paths, git branches, etc.) are completely unavailable because we own the input buffer — the command never passes through a real shell until submit.

This is noticeable for anyone used to shell autocomplete (i.e. everyone).

**Context — how shells expose completions:**

| Shell | Mechanism | Difficulty |
|-------|-----------|------------|
| **bash** | `compgen` builtin: `compgen -c "git"` (commands), `compgen -f "lib/"` (files), `compgen -d` (dirs). For command-specific completions, need to source `bash-completion` lib, set `COMP_WORDS`/`COMP_CWORD`/`COMP_LINE`/`COMP_POINT` env vars, invoke the registered completion function, read `COMPREPLY` array. | Medium — works but command-specific completions (e.g. `git checkout <branch>`) require loading the full bash-completion framework. |
| **zsh** | No simple one-shot API. Completions are deeply tied to the ZLE (Zsh Line Editor) widget system. Programmatic access requires `zpty` (pseudo-terminal module): spawn a `zsh -f -i`, send the partial line + `\t`, capture output. This is how `fzf-tab` and similar tools work. Complex, brittle, and zsh-version-sensitive. | Hard — the zpty approach works but is fragile. |
| **fish** | `complete -C "git sta"` — purpose-built API, returns completions with descriptions. By far the cleanest interface. | Easy — one command, clean output. |

**Current architecture relevant to a fix:**

- `ShellConfig` in `lib/src/shell/shell_config.dart` already knows the user's shell executable and mode (interactive/login/non-interactive). The `_baseName` getter can distinguish bash/zsh/fish/pwsh.
- `LineEditor` already emits `InputAction.requestCompletion` on Tab.
- The app already has the overlay pattern (`SlashAutocomplete`, `AtFileHint`) for showing completion candidates.

**Possible approaches:**

1. **Simple: file/command completion only** — Use `compgen -f` (files) and `compgen -c` (commands) via bash regardless of user shell. Covers ~70% of use cases. Doesn't handle command-specific completions (git branches, docker containers, etc.).

2. **Medium: shell-aware `compgen` bridge** — Detect shell from `ShellConfig`. For bash, use `compgen` + source bash-completion. For fish, use `complete -C`. For zsh, fall back to approach 1 (or attempt zpty). New `ShellCompleter` class that takes a partial line and returns candidates.

3. **Full: pseudo-terminal passthrough** — Spawn a persistent interactive shell via `zpty`/`pty`, send partial input + tab, parse the response. Most accurate but extremely complex — need to handle ANSI output parsing, timing, and shell-specific escape sequences.

**Recommended:** Start with approach 2 — a `ShellCompleter` that uses `fish complete -C` for fish users and `bash -c 'compgen ...'` for everyone else. Wire it into the existing overlay system. Accept that zsh-specific completions (custom `_git` etc.) won't work initially.

**Relevant files for implementation:**
- `lib/src/shell/shell_config.dart` — already has shell detection
- `lib/src/input/line_editor.dart` — emits Tab as `requestCompletion`
- `lib/src/app.dart` lines ~648–660 — bash mode input handling
- `lib/src/ui/slash_autocomplete.dart` — pattern to follow for the overlay
