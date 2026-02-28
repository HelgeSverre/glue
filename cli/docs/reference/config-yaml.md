# `~/.glue/config.yaml` — User Configuration Schema

User-edited YAML configuration file. Loaded at startup by `GlueConfig.load()` (`lib/src/config/glue_config.dart`).

> All sections below are implemented and live.

**Resolution order:** CLI args → environment variables → config.yaml → defaults.

## Full Schema

```yaml
# LLM Provider: anthropic | openai | ollama
provider: anthropic

# Model name (provider-specific)
model: claude-sonnet-4-6

# Provider credentials
anthropic:
  api_key: sk-ant-...

openai:
  api_key: sk-...

# Ollama configuration (local, no API key needed)
ollama:
  base_url: http://localhost:11434 # default

# Agent profiles — named provider+model pairs for subagents
profiles:
  fast:
    provider: anthropic
    model: claude-haiku-4
  local:
    provider: ollama
    model: llama3.2

# Bash/shell tool configuration
bash:
  max_lines: 50 # max output lines shown for blocking bash commands

# Shell execution configuration
shell:
  executable: zsh # shell binary: bash, zsh, fish, pwsh, sh (default: $SHELL or sh)
  mode: non_interactive # non_interactive | interactive | login

# Docker sandbox configuration
docker:
  enabled: false # enable Docker-sandboxed command execution
  image: ubuntu:24.04 # base image for containers
  shell: sh # shell inside the container (independent of host shell)
  fallback_to_host: true # fall back to host execution if Docker unavailable
  mounts: # persistent directory whitelist (always mounted)
    - /path/to/shared/libs
    - /path/to/data:ro # append :ro for read-only
```

## Field Reference

### Top-Level

| Field      | Type   | Default      | Env Override    | CLI Override | Description  |
| ---------- | ------ | ------------ | --------------- | ------------ | ------------ |
| `provider` | string | `anthropic`  | `GLUE_PROVIDER` | `--provider` | LLM provider |
| `model`    | string | per-provider | `GLUE_MODEL`    | `--model`    | Model name   |

### `anthropic` / `openai`

| Field     | Type   | Default | Env Override                                   | Description |
| --------- | ------ | ------- | ---------------------------------------------- | ----------- |
| `api_key` | string | —       | `ANTHROPIC_API_KEY` / `GLUE_ANTHROPIC_API_KEY` | API key     |
|           |        |         | `OPENAI_API_KEY` / `GLUE_OPENAI_API_KEY`       |             |

### `bash`

| Field       | Type | Default | Env Override | Description                                 |
| ----------- | ---- | ------- | ------------ | ------------------------------------------- |
| `max_lines` | int  | `50`    | —            | Max output lines for blocking bash commands |

### `shell`

| Field        | Type   | Default           | Env Override      | CLI Override   | Description               |
| ------------ | ------ | ----------------- | ----------------- | -------------- | ------------------------- |
| `executable` | string | `$SHELL` or `sh`  | `GLUE_SHELL`      | `--shell`      | Shell binary name or path |
| `mode`       | string | `non_interactive` | `GLUE_SHELL_MODE` | `--shell-mode` | Execution mode            |

**Mode values:**

- `non_interactive` — `['-c', command]`. No rc files loaded. Safest default.
- `interactive` — `['-i', '-c', command]`. Loads `~/.bashrc`/`~/.zshrc`/`config.fish`. Enables aliases and shell functions.
- `login` — `['-l', '-c', command]`. Loads login profile files.

**Shell-specific argument mapping:**

| Shell | non_interactive                | interactive         | login                 |
| ----- | ------------------------------ | ------------------- | --------------------- |
| sh    | `sh -c CMD`                    | `sh -c CMD`         | `sh -c CMD`           |
| bash  | `bash -c CMD`                  | `bash -i -c CMD`    | `bash -l -c CMD`      |
| zsh   | `zsh -c CMD`                   | `zsh -i -c CMD`     | `zsh -l -c CMD`       |
| fish  | `fish -c CMD`                  | `fish -i -c CMD`    | `fish --login -c CMD` |
| pwsh  | `pwsh -NoProfile -Command CMD` | `pwsh -Command CMD` | `pwsh -Command CMD`   |

### `docker`

| Field              | Type   | Default        | Env Override            | CLI Override                  | Description                     |
| ------------------ | ------ | -------------- | ----------------------- | ----------------------------- | ------------------------------- |
| `enabled`          | bool   | `false`        | `GLUE_DOCKER_ENABLED=1` | `--docker` / `--no-docker`    | Enable Docker sandbox           |
| `image`            | string | `ubuntu:24.04` | `GLUE_DOCKER_IMAGE`     | `--docker-image`              | Container base image            |
| `shell`            | string | `sh`           | `GLUE_DOCKER_SHELL`     | `--docker-shell`              | Shell inside container          |
| `fallback_to_host` | bool   | `true`         | —                       | `--docker-fallback-to-host`   | Fall back if Docker unavailable |
| `mounts`           | list   | `[]`           | `GLUE_DOCKER_MOUNTS`    | `--docker-mount` (repeatable) | Persistent directory whitelist  |

**Mount format:** Supports several forms:

- `/host/path` — mount read-write at same path inside container
- `/host/path:ro` — mount read-only at same path
- `/host/path:/container/path` — mount at a different container path (read-write)
- `/host/path:/container/path:ro` — mount at a different container path (read-only)

Host paths must be absolute. Container paths must be absolute POSIX paths. CWD is always mounted automatically at `/work`.

**`GLUE_DOCKER_MOUNTS` format:** Semicolon-separated specs, e.g. `/path/one;/path/two:ro;/host:/container:rw`.
