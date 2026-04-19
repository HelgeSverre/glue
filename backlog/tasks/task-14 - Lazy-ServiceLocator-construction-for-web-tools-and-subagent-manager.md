---
id: TASK-14
title: Lazy ServiceLocator construction for web tools
status: In Progress
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 22:22'
labels:
  - simplification-2026-04
  - performance
  - refactor
dependencies:
  - TASK-11
references:
  - cli/lib/src/core/service_locator.dart
documentation:
  - docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ServiceLocator.create()` eagerly constructs web-tool support on every startup. `SearchRouter` and the selected browser endpoint provider/`BrowserManager` are only needed when `web_search` or `web_browser` is invoked and should be lazy.

**Why:** Startup should only build what the initial screen needs. Deferring rarely-used services reduces startup time and simplifies config-validation failure modes.

**File:** `cli/lib/src/core/service_locator.dart`

**Currently eager** (lines ~48–228):
- Terminal, Layout, TextAreaEditor — always needed (keep eager)
- `SkillRuntime` — always scanned for system prompt (keep eager)
- Observability setup (lines 92–116 — simplified by R4)
- LLM clients — always needed
- `ConfigStore`, `SessionStore`, `Executor` — always needed
- **`SearchRouter`** — only needed if `web_search` tool is invoked
- **`BrowserManager`** — only needed if `web_browser` tool is invoked

**Target behavior:**
- Introduce memoized lazy factories for `SearchRouter` and `BrowserManager`
- `WebSearchTool` and `WebBrowserTool` receive lazy handles, not constructed instances
- `WebBrowserTool.dispose()` is safe when the browser manager was never constructed

**Acceptance criteria below ensure we don't regress functionality; perf gain is a soft goal.**

**Gotchas:**
- Browser/container provisioning already happens on first `BrowserManager.getEndpoint()`; this task only defers provider/manager object construction.
- `SearchRouter` construction is cheap; defer mostly for config-validation simplification (avoids failing fast on invalid provider config when the user never uses search)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Startup where no web tools are invoked does not construct `SearchRouter` or `BrowserManager` (verifiable via log/spy)
- [ ] #2 First invocation of `web_search` or `web_browser` still succeeds end-to-end
- [ ] #3 Tool disposal remains safe when `web_browser` was never invoked
- [ ] #4 No browser endpoint provider or browser manager is constructed until first `web_browser` invocation
- [ ] #5 Existing tests green
- [ ] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->
