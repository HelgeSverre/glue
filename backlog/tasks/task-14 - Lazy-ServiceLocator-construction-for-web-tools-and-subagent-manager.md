---
id: TASK-14
title: Lazy ServiceLocator construction for web tools and subagent manager
status: To Do
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 04:02'
labels:
  - simplification-2026-04
  - performance
  - refactor
dependencies:
  - TASK-11
references:
  - cli/lib/src/core/service_locator.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ServiceLocator.create()` eagerly constructs ~10 services on every startup. `SearchRouter` (3 providers) and `BrowserManager` (container selection) are rarely needed on turn 1 and should be lazy.

**Why:** Startup should only build what the initial screen needs. Deferring rarely-used services reduces startup time and simplifies config-validation failure modes.

**File:** `cli/lib/src/core/service_locator.dart` (~277 LOC)

**Currently eager** (lines ~48–228):
- Terminal, Layout, TextAreaEditor — always needed (keep eager)
- `SkillRuntime` — always scanned for system prompt (keep eager)
- Observability setup (lines 92–116 — simplified by R4)
- LLM clients — always needed
- `ConfigStore`, `SessionStore`, `Executor` — always needed
- **`SearchRouter`** (lines 152–160) — only needed if `web_search` tool is invoked
- **`BrowserManager`** (lines 162–181) — only needed if `web_browser` tool is invoked

**Target behavior:**
- Introduce lazy getters (or `Lazy<T>`) for `searchRouter` and `browserManager`
- Null by default; constructed on first access from within the respective tool
- `WebSearchTool` and `WebBrowserTool` receive lazy handles (a `() => Future<X>` or similar), not instances
- Disposal in `AppServices.dispose()` handles null

**Acceptance criteria below ensure we don't regress functionality; perf gain is a soft goal.**

**Gotchas:**
- `BrowserManager` owns container lifecycle; if laziness defers container start, add a user-visible loading message on first `web_browser` tool call so the delay is expected
- `SearchRouter` construction is cheap; defer mostly for config-validation simplification (avoids failing fast on invalid provider config when the user never uses search)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Startup where no web tools are invoked does not construct `SearchRouter` or `BrowserManager` (verifiable via log/spy)
- [ ] #2 First invocation of `web_search` or `web_browser` still succeeds end-to-end
- [ ] #3 `AppServices.dispose()` handles null values safely
- [ ] #4 Loading message shown on first `web_browser` if container start is noticeable
- [ ] #5 Existing tests green
- [ ] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->
