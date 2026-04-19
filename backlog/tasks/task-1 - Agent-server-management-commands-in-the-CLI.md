---
id: TASK-1
title: Agent-server management commands in the CLI
status: To Do
assignee: []
created_date: '2026-04-18 23:56'
labels:
  - cli
  - agent-servers
  - feature
dependencies: []
references:
  - cli/IDEAS.md
  - 'https://zed.dev/docs/extensions/agent-servers'
priority: low
milestone: FUTURE
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add CLI commands for managing agent servers (ACP-style headless agents) directly from Glue. Users should be able to start, stop, monitor, and inspect agent servers without leaving the terminal.

Context: Zed's agent-server model (https://zed.dev/docs/extensions/agent-servers) lets editors discover and launch external agents. Once Glue can run as an ACP agent (see the ACP web UI work), it becomes natural to also manage *other* agent servers from Glue — list registered agents, start/stop them, tail logs, check status.

This is a separate concern from "Glue itself speaks ACP" — this task is about Glue as a **client/manager** of agent servers.

Source: `cli/IDEAS.md`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI subcommand group exists for managing agent servers (e.g., `glue agent start|stop|list|logs`)
- [ ] #2 `list` shows registered agent servers with status (running/stopped) and basic metadata
- [ ] #3 `start`/`stop` manage a named agent-server process
- [ ] #4 `logs` tails the stdout/stderr of a running agent server
- [ ] #5 Subcommands documented in `--help` output
- [ ] #6 Unit tests cover command parsing and registry interaction
- [ ] #7 Reference docs updated in `devdocs/`
<!-- AC:END -->
