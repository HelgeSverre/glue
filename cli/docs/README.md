# Glue CLI Documentation

## Architecture

Core system design and terminology.

- **[glossary.md](architecture/glossary.md)** — Canonical terminology: Project, Session, Worktree, Permission Modes, Skills, Web Tools, Observability
- **[agent-loop-and-rendering.md](architecture/agent-loop-and-rendering.md)** — Agent loop (ReAct), App state machine, terminal layout, render pipeline, LLM streaming, subagents, tool approval, session persistence, web tools, skills, observability, permission modes

## Reference

Schemas and formats for Glue's configuration and data files.

- **[glue-home-layout.md](reference/glue-home-layout.md)** — `~/.glue/` directory structure and file lifecycle
- **[config-yaml.md](reference/config-yaml.md)** — `~/.glue/config.yaml` user configuration schema
- **[config-store-json.md](reference/config-store-json.md)** — `~/.glue/config.json` runtime state (internal)
- **[session-storage.md](reference/session-storage.md)** — Session files: `meta.json`, `conversation.jsonl`, `state.json`

## Design

Design documents for specific features and subsystems.

- **[command-executor.md](design/command-executor.md)** — Unified shell execution (HostExecutor / DockerExecutor)
- **[docker-sandbox.md](design/docker-sandbox.md)** — Docker-sandboxed command execution with mount whitelisting
- **[status-line-improvements.md](design/status-line-improvements.md)** — Status bar semantic grouping and ANSI styling

## Implementation Plans

Step-by-step implementation plans in `plans/`. Recent plans:

- **[pdf-browser-tools-design.md](plans/2026-02-28-pdf-browser-tools-design.md)** — PDF extraction and web browser tool (CDP) design
- **[web-tools-design.md](plans/2026-02-28-web-tools-design.md)** — Web fetch and web search tool implementation
- **[agent-skills-design.md](plans/2026-02-28-agent-skills-design.md)** — agentskills.io skill discovery, registry, and tool
- **[provider-registry-refactor.md](plans/2026-02-28-provider-registry-refactor.md)** — LLM provider registry and model catalog refactor
- **[mistral-provider.md](plans/2026-02-28-mistral-provider.md)** — Mistral LLM provider support
- **[multimodal-tool-results.md](plans/2026-02-28-multimodal-tool-results.md)** — Multimodal (image) tool result support
- **[tool-call-ui-feedback.md](plans/2026-02-28-tool-call-ui-feedback.md)** — Tool call UI rendering improvements

See `plans/` for the complete list including earlier plans for bash mode, panel modals, worktree commands, session resume, and TUI infrastructure.
