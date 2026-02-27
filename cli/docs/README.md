# Glue CLI Documentation

## Reference

Schemas and formats for Glue's configuration and data files.

- **[glue-home-layout.md](reference/glue-home-layout.md)** — `~/.glue/` directory structure and file lifecycle
- **[config-yaml.md](reference/config-yaml.md)** — `~/.glue/config.yaml` user configuration schema
- **[config-store-json.md](reference/config-store-json.md)** — `~/.glue/config.json` runtime state (internal)
- **[session-storage.md](reference/session-storage.md)** — Session files: `meta.json`, `conversation.jsonl`, `state.json`

## Design

Architecture and design documents for major features.

- **[command-executor.md](design/command-executor.md)** — Unified shell execution (HostExecutor / DockerExecutor)
- **[docker-sandbox.md](design/docker-sandbox.md)** — Docker-sandboxed command execution with mount whitelisting

## Implementation Plans

Step-by-step implementation plans in `plans/`.
