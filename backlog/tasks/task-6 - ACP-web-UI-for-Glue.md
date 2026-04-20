---
id: TASK-6
title: ACP web UI for Glue
status: To Do
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-20 00:05'
labels:
  - feature
  - acp
  - webui
  - parent
milestone: m-3
dependencies: []
references:
  - 'https://agentclientprotocol.com/'
  - 'https://github.com/SkrOYC/acp-dart'
  - 'https://www.npmjs.com/package/stdio-to-ws'
documentation:
  - cli/docs/plans/2026-02-27-acp-webui.md
priority: low
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a web-based UI for Glue that talks to the CLI agent over the Agent Client Protocol (ACP). The web UI is an **ACP Client** in the browser; Glue runs as an **ACP Agent** over stdio. This single ACP implementation serves both our own web UI and any ACP-compatible editor (Zed, JetBrains, Neovim, VS Code).

**Design doc:** `cli/docs/plans/2026-02-27-acp-webui.md` (read this first — detailed architecture, library choices, event mapping tables, and implementation order)

**Parent task reason:** Work splits cleanly into two independently deliverable subtasks. The agent side (`glue --acp`) is a prerequisite and valuable on its own (unlocks editor integrations). The web UI side builds on top.

Subtasks:
1. Implement `glue --acp` — the ACP agent entrypoint using `acp_dart`
2. Build the web UI ACP client (Alpine.js + vanilla JS, per Approach A in the design doc)

Out of scope for this parent (tracked only if/when needed):
- `session/load` session resume
- `fs/*` and `terminal/*` client capabilities
- MCP server passthrough
- Multi-user auth / production backend (replacing `stdio-to-ws`)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both subtasks (ACP agent + web UI) complete
- [ ] #2 End-to-end: user runs `npx stdio-to-ws 'dart run bin/glue.dart --acp' --port 3000`, opens the web UI, creates a session, sends a prompt, and sees streaming agent output + tool calls
- [ ] #3 Permission requests render as an approve/deny modal in the web UI
- [ ] #4 Glue `--acp` mode passes manual validation against Zed editor as ACP client
<!-- AC:END -->
