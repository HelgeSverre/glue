# `/worktree` Command — Design Document

## Overview

Git worktree management integrated into the Glue CLI. Allows creating, switching between, and removing worktrees stored in `.worktrees/` inside the project root. When switching, the agent's context is fully reset (cwd, system prompt, conversation) so it operates cleanly in the new workspace.

## Subcommands

| Command                   | Behavior                                                                                                                                                                                                                                                    |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/worktree <name>`        | If `.worktrees/<name>` exists → switch into it. Otherwise → create worktree + branch `wt/<name>` from current HEAD, add `.worktrees/` to `.gitignore` if needed, switch into it. Confirms if currently streaming or if current cwd has uncommitted changes. |
| `/worktree:list`          | Parse `git worktree list --porcelain`, show name/branch/status, mark current with `▸`.                                                                                                                                                                      |
| `/worktree:remove <name>` | Dirty check → confirm. If cwd is inside target → confirm switch to repo root. Runs `git worktree remove` (+ `--force` if confirmed), then `git branch -D wt/<name>`.                                                                                        |

## Repo Root Discovery

Derived from `git rev-parse --git-common-dir`:

- If result is `.git` (relative) → cwd is the main repo root, use `git rev-parse --show-toplevel`
- Otherwise → strip `/.git` suffix from the absolute path to get the main repo root

Stored as a lazily-resolved value on first `/worktree` invocation. Works correctly from inside any linked worktree.

## Branch Naming

- Default: `wt/<sanitized-name>`
- Sanitization: trim, replace `[/\\ :*?"<>|#]` → `-`, collapse repeated `-`, strip leading/trailing `-`
- If branch already checked out in another worktree → error with helpful message
- If branch exists but not checked out → reuse it (switch, don't create)

## Switch Flow

When switching from one worktree (or main repo) to another:

1. If `_mode != idle` → show confirm modal: "Cancel current operation and switch?"
2. Check `git status --porcelain` in current cwd → if dirty, confirm: "Uncommitted changes in current worktree. Switch anyway? (Changes remain in the worktree.)"
3. Update `Directory.current` to the worktree path
4. Update `App._cwd` (refactored to be mutable)
5. Rebuild system prompt via `Prompts.build(cwd: worktreePath)` — re-scans AGENTS.md/CLAUDE.md
6. Create fresh `LlmClient` with new system prompt, assign to `agent.llm`
7. Call `agent.reset()` (new method) — clears `_conversation`, `_pendingToolResults`, resets `tokenCount`
8. Update `AgentManager.systemPrompt` for subagent spawning
9. Keep TUI transcript blocks (user can scroll back to see prior work)
10. Insert system block: `"Switched to worktree <name> on branch wt/<name>"`
11. Re-render (status bar shows new cwd)

### What does NOT reset

- Slash command registry
- Autocomplete / @file hint state
- Terminal / layout state
- Session store (continues logging to same session — the switch is an event)

## Remove Flow

1. Resolve target path: `<repoRoot>/.worktrees/<name>`
2. If cwd is inside target → confirm: "You are in this worktree. Switch to repo root and remove?"
3. `git -C <target> status --porcelain` → if dirty, confirm: "Force remove? Uncommitted changes will be lost."
4. If was inside target: execute switch flow to repo root first
5. `git worktree remove [--force] <targetPath>`
6. `git branch -D wt/<name>` (best-effort, don't error if branch already gone)
7. `git worktree prune` (cleanup stale metadata)
8. Insert system block: `"Removed worktree <name>"`

## .gitignore Management

On first worktree creation:

1. Check if `.gitignore` exists at repo root
2. If exists, read contents and check for `/.worktrees/` or `.worktrees/` (line by line)
3. If not found → append `/.worktrees/\n` to existing file
4. If no `.gitignore` → create with `/.worktrees/\n`
5. Silent operation — no user confirmation needed

## List Output Format

```
Worktrees:
  ▸ my-feature    wt/my-feature    3 commits ahead
    fix-bug       wt/fix-bug       clean
    experiment    wt/experiment    2 uncommitted changes
  ▸ = current
```

Parsed from `git worktree list --porcelain`. For each worktree under `.worktrees/`:

- Name: directory name under `.worktrees/`
- Branch: from the `branch refs/heads/...` line
- Status: quick `git -C <path> status --porcelain` + `git rev-list --count main..HEAD`

## AgentCore.reset()

New method added to `AgentCore`:

```dart
void reset() {
  _conversation.clear();
  for (final completer in _pendingToolResults.values) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Agent reset while awaiting tool result'),
      );
    }
  }
  _pendingToolResults.clear();
  tokenCount = 0;
}
```

## File Changes

| File                               | Change                                                                                                              |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `lib/src/commands/worktree.dart`   | **New** — Git operations (create/list/remove/prune), branch sanitization, gitignore management, repo root discovery |
| `lib/src/agent/agent_core.dart`    | **Modified** — add `reset()` method                                                                                 |
| `lib/src/app.dart`                 | **Modified** — `_cwd` mutable, `/worktree` slash commands wired, `_switchWorktree()` helper method                  |
| `lib/glue.dart`                    | **Modified** — export new types                                                                                     |
| `test/commands/worktree_test.dart` | **New** — branch sanitization, gitignore append logic, porcelain list parsing                                       |

## Edge Cases

| Situation                                                            | Handling                                                                            |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Not in a git repo                                                    | Error: "Not a git repository. Worktrees require git."                               |
| `.worktrees/<name>` already exists (as directory but not a worktree) | Error: "Directory exists but is not a git worktree."                                |
| Branch `wt/<name>` already checked out in another worktree           | Error: "Branch already checked out in .worktrees/<other>. Choose a different name." |
| Remove while streaming                                               | Cancel agent first (with confirmation), then proceed with remove flow               |
| Name is empty or invalid after sanitization                          | Error: "Invalid worktree name."                                                     |
| Repo has no commits yet                                              | Error: "Repository has no commits. Create an initial commit first."                 |
