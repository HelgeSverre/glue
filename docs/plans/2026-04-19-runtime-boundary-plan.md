# Runtime Boundary Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Clarify the boundary between Glue and the place where work executes.

Glue currently supports host shell execution, Docker shell execution, local and
Docker browser backends, and cloud browser providers. Future cloud runtimes
such as E2B, Modal, Daytona, SSH workers, or custom containers should fit into
the same conceptual model without forcing a large rewrite.

Do not over-abstract prematurely. Use the existing host/Docker implementation
as the concrete base, then extract only the parts needed for the first remote
runtime.

## Current Code Context

Relevant files:

- `lib/src/shell/command_executor.dart`
- `lib/src/shell/host_executor.dart`
- `lib/src/shell/docker_executor.dart`
- `lib/src/shell/executor_factory.dart`
- `lib/src/shell/docker_config.dart`
- `lib/src/shell/shell_job_manager.dart`
- `lib/src/web/browser/browser_manager.dart`
- `lib/src/web/browser/browser_endpoint.dart`
- `lib/src/web/browser/providers/docker_browser_provider.dart`
- `lib/src/web/browser/providers/browserbase_provider.dart`
- `lib/src/web/browser/providers/browserless_provider.dart`
- `lib/src/web/browser/providers/steel_provider.dart`
- `lib/src/core/service_locator.dart`
- `lib/src/storage/session_state.dart`
- `docs/design/docker-sandbox.md`
- `docs/plans/2026-02-27-docker-sandbox.md`

Current shape:

- `CommandExecutor` has `runCapture` and `startStreaming`.
- `HostExecutor` runs commands on the local host.
- `DockerExecutor` runs one `docker run --rm` per command with cwd mounted at
  `/work`.
- `ShellJobManager` manages background command lifecycle, but stores a raw
  `Process`, which makes non-process remote runtimes harder.
- Browser backends already have a separate `BrowserEndpointProvider` interface.
- Docker shell and Docker browser are separate implementations today.

## Desired Runtime Ladder

```text
host -> Docker -> remote container/runtime
```

Each step should answer the same questions:

- where is the workspace?
- how are commands executed?
- how are files read/written?
- how are secrets passed?
- how are browser sessions created?
- how is output streamed?
- how is work cancelled?
- how are artifacts copied back?
- how is cleanup guaranteed?

## Boundary Shape

Keep `CommandExecutor` for now, but plan toward a broader `Runtime` contract.

Possible future interface:

```dart
abstract class ExecutionRuntime {
  String get id;
  RuntimeCapabilities get capabilities;

  Future<RuntimeSession> start(RuntimeStartRequest request);
}

abstract class RuntimeSession {
  String get sessionId;
  Future<RunningCommandHandle> startCommand(CommandRequest request);
  Future<CaptureResult> runCapture(CommandRequest request);
  Future<RuntimeFile> readFile(String path);
  Future<void> writeFile(String path, List<int> bytes);
  Future<BrowserEndpoint?> getBrowser();
  Future<List<RuntimeArtifact>> collectArtifacts();
  Future<void> close();
}
```

Do not implement this full interface until a second non-Docker runtime needs it.
For now, use it as a design target.

## Immediate Cleanup Before Cloud Runtimes

### 1. Decouple Background Jobs From `Process`

`ShellJob` currently stores `Process`. That makes remote command handles
awkward.

Introduce:

```dart
abstract class RunningCommandHandle {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  Future<void> kill();
}
```

`RunningCommand` can implement this for local/Docker process-backed commands.
`ShellJob` should store `RunningCommandHandle`, not `Process`.

### 2. Emit Runtime Events To Session JSONL

Command and container lifecycle should write events:

- `runtime.command.started`
- `runtime.command.output`
- `runtime.command.completed`
- `runtime.command.failed`
- `runtime.command.cancelled`
- `runtime.container.started`
- `runtime.container.stopped`

This makes local, Docker, and remote behavior replayable.

### 3. Normalize Workspace Mapping

Today Docker mounts cwd at `/work`.

Write down:

- host cwd
- runtime cwd
- path translation rules
- writable/read-only mounts
- artifact output directory

Remote runtimes will need the same mapping.

### 4. Separate Browser Runtime From Browser Provider

Browser providers currently provision CDP endpoints. That is fine, but cloud
execution runtimes may also offer browsers.

Keep `BrowserEndpointProvider`, but allow a runtime session to provide one too.
The browser tool should not care whether the endpoint came from local,
Docker-browser, Browserbase, Steel, or a future runtime.

## Runtime Capabilities

Suggested capabilities:

```yaml
capabilities:
  command_capture: true
  command_streaming: true
  background_jobs: true
  filesystem_read: true
  filesystem_write: true
  mount_host_paths: true
  browser_cdp: true
  artifacts: true
  secrets: true
  snapshots: false
  internet: true
  gpu: false
```

The UI and tools should use capability checks rather than runtime-name checks.

## Config Shape

Near-term config should keep Docker concrete:

```yaml
runtime:
  default: host

docker:
  enabled: true
  image: ubuntu:24.04
  shell: sh
  fallback_to_host: false
  mounts:
    - /Users/helge/code/shared:/shared:ro
```

Later remote config:

```yaml
runtimes:
  default: docker
  docker:
    adapter: docker
    image: ubuntu:24.04
  e2b-work:
    adapter: e2b
    image: glue/default:latest
    api_key: env:E2B_API_KEY
  modal-lab:
    adapter: modal
    app: glue-runtime
    api_key: env:MODAL_TOKEN_ID
```

Do not add the later shape until there is an implementation target.

## Security And Isolation Questions

For every runtime, define:

- network access on/off
- host mounts and write permissions
- secret injection rules
- cleanup after cancellation
- artifact retention
- max runtime duration
- max output size
- whether untrusted files can be opened by tools

Docker is not a complete security sandbox by default. Document the exact
isolation level rather than implying it is safe for all malware/reversing work.

## Implementation Plan

1. Change `ShellJob` to store a command handle interface instead of `Process`.
2. Keep `CommandExecutor` as the concrete command API for host/Docker.
3. Add runtime/session metadata to session JSONL command events.
4. Document path mapping for Docker in the Docker sandbox docs.
5. Make browser endpoint acquisition runtime-aware without breaking existing
   browser providers.
6. When implementing the first remote runtime, extract `ExecutionRuntime` from
   real duplication.
7. Add a runtime capability table to docs and website.

## Tests

Add tests for:

- background job kill calls the handle's `kill`, not raw process kill
- Docker path mapping is stable
- command events include runtime ID and cwd mapping
- runtime output is bounded and artifacted when long
- Docker cleanup runs on cancel and timeout
- browser endpoint can come from provider or runtime

## Acceptance Criteria

- Host and Docker behavior remain unchanged.
- Background jobs no longer depend directly on `Process`.
- JSONL records where commands ran.
- Docker sandbox docs accurately describe isolation limits.
- First remote runtime can be added without rewriting app/tool code.

## Open Questions

- Should remote runtimes sync the full workspace, only selected files, or use a
  mounted git checkout?
- Should cloud runtime credentials share the provider credential store?
- Should runtime selection be per-session, per-tool, or global config?
- Should browser sessions be owned by runtime sessions or remain independent?
