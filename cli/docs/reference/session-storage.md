# Session Storage Format

Each session is stored in `~/.glue/sessions/<session-id>/` with three files. Managed by `SessionStore` (`lib/src/storage/session_store.dart`).

## Directory Structure

```
~/.glue/sessions/<uuid>/
├── meta.json          # Session identity (written at creation, updated on close)
├── conversation.jsonl # Conversation log (append-only)
└── state.json         # Mutable runtime state (created on first write)
```

## `meta.json` — Session Identity

Written once when the session starts. Updated with `end_time` on close.

```json
{
  "schema_version": 2,
  "id": "1740654600000-abc",
  "cwd": "/Users/helge/code/myproject",
  "project_path": "/Users/helge/code/myproject",
  "model": "claude-sonnet-4-6",
  "provider": "anthropic",
  "start_time": "2026-02-27T10:30:00.000Z",
  "end_time": "2026-02-27T11:15:00.000Z",
  "worktree_path": "/Users/helge/code/myproject/.worktrees/fix-login",
  "branch": "glue/fix-login",
  "base_branch": "main",
  "repo_remote": "git@github.com:helgesverre/myproject.git",
  "head_sha": "a1b2c3d",
  "title": "Fix login bug",
  "tags": ["auth", "bugfix"],
  "pr_url": "https://github.com/helgesverre/myproject/pull/42",
  "pr_status": "open",
  "token_count": 15420,
  "cost": 0.23,
  "summary": "Fixed authentication token expiry check in login flow"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | int | Metadata schema version (current: 2) |
| `id` | string | Session identifier |
| `cwd` | string | Working directory at session start (launch directory) |
| `project_path` | string? | Project root directory (git root or registered dir) |
| `model` | string | LLM model used |
| `provider` | string | LLM provider name |
| `start_time` | ISO 8601 | Session creation timestamp (UTC) |
| `end_time` | ISO 8601? | Session close timestamp (UTC, null if active) |
| `worktree_path` | string? | Git worktree path if session is isolated |
| `branch` | string? | Current git branch |
| `base_branch` | string? | Base branch for worktree/PR |
| `repo_remote` | string? | Git remote URL |
| `head_sha` | string? | Commit SHA at session start |
| `title` | string? | Display title (user-set or auto-generated) |
| `tags` | string[]? | User-defined tags for grouping |
| `pr_url` | string? | GitHub PR URL |
| `pr_status` | string? | PR lifecycle status (open/merged/closed) |
| `token_count` | int? | Total tokens used |
| `cost` | double? | Estimated cost in USD |
| `summary` | string? | Auto-generated work summary |

> **Backward compatibility:** Schema version 1 files (without `schema_version`) are read with permissive defaults. All new fields are optional.

## `conversation.jsonl` — Conversation Log

Append-only. One JSON object per line, each representing a timestamped event.

```jsonl
{"timestamp":"2026-02-27T10:30:01.000Z","type":"user_message","text":"Fix the login bug"}
{"timestamp":"2026-02-27T10:30:02.000Z","type":"assistant_chunk","text":"I'll look into..."}
{"timestamp":"2026-02-27T10:30:03.000Z","type":"tool_call","tool":"read_file","args":{"path":"src/auth.dart"}}
{"timestamp":"2026-02-27T10:30:04.000Z","type":"tool_result","tool":"read_file","result":"..."}
```

### Event Types

| Type              | Fields           | Description                                 |
| ----------------- | ---------------- | ------------------------------------------- |
| `user_message`    | `text`           | User input                                  |
| `assistant_chunk` | `text`           | Assistant response text                     |
| `tool_call`       | `tool`, `args`   | Tool invocation by the agent                |
| `tool_result`     | `tool`, `result` | Tool execution result                       |
| `system`          | `text`           | System messages (job started, errors, etc.) |

## `state.json` — Session Runtime State

Mutable state scoped to the session. Created on first write. Missing file = empty/default state.

```json
{
  "version": 1,
  "docker": {
    "mounts": [
      {
        "host_path": "/Users/helge/code/shared-libs",
        "mode": "rw",
        "added_at": "2026-02-27T10:35:00.000Z"
      },
      {
        "host_path": "/Users/helge/data/fixtures",
        "mode": "ro",
        "added_at": "2026-02-27T10:40:00.000Z"
      }
    ]
  }
}
```

### Schema

| Field                       | Type     | Description                            |
| --------------------------- | -------- | -------------------------------------- |
| `version`                   | int      | Schema version (currently `1`)         |
| `docker.mounts`             | list     | Session-scoped whitelisted directories |
| `docker.mounts[].host_path` | string   | Absolute, canonicalized host path      |
| `docker.mounts[].mode`      | string   | `rw` (default) or `ro`                 |
| `docker.mounts[].added_at`  | ISO 8601 | When the mount was added               |

### Mount Resolution

Final mount list is computed by merging (deduplicated by canonical path):

1. CWD — always mounted as `/work` (rw), also at its absolute path
2. `config.yaml` → `docker.mounts` — persistent whitelist
3. `state.json` → `docker.mounts` — session-scoped whitelist

Session mounts override config mounts for the same path (e.g., config says `:ro` but session escalates to `rw`).

### Lifecycle

- **Created:** On first session-scoped state mutation (e.g., user approves a directory).
- **Updated:** On each state change (e.g., `/mount add /path`).
- **Read:** On session resume to restore whitelisted directories.
- **Deleted:** When the session directory is removed.
