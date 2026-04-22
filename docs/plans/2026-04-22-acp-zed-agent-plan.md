# Plan: Expose Glue as an ACP Agent for Zed

## Goal

Allow Glue to run as an ACP stdio server so ACP-native clients (like Zed agent integrations) can create sessions, send prompts, receive streamed updates, and approve/deny mutating tool calls.

## What was researched

- Existing repository already had an ACP concept plan in `docs/plans/2026-02-27-acp-webui.md`.
- The `acp` package now provides the required primitives:
  - `StdioTransport`
  - `AgentSideConnection`
  - `AgentHandler`
  - Typed session update and permission request models.
- ACP package examples confirm the exact method flow needed for editor integrations:
  `initialize` → `session/new` → `session/prompt` + streamed `session/update` + optional `session/request_permission`.

## Implemented prototype scope

1. Added `--acp` mode to `glue` CLI.
2. Added ACP runtime/agent bridge:
   - `cli/lib/src/acp/glue_acp_agent.dart`
   - `cli/lib/src/acp/acp_session.dart`
3. Added `acp` dependency to CLI package.
4. Added basic CLI arg test coverage for `--acp`.

## Current architecture (prototype)

- `bin/glue.dart --acp` starts an ACP stdio server.
- `GlueAcpAgent` implements ACP `AgentHandler`.
- `newSession` creates a per-session `AgentCore`.
- `prompt` streams:
  - `AgentTextDelta` -> ACP `agent_message_chunk`
  - `AgentToolCallPending` -> ACP `tool_call` (pending)
  - `AgentToolCall` execution status/results -> ACP `tool_call_update`
- Mutating tools (`write_file`, `edit_file`, `bash`) require ACP permission requests.

## Known limitations / follow-up

1. Tool working directory is currently process cwd (not per-session cwd path rewriting yet).
2. ACP mode currently exposes a minimal tool set (core local tools + `skill`) and does not yet wire the full interactive tool/runtime stack.
3. No dedicated ACP integration tests yet (manual validation with Zed/client required).
4. `session/load`/resume, richer modes/config options, and advanced session metadata updates are not implemented yet.

## Validation approach

- First test against a lightweight ACP client script using `StdioProcessTransport`.
- Then validate with real Zed ACP agent registration.
- Expand with automated ACP protocol tests once runtime contract stabilizes.
