---
id: TASK-18
title: Standardize tool result schema
status: Done
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:14'
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
- [x] #1 `Tool.execute()` returns `Future<ToolResult>`
- [x] #2 Read/Write/Edit/Bash/Grep/ListDirectory populate metadata fields
- [x] #3 Renderer uses `summary` when present
- [x] #4 LLM serialization via `toContentParts()` helper — no behavior change for the model
- [x] #5 Tests cover each tool's metadata contract
- [x] #6 `dart analyze --fatal-infos` clean; `dart test` green
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Unified `ToolResult` into a single type (moved from `agent_core.dart` into `tools.dart`) with new fields: `summary: String?`, `metadata: Map<String, dynamic>` (defaults to `const {}`), alongside existing `callId`, `content`, `contentParts`, `success`. Added `withCallId(id)` so tools can leave `callId` empty and let the agent stamp it post-hoc, and `toContentParts()` for LLM-facing serialization.

`Tool.execute()` abstract signature now returns `Future<ToolResult>`. All seven built-in tools (Read/Write/Edit/Bash/Grep/ListDirectory + Forwarding) plus peripherals (SkillTool, WebFetchTool, WebSearchTool, WebBrowserTool, SpawnSubagentTool, SpawnParallelSubagentsTool) populate structured metadata:
- Read/Write/Edit: path, bytes, line_count, is_new_file, old_lines/new_lines
- Bash: command, exit_code, stdout_bytes, stderr_bytes, timed_out
- Grep: pattern, path, match_count
- ListDirectory: path, entry_count, capped
- WebFetch/Search/Browser: url/query/action + error hints
- Subagent: task(s), depth, model_ref

`AgentCore.executeTool()` now delegates to `tool.execute(...).withCallId(call.id)` — catches exceptions into a synthesized error `ToolResult`. The conversation builder already uses `.content` / `.contentParts` so no changes needed there.

Renderers updated to prefer `summary`:
- `agent_orchestration.dart`: conversation blocks show `summary ?? content`; session log includes both `summary` and `metadata`.
- `subagent_updates.dart`: uses `summary ?? truncated content` for the one-line preview; falls back to storing raw content when either is long.

Test updates:
- Tool stubs (`agent_core_test`, `tool_filter_test`, `tool_trust_test`, `permission_gate_test`) now override to return `ToolResult` directly.
- `execute_with_parts_test` rewritten to cover the new ToolResult semantics (content, contentParts, toContentParts(), withCallId).
- Assertion helpers across tool tests switched from `ContentPart.textOnly(await tool.execute(...))` to `(await tool.execute(...)).content`.
- Bulk transform via perl + targeted Edit for multi-line cases; unused `content_part` imports cleaned up.

Verification: `dart format` clean, `dart analyze --fatal-infos` clean, all 1177 tests green (0 regressions).
<!-- SECTION:FINAL_SUMMARY:END -->
