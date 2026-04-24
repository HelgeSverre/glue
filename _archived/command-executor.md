# CommandExecutor — Unified Shell Execution

## Problem

Shell commands are executed in 3 independent call sites, all hardcoded to `Process.start('sh', ['-c', command])`:

1. **`BashTool.execute()`** — `lib/src/agent/tools.dart:168` (agent tool, capture mode + timeout)
2. **`ShellJobManager.start()`** — `lib/src/shell/shell_job_manager.dart:59` (background jobs, streaming)
3. **`App._runBlockingBash()`** — `lib/src/app.dart:1024` (bash mode, blocking capture)

This means:

- User's preferred shell is ignored (no aliases, no shell functions)
- No way to swap execution backend (host vs Docker)
- Shell configuration logic would need to be duplicated 3 times

## Design

### Architecture

```
                    ┌─────────────────────┐
                    │   CommandExecutor    │  (abstract)
                    │                     │
                    │  runCapture()       │ → CaptureResult
                    │  startStreaming()   │ → RunningCommand
                    └─────────┬───────────┘
                              │
                    ┌─────────┴───────────┐
                    │                     │
           ┌────────────────┐   ┌─────────────────┐
           │  HostExecutor  │   │ DockerExecutor   │
           │                │   │                  │
           │  Uses user's   │   │  Uses docker run │
           │  preferred     │   │  with bind       │
           │  shell         │   │  mounts          │
           └────────────────┘   └──────────────────┘
```

### API

```dart
/// Result of a captured command execution.
class CaptureResult {
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Handle to a running/streaming command.
class RunningCommand {
  final Process process;

  Stream<String> get stdout;
  Stream<String> get stderr;
  Future<int> get exitCode;
  Future<void> kill();
}

/// Unified command execution interface.
abstract class CommandExecutor {
  /// Run a command, capture all output, return when done.
  Future<CaptureResult> runCapture(String command, {Duration? timeout});

  /// Start a command and return a streaming handle.
  Future<RunningCommand> startStreaming(String command);
}
```

### Call Site Migration

| Call Site                 | Current                                             | New                                                 |
| ------------------------- | --------------------------------------------------- | --------------------------------------------------- |
| `BashTool.execute()`      | `Process.start('sh', ['-c', cmd])` + manual capture | `executor.runCapture(cmd, timeout: ...)`            |
| `ShellJobManager.start()` | `Process.start('sh', ['-c', cmd])`                  | `executor.startStreaming(cmd)` → wrap in `ShellJob` |
| `App._runBlockingBash()`  | `Process.start('sh', ['-c', cmd])` + manual capture | `executor.runCapture(cmd)`                          |

### Executor Construction

The executor is constructed in `App.create()` based on `GlueConfig`:

```dart
CommandExecutor _buildExecutor(GlueConfig config) {
  if (config.docker.enabled) {
    return DockerExecutor(
      image: config.docker.image,
      containerShell: config.docker.shell,
      mounts: _resolveMounts(config),  // config + session state
      fallbackToHost: config.docker.fallbackToHost,
    );
  }
  return HostExecutor(
    shell: config.shell.executable,
    mode: config.shell.mode,
  );
}
```

The executor is injected into `BashTool`, `ShellJobManager`, and used directly by `App`.

### HostExecutor

Resolves shell binary and builds argument vectors based on `ShellConfig`:

```dart
class HostExecutor implements CommandExecutor {
  final String shell;     // e.g. "zsh", "/bin/bash"
  final ShellMode mode;   // nonInteractive, interactive, login

  List<String> _buildArgs(String command) {
    // Maps (shell, mode) → argument list
    // See config-yaml.md shell-specific argument mapping table
  }
}
```

**Shell detection** (when no explicit config):

1. `Platform.environment['SHELL']` on Unix → use if exists
2. Fallback: `sh` on Unix, `pwsh` → `powershell` → `cmd` on Windows

### DockerExecutor

See [docker-sandbox.md](docker-sandbox.md) for full design.

### Error Handling

- **Shell not found:** `CaptureResult(exitCode: -1, stderr: "Shell 'fish' not found...")` or throw.
- **Docker not available:** If `fallbackToHost`, log warning and delegate to `HostExecutor`. Otherwise return error.
- **Timeout:** Kill process/container, return exit code `-1` with timeout message.

## File Layout

```
lib/src/shell/
├── command_executor.dart    # Abstract interface + CaptureResult + RunningCommand
├── host_executor.dart       # HostExecutor implementation
├── docker_executor.dart     # DockerExecutor implementation
├── shell_config.dart        # ShellConfig, ShellMode, DockerConfig
├── shell_job_manager.dart   # Existing (updated to use CommandExecutor)
└── line_ring_buffer.dart    # Existing (unchanged)
```
