---
id: TASK-6.2
title: Build ACP web UI client (Alpine.js + vanilla JS)
status: To Do
assignee: []
created_date: '2026-04-18 23:58'
labels:
  - feature
  - acp
  - webui
  - frontend
dependencies:
  - TASK-6.1
references:
  - 'https://agentclientprotocol.com/'
  - 'https://www.npmjs.com/package/stdio-to-ws'
documentation:
  - cli/docs/plans/2026-02-27-acp-webui.md
parent_task_id: TASK-6
priority: low
milestone: FUTURE
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build the browser-side ACP Client for Glue's web UI. Connects to `glue --acp` via WebSocket (bridged by `npx stdio-to-ws`), sends prompts, and renders streamed agent output. Depends on `task-6.1` (the `--acp` agent) being available.

**Design doc:** `cli/docs/plans/2026-02-27-acp-webui.md` — Side 2 (Web UI), Approach A (Vanilla JS).

**Why Approach A:** Zero build step, stays a single HTML file consistent with the existing static site. Full control over rendering. ~150 lines of vanilla JS handles the small ACP client surface (4 outbound methods, 2 inbound handlers).

**Components:**
- `GlueAcpClient` class — JSON-RPC over WebSocket (see design doc for a ~100-line sketch)
- Alpine.js integration — reactive store for sessions, blocks, pending permissions, connection state
- Streaming render logic:
  - `agent_message_chunk` → append to streaming assistant block
  - `tool_call` → create tool block with kind/status
  - `tool_call_update` → update status, render text result or diff
  - `session/request_permission` → show approve/deny modal
- Bridge: documented command `npx stdio-to-ws "dart run bin/glue.dart --acp" --port 3000`

**Scope for v1 (minimum viable):**
- Single session at a time (multi-session deferred)
- Advertise empty `clientCapabilities` (no fs/terminal — Glue handles file I/O via `dart:io`)
- Plain text rendering for agent output (markdown rendering deferred)
- No reconnection logic (page refresh is acceptable)

**Explicitly out of scope for v1** (tracked separately if wanted):
- Markdown rendering, code editor panel, reconnection/backoff
- Move to TypeScript SDK + Vite (Approach B)
- Multi-session tabs, session persistence/resume
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `GlueAcpClient` class handles JSON-RPC over WebSocket (request/response correlation + inbound notifications + inbound requests)
- [ ] #2 Alpine.js store reflects connection state, sessions, blocks, and pending permissions
- [ ] #3 User can create a session, send a prompt, and see streaming assistant text + tool calls rendered live
- [ ] #4 Tool call blocks show kind, status transitions (pending → in_progress → completed/failed), and result text or diff
- [ ] #5 Permission request modal appears for destructive tools and a user response completes the `session/request_permission` reply
- [ ] #6 `session/cancel` is sent when the user aborts a running prompt
- [ ] #7 README section in `website/` documents the bridge launch command
- [ ] #8 Manual end-to-end validated against `glue --acp` from task-6.1
<!-- AC:END -->
