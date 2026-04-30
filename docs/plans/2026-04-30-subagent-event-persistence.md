# Subagent Event Persistence Plan

> Status: proposed
> Date: 2026-04-30
> Owner: implementation agent

## Goal

Persist subagent activity into `conversation.jsonl` so that:

1. session resume can re-render nested subagent transcripts (today they vanish)
2. `/share` exports show subagent activity (today the share builder ignores it on purpose)
3. ACP clients see subagent activity end-to-end (today the ACP mapper is wired but nothing emits)

This is a small, self-contained change — but it touches every layer, so it's worth its own plan.

## Current state — verified 2026-04-30

### What exists

- **Typed events in `glue_core`** (`packages/glue_core/lib/src/session_event.dart`):
  - `SubagentSpawnedEvent { ..., childId, ... }`
  - `SubagentEventForwardedEvent { ..., childId, inner: SessionEvent }`
  - `SubagentCompletedEvent { ..., childId, ... }`
- **ACP mapper** in `packages/glue_server/lib/src/acp/event_mapping.dart` already pattern-matches all three: `SubagentEventForwardedEvent` unwraps to its inner event; spawn/completion currently map to `null` (placeholder for richer ACP framing later).
- **Share builder test** explicitly asserts the current contract: `ignores raw subagent-like events until a persisted schema exists` (`cli/test/share/share_transcript_builder_test.dart`).
- **HTML/Markdown renderers** already have `share-entry-subagent-group` and `share-entry-subagent-message` classes plus `share-children` nesting structure — the renderer is *ready to display subagent nesting*; the data just doesn't reach it.

### What is missing

- **`AgentManager`** (`packages/glue_harness/lib/src/agent/agent_manager.dart`):
  - exposes `Stream<SubagentUpdate>` — a UI-shaped wrapper carrying `task`, `index`, `total`, plus a raw `AgentEvent`.
  - has **no path to the parent session's persistence**. It never calls `logEvent`, never instantiates `SubagentSpawnedEvent`, etc.
- **CLI** (`cli/lib/src/app/subagent_updates.dart`):
  - subscribes to `manager.updates` and renders `_subagentGroups` as in-memory `_ConversationEntry.subagentGroup` blocks.
  - **does not persist anything**. Subagent activity is purely live UI state — gone on restart.
- **ACP server**:
  - has the mapper but receives nothing because no one emits.
- **Share builder** (`packages/glue_harness/lib/src/share/share_transcript_builder.dart`):
  - normalizer only knows `user_message`/`assistant_message`/`tool_call`/`tool_result` (`session_event_normalizer.dart`). Subagent JSON would be ignored even if present.

### Important architectural context

`SessionStore.logEvent` is **currently untyped**: `void logEvent(String type, Map<String, dynamic> data)`. The typed `SessionEvent` classes in `glue_core` are a forward-looking contract used today only by the ACP boundary, **not** by the persistence layer. Persistence happens via free-form JSON dicts written by surface code (CLI calls `app._sessionManager.logEvent('user_message', {...})`).

That means subagent persistence has two reasonable shapes:

- **Option A (small, today-shaped):** add `'subagent_spawned'` / `'subagent_event'` / `'subagent_completed'` JSON variants to `logEvent`. The harness emits them. The normalizer learns them. The share builder produces nested groups. ACP gets typed events by reconstructing from JSON OR from a parallel typed-event emit.
- **Option B (typed-events-as-source-of-truth):** make `SessionStore` accept typed `SessionEvent`s and own JSON serialization. The harness emits typed events. Storage, replay, ACP, and share all consume them.

Option B is the right long-term shape (it matches the harness-layers contract from `2026-04-29-harness-layers.md`), but it's a much larger refactor — every existing `logEvent` call in `cli/lib/src/app/...` would need typed equivalents. **This plan picks Option A**, with a clean enough JSON shape that Option B becomes a mechanical lift later.

## Proposed approach (Option A)

### 1. Give `AgentManager` a parent session sink

**File:** `packages/glue_harness/lib/src/agent/agent_manager.dart`

Add an optional `void Function(String type, Map<String, dynamic> data) onPersistEvent` constructor parameter. Surfaces wire it to `parent._sessionManager.logEvent`. Keep `Stream<SubagentUpdate> updates` for live UI rendering (it stays useful for the CLI's transient render path; ACP doesn't need it).

```dart
AgentManager({
  // ...existing fields...
  this.onPersistEvent,
});

final void Function(String type, Map<String, dynamic> data)? onPersistEvent;
```

### 2. Emit JSON for spawn / forwarded / completion

**File:** `packages/glue_harness/lib/src/agent/agent_manager.dart`

In `spawnSubagent`:

- Generate a stable `subagentId` (use `SubagentId` extension type from `glue_core/ids.dart`, e.g. `SubagentId('sub-${nanoid8}')`).
- On spawn, before calling the runner:

  ```dart
  onPersistEvent?.call('subagent_spawned', {
    'subagent_id': id.value,
    'parent_subagent_id': parentId?.value,  // null for top-level
    'task': task,
    'depth': currentDepth,
    'index': index,
    'total': total,
    'model': ref.toString(),
  });
  ```

- For each `event` from the runner's `onEvent`, before dispatching to `_updateController`:

  ```dart
  onPersistEvent?.call('subagent_event', {
    'subagent_id': id.value,
    'inner': _serializeAgentEvent(event),
  });
  ```

- On completion (success or error path):

  ```dart
  onPersistEvent?.call('subagent_completed', {
    'subagent_id': id.value,
    'error': errorString,  // null on success
  });
  ```

`_serializeAgentEvent` converts the existing `AgentEvent` variants (`AgentTextDelta`, `AgentToolCall`, `AgentToolResult`, `AgentToolCallPending`, `AgentDone`, `AgentError`) into a JSON map. This is small — those types are already pattern-matched in several places.

### 3. Wire the sink in CLI surface

**File:** `cli/lib/src/app.dart` (where `_manager` is constructed)

```dart
_manager = AgentManager(
  // ...existing...
  onPersistEvent: (type, data) => _sessionManager.logEvent(type, data),
);
```

ACP server already constructs its own `Glue` via `ServiceLocator`; the same wiring applies.

### 4. Teach the normalizer about subagent events

**File:** `packages/glue_harness/lib/src/session/session_event_normalizer.dart`

Add a new kind:

```dart
enum NormalizedSessionEventKind {
  user, assistant, toolCall, toolResult,
  subagentSpawned, subagentEvent, subagentCompleted,
}
```

Add corresponding factories on `NormalizedSessionEvent` carrying:

- `subagentId`
- `parentSubagentId`
- `task` (spawn only)
- `inner: NormalizedSessionEvent?` (forwarded only — recursively normalized from the `inner` JSON)
- `error: String?` (completed only)

Extend the `switch (type)` in `normalizeSessionEvent`:

```dart
case 'subagent_spawned': ...
case 'subagent_event':
  final inner = event['inner'] as Map<String, dynamic>?;
  final innerNormalized = inner != null ? normalizeSessionEvent(inner) : null;
  ...
case 'subagent_completed': ...
```

### 5. Build nested subagent groups in the share builder

**File:** `packages/glue_harness/lib/src/share/share_transcript_builder.dart`

Replace the existing `build()` loop with a stack-based walker:

- Maintain a stack of `(subagentId, ShareEntry group)`.
- On `subagentSpawned`: push a new `ShareEntry(kind: ShareEntryKind.subagentGroup, subagentId: id, text: task, children: [])` onto the active parent (top-of-stack or root).
- On `subagentEvent`: normalize the inner kind to a `ShareEntryKind.subagentMessage` / nested `subagentGroup` as appropriate; append to the active subagent's `children`.
- On `subagentCompleted`: pop the stack frame.

Promote the existing `cli/test/share/share_transcript_builder_test.dart` `ignores raw subagent-like events until a persisted schema exists` case — replace it with a test that builds nested groups from real `subagent_spawned`/`subagent_event`/`subagent_completed` JSON rows.

### 6. Surfaces consume the new events

**CLI (`cli/lib/src/app/subagent_updates.dart` + session resume path):**

- Live mode keeps the existing `_handleSubagentUpdateImpl(SubagentUpdate)` for in-flight rendering — no change needed; persistence is a parallel sink, not a replacement.
- Resume path (`cli/lib/src/app/session_runtime.dart` or wherever JSONL is replayed into `_blocks`): when normalizer emits a `subagentSpawned`/`subagentEvent`/`subagentCompleted` chain, reconstruct `_SubagentGroup`s and append `_ConversationEntry.subagentGroup(group)` to `_blocks`. This is straightforward because the in-memory shape already exists.

**ACP server:**

- The ACP mapper currently maps `SubagentSpawnedEvent` → `null` and unwraps `SubagentEventForwardedEvent`. Once the harness emits typed events on the session stream (see next phase), the mapper's existing pattern-match works without changes.
- For Option A (JSON-only), the typed-event emit happens in a small adapter inside `glue_server`'s session attach path: the server reads JSONL rows and reconstructs `SubagentSpawnedEvent` / `SubagentEventForwardedEvent` / `SubagentCompletedEvent` for the in-memory `Stream<SessionEvent>`. This is a minor extension to whatever already converts JSONL → `SessionEvent` in the server.

If `glue_server` does not yet have a JSONL → typed-`SessionEvent` reconstructor (likely it doesn't, since typed-event persistence is the bigger Option B work), then the ACP path remains best-effort until that lands. Document this gap.

### 7. Tests

#### `packages/glue_harness/test/agent/agent_manager_test.dart` (new — or under `packages/glue_harness/test/` once that tree exists)

- Spawning a subagent invokes `onPersistEvent` with `'subagent_spawned'` carrying the right id/task/depth.
- Each subagent `AgentEvent` produces a `'subagent_event'` row with the inner event serialized.
- Completion produces `'subagent_completed'`.
- Errors produce `'subagent_completed'` with `error` populated.
- Parallel spawns produce distinct subagent ids and interleaved rows.

#### `packages/glue_harness/test/session/session_event_normalizer_test.dart`

- Round-trips `'subagent_spawned'` / `'subagent_event'` / `'subagent_completed'` JSON to `NormalizedSessionEvent` of the right kind.
- Recursively normalizes inner events.
- Skips malformed/empty rows safely.

#### `packages/glue_harness/test/share/share_transcript_builder_test.dart` (migrated from `cli/test/share/`)

- Builds nested subagent groups from real persisted JSON (replacing the `ignores raw subagent-like events…` case).
- Handles a parent agent with two parallel subagents.
- Handles a subagent that spawns its own subagent (nesting).

#### `cli/test/app/session_resume_subagent_test.dart` (new)

- Resuming a session with persisted subagent events reconstructs `_SubagentGroup` blocks correctly.

#### `packages/glue_server/test/acp/subagent_mapping_test.dart` (extend if exists)

- Once the JSONL → `SessionEvent` reconstructor lands: typed events flow through the existing mapper unchanged.

## Migration / housekeeping

- **Test location:** the `packages/glue_harness/test/` tree does not exist yet. This plan is a good time to establish it. Move share tests at the same time (the share plan already calls for this).
- **Subagent id minting:** use the typed `SubagentId` extension type from `glue_core/ids.dart` rather than raw strings everywhere.
- **`SubagentUpdate` keeping vs renaming:** keep it. It's a transient UI-only carrier with `task`/`index`/`total` framing — useful for the CLI's live-rendering grouping logic. It does not need to disappear.

## Acceptance criteria

This plan closes when:

1. `AgentManager` accepts an `onPersistEvent` sink and emits `subagent_spawned`, `subagent_event`, `subagent_completed` JSON rows for every subagent.
2. The CLI wires that sink to `_sessionManager.logEvent`.
3. The session-event normalizer recognizes the three new types and recursively normalizes inner events.
4. The share transcript builder produces nested `subagentGroup` / `subagentMessage` entries from real persisted JSON.
5. CLI session resume reconstructs subagent groups visually when the session is reopened.
6. The existing `'ignores raw subagent-like events…'` test is replaced with a positive nested-group test.
7. (Optional in the same PR) ACP server reconstructs typed `SubagentSpawnedEvent` / `SubagentEventForwardedEvent` / `SubagentCompletedEvent` for streaming clients. If deferred, document the gap.

## Out of scope

- **Migrating `SessionStore.logEvent` to consume typed `SessionEvent`s** — that's the larger Option B refactor referenced in the harness-layers plan and should be its own PR. The JSON shape introduced here is structured well enough to feed a future typed-event source of truth without re-shaping persisted data.
- **A new `/subagents` slash command** — out of scope. The data is enough; UX additions can come later.

## Why this is small

Five files in the harness, one in the CLI, plus tests. The renderers are already ready. The ACP mapper is already ready. The data model is already defined in `glue_core`. The remaining work is just wiring the persistence pipe.
