# Fix `↳` Prefix Repeating On Every Subagent Step Line

## Context

When the user expands a `spawn_parallel_subagents` group in Glue's TUI, every child step renders with the same `↳ [N/M]` prefix as the header summary line. The user reported this looks visually wrong — they expect `↳` to mark only the group header, with inner steps indented and prefixed by just their action glyph (`▶`, `✓`, `✗`, `·`).

Observed (expanded):

```
      ↳ [1/3] Use the web_fetch tool... (4 steps, done ✓)
      ↳ [1/3] ▶ web_fetch  url: https://www.nrk.no
      ↳ [1/3] ✓ Fetched https://www.nrk.no (19591 chars)
```

Desired:

```
      ↳ [1/3] Use the web_fetch tool... (4 steps, done ✓)
         ▶ web_fetch  url: https://www.nrk.no
         ✓ Fetched https://www.nrk.no (19591 chars)
```

## Root Cause

The `↳ [N/M]` prefix is baked into `SubagentEntry.display` strings at the three insertion sites:

- `cli/lib/src/app.dart:2720-2746` — live event handler `_handleSubagentUpdate` builds `prefix` once then prepends it to every entry (tool call, tool result, error).
- `cli/lib/src/services/conversation_view.dart:145-174` — replay path `subagentEvent` does the same.
- `cli/lib/src/services/conversation_view.dart:182-186` — replay path `subagentCompleted` error branch.

At render time, `cli/lib/src/app.dart:935-937` joins `summary + entries...` with `\n` and feeds the whole block through `BlockRenderer.renderSubagent` (`cli/lib/src/rendering/block_renderer.dart:177-181`), which applies a uniform 6-space indent + dim cyan to every line. So the header and child lines end up visually indistinguishable, and the redundant `↳ [N/M]` makes the redundancy stark.

`SubagentGroup.summary` (`cli/lib/src/conversation/entry.dart:123-132`) is the only place the `↳` belongs — that's the group header. The child entries should not carry it.

## Approach

Strip the `↳ [N/M]` prefix from entries at the insertion sites, and add a small inner indent at the entry-render site so children visually nest under the header.

### 1. Remove prefix at the three insertion sites

In all three places, replace `'$prefix ▶ ...'` / `'$prefix ✓ ...'` / `'$prefix ✗ ...'` / `'$prefix · ...'` with just `'▶ ...'` / `'✓ ...'` / `'✗ ...'` / `'· ...'`. Drop the `prefix` local entirely.

Files & lines:

- `cli/lib/src/app.dart:2720-2746` — delete the `final prefix = ...` declaration; update the four `SubagentEntry(...)` constructions.
- `cli/lib/src/services/conversation_view.dart:145-174` — same in the `subagentEvent` switch (`toolCall`, `toolResult`, `default`).
- `cli/lib/src/services/conversation_view.dart:182-186` — same in the `subagentCompleted` error branch.

### 2. Indent child rows in `SubagentEntry.render`

Update `SubagentEntry.render({required bool expanded})` in `cli/lib/src/conversation/entry.dart:90-96` to prepend `'   '` (3 spaces) when called from the expanded join. Since `render` is called only from `app.dart:935-937` for the expanded path (and `display` is otherwise unused as-is), the simplest change is: prepend `'   '` to `display` unconditionally inside `render`, since this method only runs when an entry is being rendered into the expanded view.

Resulting indent stack (cumulative): `renderSubagent` adds 6 spaces + dim cyan to every line → header sits at 6, children sit at 6 + 3 = 9. The pretty-printed JSON branch (`'          '`, 10 spaces) already exceeds the new step indent and can stay.

### 3. Keep `SubagentGroup.summary` unchanged

The header line keeps `↳ $prefix $taskPreview ...` — that's the one place `↳` is correct.

## Files To Modify

- `cli/lib/src/app.dart` (live subagent path, ~lines 2720-2746)
- `cli/lib/src/services/conversation_view.dart` (replay path, lines 145-186)
- `cli/lib/src/conversation/entry.dart` (`SubagentEntry.render`, lines 90-96)

No new files, no abstractions.

## Tests

No existing test asserts the `↳ [N/M]` prefix on child entry strings (verified via `grep '↳' cli/test/` — no matches). The plan is safe re: regressions in `cli/test/commands/*_test.dart` which only reference `SubagentGroup` as a map type.

If we want a regression guard, add a single unit assertion in (e.g.) a new tiny test that:
- Constructs a `SubagentGroup` with `index: 0, total: 3`.
- Calls `_handleSubagentUpdate` with an `AgentToolCall` event.
- Asserts the resulting `SubagentEntry.display` starts with `'▶ '` and does **not** contain `'↳'`.

This is optional given the small surface; the visual verification below is more useful.

## Verification

1. `just cli::check` — analyze + tests pass with no warnings.
2. Run the existing parallel-subagents harness script: `dart run cli/tool/e2e_parallel_subagents.dart` (already modified in the working tree — make sure its assertions don't pin the `↳` string).
3. Manual TUI check: start `dart run cli/bin/glue.dart`, prompt the agent to use `spawn_parallel_subagents` with 2–3 tasks, then toggle expand on one group. Confirm:
   - Collapsed: each group shows one `↳ [N/M] ...` summary line (unchanged).
   - Expanded: the summary keeps `↳ [N/M]`; child rows show only their glyph (`▶`/`✓`/`✗`/`·`) with deeper indent and no arrow.
4. Replay a saved session that contains a parallel-subagents run (`glue --resume`) and confirm the same shape in the replay path.
