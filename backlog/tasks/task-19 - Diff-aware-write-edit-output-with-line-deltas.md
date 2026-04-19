---
id: TASK-19
title: Diff-aware write/edit output with line deltas
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:02'
labels:
  - simplification-2026-04
  - tools
  - ux
dependencies:
  - TASK-18
references:
  - cli/lib/src/agent/tools.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: medium
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Once `ToolResult` has a `metadata` map (see M6), `WriteFileTool` and `EditFileTool` should populate line-delta info so the UI can render Codex-style `Edited N files (+x -y)` summaries instead of raw tool output.

**Files:**
- `cli/lib/src/agent/tools.dart` — `WriteFileTool` (~41 LOC) and `EditFileTool` (~87 LOC)
- Renderer in `cli/lib/src/app/` (likely `render_pipeline.dart` or `command_helpers.dart`)

**Current returns:**
- `WriteFileTool`: `"Wrote {bytes} bytes to {path}"`
- `EditFileTool`: `"Applied edit to {path}: replaced {oldLines} line(s) with {newLines} line(s)"`

**Target metadata:**
```
{ path, bytes_written, lines_added, lines_removed, is_new_file }
```
- For edits: compute line delta by counting lines before/after replacement (simple line count diff, no LCS needed)
- For new files: `is_new_file=true`, `lines_added=count(newlines(content))`, `lines_removed=0`

**Rendering:**
- Batch N tool calls → `Edited N files (+x -y)`
- Single new file → `Created foo.md (+N)`

**Depends on:** M6 (`ToolResult` schema must exist).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `WriteFileTool` populates `metadata.lines_added`, `lines_removed`, `is_new_file`, `path`
- [ ] #2 `EditFileTool` populates same fields + old vs new line count diff
- [ ] #3 Renderer emits `Edited N files (+x -y)` for batched tool calls
- [ ] #4 Renderer emits `Created foo.md (+N)` for new file
- [ ] #5 Tests cover create, append, replace, no-op cases
- [ ] #6 `dart test` green
<!-- AC:END -->
