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
  "schema_version": 5,
  "id": "1740654600000-abc",
  "glue_version": "0.9.0",
  "transcript_schema_version": 1,
  "cwd": "/Users/helge/code/project",
  "model": "claude-sonnet-4-6",
  "provider": "anthropic",
  "start_time": "2026-02-27T10:30:00.000Z",
  "end_time": "2026-02-27T11:15:00.000Z",
  "termination_status": "completed",
  "forked_from": "1740650000000-xyz",
  "title": "Fix flaky shell test"
}
```

Supported fields include:

- Core: `schema_version`, `id`, `glue_version`, `transcript_schema_version`, `cwd`, `project_path`, `model_ref`, `start_time`, `end_time`, `termination_status`, `forked_from`
- Git context: `worktree_path`, `branch`, `base_branch`, `repo_remote`, `head_sha`
- Display: `title`, `tags`
- PR lifecycle: `pr_url`, `pr_status`
- Metrics: `token_count`, `cost`
- Summary: `summary`

## `conversation.jsonl`

Append-only JSON-lines event log.

Newly written lines conform to
[`schemas/session/conversation-event-v1.schema.json`](../../schemas/session/conversation-event-v1.schema.json).
Legacy unversioned lines remain readable and are not rewritten. Each v1 line
contains:

- `schema_version` (currently `1`)
- `event_id` and `session_id`
- `timestamp` (UTC ISO-8601)
- `type` (event type)
- monotonic `sequence`
- `turn_id` and `request_id` when available
- event payload fields

Common event types:

- `user_message` with `text`
- `assistant_message` with `text`
- `assistant_thinking` with `text` when reasoning retention is enabled
- `tool_call` with `id`, `name`, `arguments`
- `tool_result` with `call_id`, `content`
- `title_generated` with `title`

Glue may append additional event types over time.

The authoritative metadata contract is
[`schemas/session/meta-v5.schema.json`](../../schemas/session/meta-v5.schema.json).
Run `glue session validate <session-id-or-path>` to validate one session, or
`glue session validate --all` to validate the complete local archive.

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
