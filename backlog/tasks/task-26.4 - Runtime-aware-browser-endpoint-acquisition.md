---
id: TASK-26.4
title: Runtime-aware browser endpoint acquisition
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
updated_date: '2026-04-20 00:05'
labels:
  - runtime-boundary-2026-04
  - browser
milestone: m-2
dependencies: []
references:
  - cli/lib/src/web/browser/browser_manager.dart
  - cli/lib/src/web/browser/browser_endpoint.dart
documentation:
  - cli/docs/plans/2026-04-19-runtime-boundary-plan.md
parent_task_id: TASK-26
priority: medium
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today browser backends provision CDP endpoints via `BrowserEndpointProvider` (local, Docker-browser, Browserbase, Steel). That's fine for today but future cloud runtimes (E2B, Modal) may also offer browsers.

**Change:** allow a runtime session to provide a browser endpoint too. The browser tool should not care whether the endpoint came from a standalone provider or a runtime session.

**Refactor:**
- Keep `BrowserEndpointProvider` interface as-is (backward compat)
- Add `BrowserEndpointSource` abstraction that can be either a `BrowserEndpointProvider` OR a hook into a runtime session
- `BrowserManager` resolves endpoints via either source

**Files:**
- Modify: `cli/lib/src/web/browser/browser_manager.dart`
- Create: `cli/lib/src/web/browser/browser_endpoint_source.dart`
- Existing providers (`docker_browser_provider.dart`, `browserbase_provider.dart`, `browserless_provider.dart`, `steel_provider.dart`) unchanged

**Explicit non-goal:** do NOT implement a runtime-provided browser yet. Just make the manager runtime-aware so it's easy to add later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `BrowserEndpointSource` abstraction exists
- [ ] #2 `BrowserManager` can resolve endpoints from provider OR runtime (even if runtime path is unused today)
- [ ] #3 Existing browser providers continue to work without changes
- [ ] #4 Tests verify endpoint resolution from both source types (mock runtime)
- [ ] #5 No user-visible regression
<!-- AC:END -->
