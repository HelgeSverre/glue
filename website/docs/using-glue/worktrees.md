# Worktrees

Git worktrees let you run multiple Glue sessions in parallel, each in its own isolated working copy. No stashing, no conflicts between sessions.

## How It Works

A git worktree is a full checkout of your repository on a separate branch. All worktrees share the same `.git` directory, so commits made in one worktree are immediately visible across all of them.

1. **Isolated checkouts** — each worktree has its own branch, so there is no need to stash or switch branches
2. **Shared history** — all worktrees reference the same `.git` directory; commits, tags, and refs stay in sync
3. **Per-session context** — each Glue session has its own conversation history and tool state
4. **Auto cleanup** — Glue can merge, create a PR, or clean up the worktree when done

## Setup

Create worktrees for parallel work, then launch a Glue session in each:

```bash
# Create worktrees for parallel work
cd worktree/feat/auth && glue
cd worktree/fix/crash && glue
cd worktree/refactor/db && glue
```

Each session operates independently with its own branch, file state, and conversation.

## Common Workflows

### Feature + Hotfix

Keep feature work running while fixing a bug in a separate worktree. The hotfix can be merged to `main` without touching your in-progress feature branch.

### Parallel Features

Run 3 sessions on 3 features simultaneously. Each agent works on its own branch with no interference from the others.

### Explore & Commit

Create a throwaway worktree to experiment freely. If the experiment works, merge it. If not, delete the worktree with no cleanup needed.

### Model Comparison

Run the same task with different models in different worktrees. Compare the results side by side to evaluate quality, speed, or cost.

::: tip
Worktrees are especially useful for long-running agent tasks. You can start a feature in one worktree and continue working manually or with another agent session in a different worktree.
:::
