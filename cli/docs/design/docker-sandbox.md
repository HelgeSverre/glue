# Docker Sandbox — Isolated Command Execution

## Overview

An optional execution backend that runs shell commands inside ephemeral Docker containers instead of directly on the host. The container is scoped to whitelisted directories via bind mounts. Enabled via config, CLI flag, or environment variable.

## Container Lifecycle

Each command spawns a new container via `docker run --rm`. No long-lived containers.

```
docker run --rm -i \
  --cidfile /tmp/glue-cid-<uuid> \
  -w /work \
  -v /host/cwd:/work:rw \
  -v /host/shared:/host/shared:rw \
  -v /host/data:/host/data:ro \
  ubuntu:24.04 sh -c "<command>"
```

### Flags

| Flag                       | Purpose                                                   |
| -------------------------- | --------------------------------------------------------- |
| `--rm`                     | Auto-remove container on exit                             |
| `-i`                       | Keep stdin open (no `-t` — no TTY, breaks output capture) |
| `--cidfile <path>`         | Write container ID to file for reliable termination       |
| `-w /work`                 | Set working directory inside container                    |
| `-v host:container[:mode]` | Bind mount directories                                    |

### Why no `-t`?

The TUI tool execution does not allocate a real TTY. Using `-t` causes Docker to inject carriage returns and other TTY artifacts into captured output, corrupting results.

## Mount Strategy

### CWD Mount

The current working directory is **always** mounted at `/work` and set as the container's working directory. This is implicit — the user doesn't need to whitelist it.

### Whitelisted Directory Mounts

Additional directories are mounted **at their original absolute host path** inside the container. This preserves path references in commands:

```yaml
# Config: mounts: ["/Users/helge/code/shared-libs"]
# Result: -v /Users/helge/code/shared-libs:/Users/helge/code/shared-libs:rw
```

### Mount Resolution Order

Mounts are merged from three sources (later overrides earlier for same path):

1. **CWD** — always mounted at `/work` (rw)
2. **Config file** — `docker.mounts` in `~/.glue/config.yaml` (persistent)
3. **Session state** — `docker.mounts` in `state.json` (session-scoped)

Deduplication is by canonical (resolved) host path. If config says `:ro` and session says `rw` for the same path, session wins.

### Mount Validation

Before mounting, each path is:

1. Checked to be an **absolute path** (reject relative paths)
2. Checked to **exist on the host** and be a **directory**
3. **Canonicalized** (symlinks resolved via `resolveSymbolicLinksSync()`)
4. Checked for **no dangerous mounts** (`/`, `~` root — warn and require explicit confirmation)

## Session-Scoped Mounts

Users can add directories to the whitelist during a session. These persist in `state.json` and survive session resume but are not global.

### Adding Mounts

Via TUI slash command (future):

```
/mount add /path/to/dir          # add rw mount
/mount add /path/to/dir:ro       # add ro mount
/mount list                      # show all active mounts
/mount remove /path/to/dir       # remove session mount
```

Via agent tool approval flow: when a command references a path outside mounted directories, the agent could request mount approval (future enhancement).

### Storage

Session mounts stored in `~/.glue/sessions/<id>/state.json`:

```json
{
  "version": 1,
  "docker": {
    "mounts": [{ "host_path": "/abs/path", "mode": "rw", "added_at": "..." }]
  }
}
```

## Docker Availability

### Detection

On executor construction, check Docker availability:

```dart
Future<bool> _checkDocker() async {
  final result = await Process.run('docker', ['--version']);
  return result.exitCode == 0;
}
```

### Fallback Behavior

If Docker is not available:

- **`fallback_to_host: true`** (default): Log a warning system message ("Docker not available, running on host"), delegate to `HostExecutor`.
- **`fallback_to_host: false`**: Return error result ("Docker is required but not available").

## Termination

### Foreground Commands (runCapture)

1. Timeout fires → read container ID from cidfile
2. `docker stop -t 5 <cid>` (SIGTERM, 5s grace)
3. If still running: `docker kill <cid>` (SIGKILL)
4. Clean up cidfile

### Background Jobs (startStreaming)

The `docker run` process is managed like any host process by `ShellJobManager`. On kill:

1. `RunningCommand.kill()` reads cidfile
2. `docker stop <cid>` → grace period → `docker kill <cid>`
3. The `docker run` process exits naturally after container stops

### App Shutdown

`ShellJobManager.shutdown()` kills all running jobs, which triggers Docker container cleanup for any Docker-backed jobs.

## Interaction with Shell Config

| Setting            | HostExecutor | DockerExecutor                                   |
| ------------------ | ------------ | ------------------------------------------------ |
| `shell.executable` | ✅ Used      | ❌ Ignored (container may not have it)           |
| `shell.mode`       | ✅ Used      | ❌ Ignored (always non-interactive in container) |
| `docker.shell`     | ❌ N/A       | ✅ Used as shell inside container                |

The host shell config and Docker shell config are intentionally independent. The container's base image may not have the user's preferred shell installed.

## Security Considerations

- **Default mount mode: `rw`** — matches host behavior. Consider defaulting to `ro` in future for untrusted commands.
- **No network isolation** initially — containers have network access. Future: `--network none` option.
- **File ownership:** Container writes may be root-owned on Linux. Document this limitation. Future: `--user $(id -u):$(id -g)` option.
- **Path canonicalization:** Always resolve symlinks before mounting to prevent escapes.
- **No auto-mounting of `~` or `/`:** Reject or require explicit confirmation.

## Configuration

See [config-yaml.md](../reference/config-yaml.md) `docker` section for full schema.
