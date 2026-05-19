# Session Storage Format

Each session is stored under `~/.glue/sessions/<session-id>/`.

Managed by:

- `SessionStore` (`packages/glue_harness/lib/src/storage/session_store.dart`)
- `SessionState` (`packages/glue_harness/lib/src/storage/session_state.dart`)

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

### Runtime command events (in-process only)

The `SessionEvent` sealed class in
`packages/glue_core/lib/src/session_event.dart` also defines a runtime
command family used by cloud-runtime executors (Phase 0–1 of the cloud
runtimes correctness work):

- `RuntimeCommandStartedEvent` — `runtimeId`, `commandId`, `command`,
  `runtimeCwd`, optional `sessionScopedId`
- `RuntimeCommandOutputEvent` — `commandId`, `stream`, `text`
- `RuntimeCommandCompletedEvent` — `commandId`, `exitCode`, `duration`,
  optional `stdoutBytes` / `stderrBytes`
- `RuntimeCommandFailedEvent` — `commandId`, `errorType`, `message`
  (transport / runtime-level failure, not a non-zero exit)
- `RuntimeCommandCancelledEvent` — `commandId` (timeout, `/cancel`, shutdown)

These are emitted by the Docker / Daytona / Sprites / Modal executors via
the in-process `RuntimeEventSink` so the TUI and other in-session
subscribers can observe them. They are **not currently written to
`conversation.jsonl`** — the persistent log still only contains the
common event types above. Persistence is tracked separately under the
session JSONL schema work.

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
