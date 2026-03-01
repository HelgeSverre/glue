# Docker Sandbox

Run shell commands inside a Docker container for isolation. When enabled, the `bash` tool executes commands inside the container instead of on the host.

## Enable

```yaml
# ~/.glue/config.yaml
docker:
  enabled: true
  image: "ubuntu:24.04"          # default image
  shell: "sh"                    # shell inside the container
  fallback_to_host: true         # fall back to host if Docker unavailable
  mounts:
    - "/home/me/project:/workspace:rw"
```

Or via environment variable:

```bash
export GLUE_DOCKER_ENABLED=1
```

## Mount Syntax

Mounts follow Docker's `-v` syntax:

| Spec | Result |
|---|---|
| `/host/path` | Read-write, same container path |
| `/host/path:/container/path` | Read-write, explicit container path |
| `/host/path:ro` | Read-only, same container path |
| `/host/path:/container/path:ro` | Read-only, explicit container path |

::: info Note
If Docker is enabled but unavailable (e.g. daemon not running), Glue falls back to host execution when `fallback_to_host` is `true` (the default).
:::

## See also

- [DockerConfig](/api/shell/docker-config)
- [DockerExecutor](/api/shell/docker-executor)
- [ExecutorFactory](/api/shell/executor-factory)
