# Fix nested-looking parallel subagents in `/share` HTML export

## Context

Sharing a session that spawned three parallel subagents (`spawn_parallel_subagents`) renders them in the HTML export as a 3-deep cascade — subagent #2 nested inside #1, #3 nested inside #2 — and every subsequent event in the conversation also appears nested under #3. They are not actually nested; they ran in parallel.

Reproduced session: `~/.glue/sessions/1778140738915-hm/conversation.jsonl`. Raw rows confirm three parallel spawns at the **same microsecond**, all `depth=0`, with `index/total = 0/3, 1/3, 2/3`, and `subagent_completed` rows arriving over a minute later in spawn order. The output is `cli/glue-session-1778140738915-hm.html` — see entries #22 → #23 → #24 in the rendered cascade and the outline at the bottom (every entry from #23 onward marked `is-nested`).

## Root cause

`packages/glue_harness/lib/src/share/share_transcript_builder.dart` correlates persisted subagent events to groups using a **stack** of open subagents (`final stack = <_OpenGroup>[]`). The stack model assumes LIFO ordering — i.e. that subagents are strictly nested in time. That is true for one subagent spawning another (the parent must still be open when the child starts), but **false** for parallel siblings spawned by the same agent.

Trace for the reproducer (3 parallel spawns from the top-level agent):

1. `subagent_spawned A` → `stack=[A]`. A is appended at top level. ✓
2. `subagent_spawned B` → `appendEntry` looks at `stack.last == A` and **appends B as a child of A**. `stack=[A, B]`. ✗
3. `subagent_spawned C` → appended as a child of B. `stack=[A, B, C]`. ✗
4. Interleaved `subagent_event` rows for A and B: the guard
   `if (stack.isEmpty || stack.last.subagentId != event.subagentId) continue;`
   silently drops every event whose `subagent_id` isn't the top of the stack, so **all of A's and B's streamed activity is discarded** until C completes.
5. `subagent_completed A` arrives first: `stack.last.subagentId (C) != A`, so the pop is a no-op. Same for `complete B`. Only `complete C` actually pops.
6. After C pops, `stack=[A, B]` — A and B are still open forever (their completions are already past). Every later top-level event (assistant turns, tool calls, the user's follow-up message) gets appended under B, producing the long `is-nested` tail in the outline.

So this is a **transcript-builder correlation bug**, not a data-loss problem in persistence: `conversation.jsonl` correctly tags every row with `subagent_id`, and the live UI (which routes by ID via `SubagentUpdate`) renders parallel subagents correctly. Only the share builder is broken.

The existing test `builds two parallel subagent groups` did not catch this because it feeds **fully sequential** rows (`spawn-a, event-a, complete-a, spawn-b, event-b, complete-b`), which the stack handles fine. Real parallel runs interleave the rows.

## Fix

Replace the stack with a **map of open groups keyed by `subagent_id`**, and route every event by its own ID rather than by stack position. Determine the parent group at spawn time from the data already in the event stream — no persistence-format change is needed for the fix to land for existing sessions, though we should also persist `parent_subagent_id` going forward so the builder doesn't have to infer.

### File to modify

`packages/glue_harness/lib/src/share/share_transcript_builder.dart`

Replacement model:

- `final openGroups = <String, _OpenGroup>{};` — `LinkedHashMap` (Dart's default `Map` literal preserves insertion order), so "most-recently-opened" lookup is just `openGroups.values.lastWhere(...)`.
- `_OpenGroup` keeps `subagentId`, `children`, `nestingLevel`, and (new) `depth` from the spawn event.
- For each event:
  - **`subagentSpawned`** — pick a parent:
    1. If the event has `parent_subagent_id` *(see optional follow-up below; absent in legacy sessions)* and that group is open, parent = that group.
    2. Otherwise, walk `openGroups.values` in reverse insertion order and pick the most recently opened group whose `depth == event.depth - 1`. If none, parent = top-level (transcript root).
    3. Append the new group as a child of that parent (or to top-level entries) with `nestingLevel = parentLevel + 1` (or 0). Insert into `openGroups`.
  - **`subagentEvent`** — look up the open group by `event.subagentId`. If present, append the inner child (using the inner kind mapping that already exists). If absent, skip (orphan — same safety behavior as today).
  - **`subagentCompleted`** — `openGroups.remove(event.subagentId)`. No stack-top check.

Note: the existing helper `nestingLevel()` and `appendEntry()` close over the stack; both go away.

### Persistence — also emit `parent_subagent_id` (recommended follow-up)

`packages/glue_harness/lib/src/agent/agent_manager.dart` already mints `subagentId` at line 151, just before the `subagent_spawned` payload at line 152. To propagate the parent ID through nested spawns:

- `SpawnSubagentTool` and `SpawnParallelSubagentsTool` (in `packages/glue_harness/lib/src/tools/subagent_tools.dart`) already receive `depth` when they're constructed for a child subagent. Extend them to also receive the *owning* `parentSubagentId` so they can pass it back to `manager.spawnSubagent(...)`.
- Reorder the `spawnSubagent` body so `_mintSubagentId()` runs **before** `subagentTools` is built, then construct the subagent's spawn tools with `parentSubagentId: subagentId.value`.
- Add `parent_subagent_id` to the `subagent_spawned` payload (null at the top level).
- Extend `NormalizedSessionEvent` and `normalizeSessionEvent` (`session_event_normalizer.dart`) to carry `parentSubagentId` on `subagentSpawned`.

The builder's parent-resolution rule (1) above will then use it directly for new sessions; rule (2) remains the fallback for legacy `.jsonl` files (including the reproducer).

### Tests

Extend `packages/glue_harness/test/share/share_transcript_builder_test.dart` with cases that mirror the actual interleaving:

1. **Three parallel subagents, interleaved events, completions in spawn order** — reproduces the bug. Asserts: three sibling `subagentGroup` entries at top level (not nested); each group's children contain the events that match its `subagent_id`; events for A/B are not dropped; subsequent top-level events are not nested.
2. **Two parallel subagents, completions in reverse order** (B completes before A) — asserts both are siblings and the trailing top-level entry is at top level.
3. **Mixed: parallel siblings + one sibling spawns a nested child** — asserts the nested child renders under its true parent (uses `depth`-based parent resolution on legacy data; uses `parent_subagent_id` once persistence is updated).
4. Update the existing `builds two parallel subagent groups` test to keep its sequential ordering (still valid) and rename for clarity, since "parallel" was misleading.

If we ship the persistence change, also add a unit test that the new `parent_subagent_id` field round-trips through `normalizeSessionEvent`.

## Verification

```sh
# Unit tests for the share package
cd packages/glue_harness && dart test test/share/

# Full quality gate
cd /Users/helge/code/glue/cli && just check

# Visual verification: re-export the bug session and inspect
cd /Users/helge/code/glue/cli
dart run bin/glue.dart -r 1778140738915-hm
# inside session: /share html
# open the new HTML; confirm:
#   - three subagent groups appear as siblings (#22, #23, #24 — or whatever indices)
#   - each group contains its own events (A and B are no longer empty)
#   - entries after the parallel block are at top level, not is-nested
```

## Critical files

- `packages/glue_harness/lib/src/share/share_transcript_builder.dart` — the fix
- `packages/glue_harness/test/share/share_transcript_builder_test.dart` — new tests
- `packages/glue_harness/lib/src/session/session_event_normalizer.dart` — extend if persisting parent ID
- `packages/glue_harness/lib/src/agent/agent_manager.dart` — extend if persisting parent ID
- `packages/glue_harness/lib/src/tools/subagent_tools.dart` — extend if persisting parent ID
- Reference sample: `~/.glue/sessions/1778140738915-hm/conversation.jsonl`
- Reference output: `cli/glue-session-1778140738915-hm.html`
