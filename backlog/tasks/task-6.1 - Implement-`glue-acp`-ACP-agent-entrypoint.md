---
id: TASK-6.1
title: Implement `glue --acp` ACP agent entrypoint
status: To Do
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-20 00:05'
labels:
  - feature
  - acp
  - dart
milestone: m-3
dependencies: []
references:
  - 'https://agentclientprotocol.com/'
  - 'https://github.com/SkrOYC/acp-dart'
documentation:
  - cli/docs/plans/2026-02-27-acp-webui.md
parent_task_id: TASK-6
priority: low
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the ACP Agent side of Glue — a headless mode invoked as `glue --acp` that speaks the Agent Client Protocol over stdio (newline-delimited JSON-RPC). This lets any ACP-compatible client (our web UI, Zed, JetBrains, Neovim, VS Code) drive Glue's agent loop.

**Design doc:** `cli/docs/plans/2026-02-27-acp-webui.md` — Side 1 (ACP Agent).

**Library:** `acp_dart` v0.3.0 (https://github.com/SkrOYC/acp-dart) — handles stdio framing, JSON-RPC routing, typed Dart objects.

**Methods to implement:**
- `initialize` — return capabilities + agent info; advertise `loadSession: false` for v1
- `session/new` — create a new `AgentCore` + tools per session; key by `sessionId`, use `params.cwd`
- `session/prompt` — drive `AgentCore.run(userMessage)`, stream `AgentEvent`s as `session/update` notifications
- `session/cancel` — cancel the active agent stream; return `stopReason: cancelled`
- `request_permission` — call outbound before destructive tools (write/edit/bash)

**Event mapping** (see design doc for the full table):
- `AgentTextDelta` → `agent_message_chunk`
- `AgentToolCall` → `tool_call` (pending) then `tool_call_update` (in_progress → completed/failed)
- `AgentDone` → return `PromptResponse { stopReason: endTurn }`

**Tool kind mapping:** read/edit/execute/search as per the design doc's table.

**Files (approximate):**
- `cli/lib/src/acp/glue_acp_agent.dart` — `Agent` interface bridge to `AgentCore`
- `cli/lib/src/acp/acp_session.dart` — per-session state (AgentCore, tools, subscription)
- `cli/bin/glue.dart` — add `--acp` flag, wire `ndJsonStream` + `AgentSideConnection`

Estimated size: ~200–300 lines of Dart.

**Validation:** test manually against Zed editor configured to launch `glue --acp` as an ACP agent. Zed is an independent ACP client and will surface protocol bugs our web UI might mask.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `acp_dart` added to `pubspec.yaml`
- [ ] #2 `--acp` flag launches Glue in headless ACP mode over stdio
- [ ] #3 `initialize`, `session/new`, `session/prompt`, `session/cancel` all implemented
- [ ] #4 Permission requests sent for destructive tools (write_file, edit_file, bash); read-only tools auto-execute
- [ ] #5 Streaming events map correctly per the design doc's table (text deltas, tool_call, tool_call_update, diff content for edits)
- [ ] #6 Manual validation: Glue launches as agent in Zed editor and completes a multi-turn conversation with tool use
- [ ] #7 Unit tests cover event mapping and session lifecycle
<!-- AC:END -->
