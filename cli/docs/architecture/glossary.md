# Glue — Glossary

Canonical terminology for the Glue CLI and web UI. Use these terms consistently in code, UI strings, documentation, and agent instructions.

## Core Concepts

### Project

A registered directory that workspaces run against. Typically a git repository, but can be any local directory. A project has:

- A **name** (display name, e.g. `glue`)
- A **path** (local filesystem path, e.g. `~/code/glue`)
- **Detected metadata** (default branch from git, if applicable)
- **Settings overrides** (per-project overrides for provider, model, base branch, workspace mode, branch prefix)

The sidebar groups workspaces by project. The project switcher filters visible workspaces.

### Workspace

The top-level unit of work. A workspace is an agent context that combines:

- A **directory** where the agent operates (project root or a git worktree)
- An **LLM provider and model** (e.g. `anthropic/claude-4-sonnet`)
- Optionally a **git branch** (created on demand or pre-existing)
- A **conversation history** (user messages, assistant responses, tool calls)
- A unique **ID** (e.g. `W-01`) used for resumption

A workspace is created via the "New Workspace" wizard and listed in the left sidebar. It has a lifecycle: **active → archived → deleted**.

UI strings: `+ new workspace`, `Archive workspace`, `Workspace W-01`.

### Worktree

A git worktree created for workspace isolation. When a workspace uses a worktree, the agent operates in a separate working directory branched from a base branch, avoiding conflicts with the main working tree.

Worktrees live under `.worktrees/` relative to the project root.

A workspace may or may not use a worktree — it can also run directly in the project root (on the current branch).

### Git Branch

An optional git branch associated with a workspace. Branches are **not created by default** — the workspace runs on the current HEAD. The user can opt in to creating a branch at workspace creation time, using a configurable prefix (e.g. `glue/`, `feature/`).

After a few messages, Glue may propose renaming the auto-generated branch to something descriptive (e.g. `feat/screen-buffer-diffing`), shown as a rename toast in the sidebar.

## Lifecycle

### Active

A workspace that is currently running or ready to accept messages. Shown with a green pulsing dot in the sidebar.

### Idle

A workspace that exists but has no active agent loop running. Shown with a gray dot.

### Archived

A workspace that has been stopped and hidden from the default sidebar view. Archived workspaces are preserved (logs, metadata) but no longer listed under "Active". When archiving a workspace with a worktree, the user may be prompted to delete the worktree (configurable via `onArchiveWorktree`: `ask` | `keep` | `delete`).

### Deleted

A workspace that has been permanently removed, along with its worktree (if any) and conversation history. This is destructive and irreversible.

## Settings Hierarchy

Settings resolve in layers (highest priority first):

1. **Workspace-level** — overrides set during creation (in the wizard)
2. **Project-level** — per-project overrides (in Settings → Per-Project Overrides)
3. **Global defaults** — user-wide defaults (in Settings → Global Defaults)
4. **App defaults** — hardcoded fallbacks

Overridable settings: `provider`, `model`, `isolationMode` (worktree vs project root), `baseBranch`, `branchPrefix`, `onArchiveWorktree`.

## CLI Resumption

### `glue --resume <ID>`

Resumes an existing workspace by ID. By default, `--resume` is **scoped to the current working directory** — it only lists/matches workspaces whose project path matches `cwd`. Use `--all` (or a key combo in the interactive session picker) to show workspaces across all projects.

When resuming a workspace from a different directory, Glue changes into the correct workspace directory (project root or worktree path) automatically.

> **Note:** cwd-scoping for `--resume` is planned but not yet implemented. Current behavior shows all workspaces regardless of cwd.

## UI Zones

### Rail (Left Sidebar)

Lists workspaces grouped by project. Contains the project switcher (with "All Projects" option), "New Workspace" button, workspace list (active/archived), and connection status footer with settings button.

### Viewport (Center)

The main conversation area. Contains the output zone (messages), overlay zone (command palette, popups), status bar (yellow), and input zone (prompt textarea with slash completion).

### Sidecar (Right Sidebar)

Workspace details panel. Contains:

- **Header** — "Workspace" label with workspace ID (click to copy)
- **Info section** — key-value definition list: root dir, worktree dir, branch, model, status, tokens, messages, started, last active
- **Tool Calls** — collapsible list of tool invocations with status indicators

### Status Bar

The yellow bar between output and input zones. Shows workspace name, branch, provider/model, token count, and relative time.

## Configuration

### `~/.glue/config.yaml`

User-edited global configuration file. See `docs/reference/config-yaml.md` for the full schema.

### `onArchiveWorktree`

Global setting controlling worktree cleanup when archiving a workspace:

- `ask` — prompt the user each time (default)
- `keep` — always keep the worktree
- `delete` — always delete the worktree (with safety check for uncommitted changes)

### `branchPrefix`

Global setting for the default git branch name prefix when creating a branch at workspace creation. Examples: `glue/`, `feature/`, `wip/`. Default: `glue/`.

### `isolationMode`

How a workspace is isolated from the project:

- `new-worktree` — create a new git worktree (recommended for git projects)
- `existing-worktree` — use an existing worktree
- `project-root` — run directly in the project root directory (no isolation)
