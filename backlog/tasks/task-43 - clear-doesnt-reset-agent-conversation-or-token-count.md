---
id: TASK-43
title: /clear doesn't reset agent conversation or token count
status: To Do
assignee: []
created_date: "2026-04-20 00:09"
updated_date: "2026-04-20 00:32"
labels:
  - bug
  - commands
  - cli
milestone: m-0
dependencies: []
references:
  - cli/lib/src/app/command_helpers.dart
  - cli/lib/src/agent/agent_core.dart
priority: medium
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Bug surfaced during the slash-command-conventions plan adversarial review (2026-04-20 conversation `49eabc82`):

`_clearConversationImpl` clears the on-screen scrollback but does **not** call `agent.clearConversation()` and does **not** reset `tokenCount`. After `/clear`, the model still sees the entire prior conversation history on the next turn and the status bar still shows accumulated tokens — both at odds with what the user reasonably expects "clear" to mean.

**Expected after `/clear`:**

- On-screen scrollback cleared (works today).
- Agent's internal conversation history reset to empty.
- Status-bar token count reset to 0.
- Session JSONL records a `conversation_cleared` event so replay shows the boundary (see TASK-37 schema work).

**Coordinates with:**

- TASK-33 (slash command grammar) — once the noun-namespace pattern lands, decide whether `/clear` stays a top-level verb or becomes `/session clear`. Either way, the underlying behavior fix is independent.
- TASK-37 (JSONL schema) — boundary event optional; ship the bug fix without waiting.

**Out of scope:**

- Renaming or relocating `/clear` (TASK-33 owns that).
- Confirmation prompt before clearing (separate UX call).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 After `/clear`, `agent.conversationHistory` is empty (verified via spy or unit test).
- [ ] #2 After `/clear`, status-bar `tokenCount` reads 0.
- [ ] #3 After `/clear`, the next user turn sends only that turn's messages to the LLM (no historical context leaked).
- [ ] #4 Test added covering: pre-clear history present → `/clear` → post-clear history empty → next turn payload contains only new message.
- [ ] #5 No regression in existing slash-command tests.
<!-- AC:END -->
