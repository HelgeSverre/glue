---
id: TASK-24.4
title: Artifact writer for large/binary output
status: To Do
assignee: []
created_date: '2026-04-19 00:43'
labels:
  - session-jsonl-2026-04
  - storage
dependencies:
  - TASK-24.1
  - TASK-24.2
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-24
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Large outputs, binary payloads, images, and big diffs should not bloat `conversation.jsonl`. Write them to sidecar files and reference from the JSONL.

**Target layout:**
```
~/.glue/sessions/<session-id>/
  conversation.jsonl
  artifacts/
    <event-id>.txt
    <event-id>.json
    <event-id>.patch
    <event-id>.png
```

**Artifact trigger conditions:**
- output exceeds configured byte limit (default: 32 KB)
- output is binary
- output is an image
- diff is large
- browser screenshot captured

**JSONL reference shape:**
```json
{
  "type": "tool_call.output",
  "data": {
    "call_id": "tc1",
    "artifact": "artifacts/evt_123.txt",
    "truncated": true,
    "bytes": 1048576
  }
}
```

**Files:**
- Create: `cli/lib/src/session/artifact_writer.dart`
- Modify tool output paths to call artifact writer above threshold
- Config: byte threshold configurable in `GlueConfig`

**Open question (defer):** GC with session, or share by content hash? Default: session-local, GC with session.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Outputs over threshold (default 32 KB) written to `artifacts/<event-id>.txt`
- [ ] #2 JSONL event references artifact by relative path + records `bytes`, `truncated` flag
- [ ] #3 Binary outputs written with appropriate extension
- [ ] #4 Browser screenshots captured as artifact references
- [ ] #5 Byte threshold configurable via `GlueConfig`
- [ ] #6 Tests cover: over-threshold text, binary payload, image artifact
<!-- AC:END -->
