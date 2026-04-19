---
id: TASK-24.2
title: Append-only JSONL writer (fix file-rewrite perf cliff)
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - session-jsonl-2026-04
  - perf
dependencies:
  - TASK-24.1
references:
  - cli/lib/src/storage/session_store.dart
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-24
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today `SessionStore.logEvent(type, data)` reads the whole JSONL file and atomically rewrites it for every event. That is a performance cliff for long-running sessions.

**Change `SessionStore.logEvent`:**
- Open file in append mode (`FileMode.writeOnlyAppend`)
- Write one JSON line per event
- Flush periodically or on session-close for crash safety
- Keep atomic tmp-file-then-rename for `meta.json` and `state.json` (those are whole-file writes)

**Introduce (optional, if needed):**
```dart
abstract class SessionEventSink {
  void append(SessionEvent event);
  Future<void> flush();
}
```

**Keep compatibility wrapper:** the existing `logEvent(String type, Map data)` signature stays as a thin adapter over the new typed-event path.

**Files:**
- Modify: `cli/lib/src/storage/session_store.dart`
- Create: `cli/lib/src/session/session_event_sink.dart` (if we go interface route)
- Tests: long-running append doesn't scale O(n²)

**Depends on:** SE1 (typed events).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `SessionStore.logEvent` opens file in append mode, does not read existing content
- [ ] #2 1000+ events appended without O(n²) behavior (performance test)
- [ ] #3 Crash safety maintained via flush on session close
- [ ] #4 `meta.json` and `state.json` still use atomic tmp-file-then-rename
- [ ] #5 Existing `logEvent(String, Map)` signature still works (backward compat)
- [ ] #6 Tests verify append behavior + flush semantics
<!-- AC:END -->
