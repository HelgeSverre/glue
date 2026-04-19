---
id: TASK-18
title: Standardize tool result schema
status: In Progress
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:02'
labels:
  - simplification-2026-04
  - tools
  - refactor
dependencies: []
references:
  - cli/lib/src/agent/tools.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: medium
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tools currently return `Future<List<ContentPart>>` — ad-hoc text with no structured metadata. Define a small display contract (`summary`, `details`, `is_error`, `bytes`, `line_count`, `artifacts`) so rendering is cleaner and M7 (diff-aware write/edit) has a place to put line counts.

**New type (in `cli/lib/src/agent/`):**
```dart
class ToolResult {
  final bool success;
  final String message;              // primary payload the LLM sees
  final String? summary;             // optional one-liner for UI
  final Map<String, dynamic> metadata; // bytes, lines, exit_code, paths, etc.
  final List<ContentPart>? artifacts; // structured content (diffs, images)
}
```

**Files to modify:**
- `cli/lib/src/agent/tools.dart` — abstract `Tool.execute()` returns `Future<ToolResult>`
- Update `ReadFileTool`, `WriteFileTool`, `EditFileTool`, `BashTool`, `GrepTool`, `ListDirectoryTool` to populate metadata (bytes for read/write, exit_code for bash, line_count for grep, entry count for list)
- Add `ToolResult.toContentParts()` serialization helper for the LLM path
- Renderer in `cli/lib/src/app/` — prefer `summary`, fall back to truncated `message`

**Enables:** M7 (diff-aware write/edit) — blocks on this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `Tool.execute()` returns `Future<ToolResult>`
- [ ] #2 Read/Write/Edit/Bash/Grep/ListDirectory populate metadata fields
- [ ] #3 Renderer uses `summary` when present
- [ ] #4 LLM serialization via `toContentParts()` helper — no behavior change for the model
- [ ] #5 Tests cover each tool's metadata contract
- [ ] #6 `dart analyze --fatal-infos` clean; `dart test` green
<!-- AC:END -->
