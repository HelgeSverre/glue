# Session Storage Format

Each session is stored under `~/.glue/sessions/<session-id>/`.

Managed by:

- `SessionStore` (`lib/src/storage/session_store.dart`)
- `SessionState` (`lib/src/storage/session_state.dart`)

## Directory Structure

```text
~/.glue/sessions/<session-id>/
├── meta.json
├── conversation.jsonl
└── state.json            # optional; created on first state mutation
```

## `meta.json`

Session metadata (`SessionMeta`).

```json
{
  "schema_version": 2,
  "id": "1740654600000-abc",
  "cwd": "/Users/helge/code/project",
  "model": "claude-sonnet-4-6",
  "provider": "anthropic",
  "start_time": "2026-02-27T10:30:00.000Z",
  "end_time": "2026-02-27T11:15:00.000Z",
  "forked_from": "1740650000000-xyz",
  "title": "Fix flaky shell test"
}
```

Supported fields include:

- Core: `schema_version`, `id`, `cwd`, `project_path`, `model`, `provider`, `start_time`, `end_time`, `forked_from`
- Git context: `worktree_path`, `branch`, `base_branch`, `repo_remote`, `head_sha`
- Display: `title`, `tags`
- PR lifecycle: `pr_url`, `pr_status`
- Metrics: `token_count`, `cost`
- Summary: `summary`

## `conversation.jsonl`

Append-only JSON-lines event log.

Each line contains:

- `timestamp` (UTC ISO-8601)
- `type` (event type)
- event payload fields

Common event types:

- `user_message` with `text`
- `assistant_message` with `text`
- `tool_call` with `id`, `name`, `arguments`
- `tool_result` with `call_id`, `content`
- `title_generated` with `title`

Glue may append additional event types over time.

## `state.json`

Mutable per-session runtime state.

```json
{
  "version": 1,
  "docker": {
    "mounts": [{ "host_path": "/Users/helge/code/shared", "mode": "rw" }]
  },
  "browser": {
    "container_ids": ["abc123"]
  }
}
```

Fields:

- `version`: state schema version
- `docker.mounts[]`: serialized `MountEntry` records
- `browser.container_ids[]`: browser container identifiers used by browser backends

Unknown future `version` values are ignored safely by current clients.
