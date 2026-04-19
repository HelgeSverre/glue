---
id: TASK-24.3
title: 'Emit full event coverage: messages, model, tool, file, runtime, agent'
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - session-jsonl-2026-04
  - integration
dependencies:
  - TASK-24.1
  - TASK-24.2
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-24
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wire up emission of all event types defined in SE1 throughout the runtime paths. Today only `user_message`, `assistant_message`, `tool_call`, `tool_result`, `title_generated` are emitted; this task expands coverage.

**Emit points to add:**
- `AgentCore` — turn.{started,completed,failed,cancelled}, message.assistant.{started,delta,completed}, model.request.started, model.response.{delta,completed,failed}, model.usage
- `Tool.execute` wrappers — tool_call.{pending,started,output,completed,failed,denied,cancelled}
- `WriteFileTool`/`EditFileTool` — file.write.{started,diff,completed,failed}
- `ReadFileTool` — file.read
- `ShellJobManager` — runtime.command.{started,output,completed,failed,cancelled}
- `DockerExecutor` — runtime.container.{started,stopped}
- `AgentManager` — agent.{delegated,message,tool_call,completed,failed}

**Coordinate with:**
- MP (task-22) — model events should include `model_ref` (provider_id + model_id), per the adapter contract plan
- R3 (task-10) — tool_call.denied path
- RB1 (runtime boundary) — command.started event should carry runtime_id + cwd mapping

**Files:**
- Modify: `cli/lib/src/agent/agent_core.dart`
- Modify: `cli/lib/src/agent/tools.dart` (wrapper around `execute`)
- Modify: `cli/lib/src/shell/shell_job_manager.dart`
- Modify: `cli/lib/src/shell/docker_executor.dart`
- Modify: `cli/lib/src/agent/agent_manager.dart`

**Depends on:** SE1 (event types) + SE2 (append writer).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A realistic session produces the full expected event stream (turn/tool/file/runtime/agent events present)
- [ ] #2 Tool state transitions are captured: pending → started → output* → completed|failed|denied|cancelled
- [ ] #3 Model events include `model_ref` (provider_id + model_id)
- [ ] #4 Runtime command events include runtime_id + cwd mapping
- [ ] #5 Agent delegation produces a nested event stream under parent turn_id
- [ ] #6 Tests cover at least one example from each event family
<!-- AC:END -->
