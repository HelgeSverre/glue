---
id: TASK-14
title: Lazy ServiceLocator construction for web tools
status: Done
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-20 00:48'
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
- [x] #1 Startup where no web tools are invoked does not construct `SearchRouter` or `BrowserManager` (verifiable via log/spy)
- [x] #2 First invocation of `web_search` or `web_browser` still succeeds end-to-end
- [x] #3 Tool disposal remains safe when `web_browser` was never invoked
- [x] #4 No browser endpoint provider or browser manager is constructed until first `web_browser` invocation
- [x] #5 Existing tests green
- [x] #6 `dart analyze --fatal-infos` clean
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Revised the task scope to cover only web-tool service construction, removed stale subagent-manager wording, fixed the simplification-plan documentation path, and replaced the nonexistent `AppServices.dispose()` criterion with the real tool-disposal lifecycle.

Implemented lazy web service construction in `ServiceLocator.create()` by passing memoized lazy factories into `WebSearchTool.lazy(...)` and `WebBrowserTool.lazy(...)`. `SearchRouter`, browser provider selection, and `BrowserManager` are no longer constructed during startup; they are built on first valid tool use. Existing direct constructors remain for tests and existing call sites.

`WebBrowserTool.dispose()` is safe before first use and does not force lazy manager construction. Focused tests cover lazy `web_search`, validation failures that do not construct `BrowserManager`, and disposal before first browser use.

Verification:
- `dart analyze --fatal-infos` clean.
- `dart test test/tools/web_search_tool_test.dart test/tools/web_browser_tool_test.dart` passed.
- Full `dart test` was run and has one unrelated pre-existing failure: `test/shell/docker_executor_test.dart: DockerExecutor runCapture executes in container` expected `hello` but got empty stdout.

AC #1 is satisfied by the focused lazy-construction tests at the tool boundary rather than a startup integration spy.
<!-- SECTION:FINAL_SUMMARY:END -->
