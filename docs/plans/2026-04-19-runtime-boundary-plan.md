# Runtime Boundary Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19
Last revised: 2026-04-30 (re-spec'd against the four-layer harness/strategies/core split landed in `claude/architect-harness-layers-maSVJ`)

## Goal

Clarify the boundary between Glue and the place where work executes.

Glue currently supports host shell execution, Docker shell execution, local
and Docker browser backends, and cloud browser providers. Future cloud
runtimes such as E2B, Daytona, Fly.io Sprites, Modal, or SSH workers should
fit into the same conceptual model without forcing a large rewrite.

Do not over-abstract prematurely. Use the existing host/Docker implementation
as the concrete base, then extract only the parts needed for the first remote
runtime.

## How this plan relates to the harness layers

After the harness extraction (see `2026-04-29-harness-layers.md`), the
runtime story has a clear home:

- **Strategy interfaces** (`packages/glue_strategies/`) own
  `CommandExecutor`, `BrowserEndpointProvider`, and the future
  `ExecutionRuntime`. These are pluggable contracts.
- **Harness** (`packages/glue_harness/`) owns the agent loop, tool registry,
  session log, and `ShellJobManager` — the consumers that talk to a runtime
  through strategy interfaces only.
- **Surfaces** (`cli/`, `glue_server/`) never reach into runtime internals;
  they observe lifecycle through `SessionEvent`s.

Consequence: every type the runtime layer exposes to the outside world is a
strategy contract or a `glue_core` data type. New cloud runtimes ship as
separate packages depending only on `glue_strategies` + `glue_core`.

## Historical Context — Docker Sandbox (shipped)

The docker sandbox work originally tracked in
`docs/plans/done/2026-02-27-docker-sandbox.md` is complete. Current state, as
of 2026-04-30:

- `DockerConfig` + `MountEntry` data model — `packages/glue_strategies/lib/src/shell/docker_config.dart`
- `DockerExecutor` with cidfile-based container lifecycle — `packages/glue_strategies/lib/src/shell/docker_executor.dart`
- `ExecutorFactory` with host-fallback logic — `packages/glue_strategies/lib/src/shell/executor_factory.dart`
- `SessionState` persisting per-session mount whitelist — `packages/glue_harness/lib/src/storage/session_state.dart`
- `docker.*` config parsed from YAML + env (`GLUE_DOCKER_ENABLED`, `GLUE_DOCKER_IMAGE`, `GLUE_DOCKER_SHELL`, `GLUE_DOCKER_MOUNTS`)
- Wired through `ServiceLocator.create()` (`packages/glue_harness/lib/src/core/service_locator.dart`)
- Barrel exports in `packages/glue_strategies/lib/glue_strategies.dart`
- `runtime-capabilities.yaml` marks `host` and `docker` as `status: shipping`

The remaining work is the boundary-hardening described below, not new sandbox
functionality.

## Current Code Context

Relevant files (post-extraction paths):

- `packages/glue_strategies/lib/src/shell/command_executor.dart`
- `packages/glue_strategies/lib/src/shell/host_executor.dart`
- `packages/glue_strategies/lib/src/shell/docker_executor.dart`
- `packages/glue_strategies/lib/src/shell/executor_factory.dart`
- `packages/glue_strategies/lib/src/shell/docker_config.dart`
- `packages/glue_harness/lib/src/agent/shell_job_manager.dart` (data-driven service, lives in harness — see harness-layers step #5)
- `packages/glue_strategies/lib/src/web/browser/browser_manager.dart`
- `packages/glue_strategies/lib/src/web/browser/browser_endpoint.dart`
- `packages/glue_strategies/lib/src/web/browser/providers/docker_browser_provider.dart`
- `packages/glue_strategies/lib/src/web/browser/providers/browserbase_provider.dart`
- `packages/glue_strategies/lib/src/web/browser/providers/browserless_provider.dart`
- `packages/glue_strategies/lib/src/web/browser/providers/steel_provider.dart`
- `packages/glue_harness/lib/src/core/service_locator.dart`
- `packages/glue_harness/lib/src/storage/session_state.dart`
- `docs/design/docker-sandbox.md`
- `docs/reference/runtime-capabilities.yaml`

Current shape:

- `CommandExecutor` has `runCapture` and `startStreaming`.
- `HostExecutor` runs commands on the local host.
- `DockerExecutor` runs one `docker run --rm` per command with cwd mounted at
  `/workspace`.
- `ShellJobManager` manages background command lifecycle, but stores a raw
  `Process` (`ShellJob.process`), which makes non-process remote runtimes
  harder.
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

## Universal Workspace Path: `/workspace`

Across every runtime — Docker, cloud sandboxes, future SSH workers — the
user's working tree is exposed at the container/VM path **`/workspace`**.

- **Docker** bind-mounts host cwd at `/workspace` (`-v $cwd:/workspace:rw`).
- **Cloud runtimes** git-clone or rsync the workspace into `/workspace`.
- Agent prompts and tool error messages reference `/workspace` without
  branching on backend.

This aligns with VibeKit, E2B, Daytona, and Sprites defaults. Migration
landed 2026-04-19: see
`packages/glue_strategies/lib/src/shell/docker_executor.dart` +
`docs/design/docker-sandbox.md`.

## Boundary Shape

Keep `CommandExecutor` for now, but plan toward a broader `Runtime` contract.

Possible future strategy interface (design target; do not implement until a
second remote runtime needs it). It lives in `glue_strategies` and depends
only on `glue_core` data types:

```dart
// packages/glue_strategies/lib/src/runtime/execution_runtime.dart (future)
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
  Future<Uri> getHost(int port);
  Future<List<RuntimeArtifact>> collectArtifacts();
  Future<void> close();
}
```

The `getHost(port)` method is lifted from VibeKit: the runtime returns a
reachable URL for any TCP port running inside the sandbox. Lets agents spawn
dev servers / preview apps without leaking backend-specific plumbing.

The harness consumes `ExecutionRuntime` through `ServiceLocator`; tools see
only `RuntimeSession`. No surface code (CLI, ACP server) imports this
interface.

## Immediate Cleanup Before Cloud Runtimes

### 1. Decouple Background Jobs From `Process`

`ShellJob` currently stores `Process`. That makes remote command handles
awkward.

Introduce a `glue_core` data type and a strategy-side handle:

```dart
// packages/glue_core/lib/src/running_command.dart (future)
abstract class RunningCommandHandle {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  Future<void> kill();
}
```

`HostExecutor` and `DockerExecutor` (in `glue_strategies`) implement this for
process-backed commands. `ShellJob` (in `glue_harness/agent/`) stores the
abstract handle, not `Process`.

Tracked as **task-26.1**.

### 2. Emit Runtime Events As `SessionEvent`s

Command and container lifecycle should be `SessionEvent` variants in
`glue_core/session_event.dart`, not bespoke JSONL rows:

- `RuntimeCommandStartedEvent`
- `RuntimeCommandOutputEvent`
- `RuntimeCommandCompletedEvent`
- `RuntimeCommandFailedEvent`
- `RuntimeCommandCancelledEvent`
- `RuntimeContainerStartedEvent`
- `RuntimeContainerStoppedEvent`

Each event carries: `runtimeId` (host/docker/<cloud>), `sessionId`,
`workspaceMapping` (host cwd ↔ runtime cwd), `command` (truncated),
`exitCode`, `durationMs`. Inheriting `SessionEvent` gets persistence + ACP
forwarding for free.

This makes local, Docker, and remote behavior replayable across surfaces.
Tracked as **task-26.3**.

### 3. Normalize Workspace Mapping

Today Docker mounts cwd at `/workspace` (universal path — see section
above). Codify this as a first-class type in `glue_core`:

```dart
// packages/glue_core/lib/src/workspace_mapping.dart (future)
class WorkspaceMapping {
  final String hostCwd;        // e.g. /Users/helge/code/glue
  final String runtimeCwd;     // always /workspace
  final List<MountEntry> additionalMounts;
  final String artifactsDir;   // e.g. /workspace/.glue/artifacts
}
```

Host path ↔ runtime path translation rules:

- Paths inside `hostCwd` → translate to `/workspace/<relative>`.
- Paths under additional mounts → translate using the mount's target path.
- Paths elsewhere → reject at tool layer (don't silently mount).

Remote runtimes will need the same mapping. Tracked as **task-26.2**.

### 4. Separate Browser Runtime From Browser Provider

Browser providers currently provision CDP endpoints. That is fine, but cloud
execution runtimes may also offer browsers (E2B `browser` template, hopx
Chrome, Daytona Computer Use).

Keep `BrowserEndpointProvider` as a strategy interface, but allow a
`RuntimeSession` to provide one too via a `BrowserEndpointSource` union.
The browser tool (`glue_harness/tools/web_browser_tool.dart`) should not
care whether the endpoint came from local, Docker-browser, Browserbase,
Steel, or a future runtime. Tracked as **task-26.4**.

## VibeKit Patterns To Adopt

Pulled from VibeKit SDK (`docs.vibekit.sh`) — the patterns worth stealing
now, during boundary work, not later:

### Return a runtime handle on every call

VibeKit's `executeCommand` returns `{ sandboxId, stdout, stderr, exitCode }`.
The `sandboxId` lets a client always reattach to the warm sandbox. For Glue:
add `runtimeId` and `sessionId` fields to `CaptureResult` (in
`glue_strategies/shell/command_executor.dart`). Trivial, opens the door to
session-pinned commands later.

### `getHost(port)` as the escape hatch

When an agent starts a dev server inside the sandbox, the user needs a URL.
VibeKit exposes `getHost(port) → Promise<string>`. Bake this into the future
`RuntimeSession` interface (see "Boundary Shape"). Not needed for host
executor (ports are already local); needed the moment we have a remote
runtime.

### Git as the workspace-sync protocol

VibeKit leans on `.withGithub({ token, repository })` plus a `branch`
parameter — the sandbox **clones** the repo rather than uploading a tarball.
For host and Docker this is moot (bind mount). For cloud runtimes this is
the cheapest, most debuggable default. Aligns with Cloud Runtimes Plan
Option D.

### Ephemeral-by-default, persistent-opt-in

Only Northflank opts into persistence in the VibeKit world. Glue already
does this (Docker runs `--rm`); make it explicit in the capability table
and the default for any cloud adapter.

### Read-only "Ask Mode" as a capability flag

VibeKit's `mode: "ask"` disables filesystem writes. Single flag, high
leverage — 80% of the safety surface without a full capability DSL. Add
this as a runtime-independent toggle so host/Docker/cloud all honor it via
the `CommandExecutor` layer (surface as a pre-command predicate that blocks
write-ish commands). Scope: small spike after task-26.1 lands.

### Provider factories in separate packages

When cloud runtimes land, ship each adapter as a separate pub package
(`glue_e2b`, `glue_daytona`, etc.) depending only on `glue_strategies` +
`glue_core`. Keeps `glue_harness` and `cli/` free of cloud SDK
dependencies — and matches the strategy-package pattern already used by
`glue_strategies` itself.

## Runtime Capabilities

Source of truth: `docs/reference/runtime-capabilities.yaml`.

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
  persistent: false
  ask_mode: true
```

The UI and tools should use capability checks rather than runtime-name checks.
Tracked as **task-26.5**.

## Config Shape

Near-term config stays Docker-concrete:

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

Later remote config (illustrative — do not implement until cloud runtimes
plan activates):

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
  daytona-work:
    adapter: daytona
    image: glue/default:latest
    api_key: env:DAYTONA_API_KEY
```

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
isolation level rather than implying it is safe for all malware/reversing
work.

## Implementation Plan

1. Change `ShellJob` (in `glue_harness/agent/shell_job_manager.dart`) to
   store a `RunningCommandHandle` interface from `glue_core` instead of
   `Process`. (task-26.1)
2. Keep `CommandExecutor` (in `glue_strategies/shell/`) as the concrete
   command API for host/Docker. Add `runtimeId` and `sessionId` fields to
   `CaptureResult`.
3. Promote runtime/session metadata to typed `SessionEvent` variants in
   `glue_core/session_event.dart`. (task-26.3)
4. Document path mapping for Docker in the Docker sandbox docs; introduce
   `WorkspaceMapping` type in `glue_core`. (task-26.2)
5. Make browser endpoint acquisition runtime-aware without breaking existing
   browser providers (`BrowserEndpointSource` in `glue_strategies/web/`).
   (task-26.4)
6. Add a runtime capability table to docs and website. (task-26.5)
7. Add read-only Ask Mode flag honored by host and Docker executors at the
   `CommandExecutor` boundary. (new scope — follow-up task)
8. When implementing the first remote runtime, extract `ExecutionRuntime`
   into `glue_strategies/runtime/` from real duplication. (cloud runtimes
   plan)

## Tests

Test files live alongside their owning package:

- `packages/glue_strategies/test/shell/...` for executor + handle behavior
- `packages/glue_harness/test/agent/shell_job_manager_test.dart` for
  background-job kill semantics
- `packages/glue_core/test/session_event_test.dart` for new runtime event
  shapes
- `packages/glue_strategies/test/web/browser/...` for browser endpoint
  source unification

Add tests for:

- background job kill calls the handle's `kill`, not raw process kill
- Docker path mapping is stable (`$cwd → /workspace`, paths outside cwd
  rejected)
- runtime command lifecycle emits typed `SessionEvent`s with runtime ID and
  cwd mapping
- runtime output is bounded and artifacted when long
- Docker cleanup runs on cancel and timeout
- browser endpoint can come from provider or runtime
- Ask Mode blocks write-ish commands at the executor boundary

## Acceptance Criteria

- Host and Docker behavior remain unchanged (except `/workspace` path).
- Background jobs no longer depend directly on `Process`.
- Typed `SessionEvent`s record where commands ran and stream uniformly to
  all surfaces (CLI + ACP server).
- Docker sandbox docs accurately describe isolation limits.
- First remote runtime can be added as a separate package depending only on
  `glue_strategies` + `glue_core`, without changes to `glue_harness` or
  `cli/`.

## Open Questions

- Should remote runtimes sync the full workspace, only selected files, or use
  a mounted git checkout? → Leading: Option D from Cloud Runtimes Plan
  (git-first + persistence opt-in).
- Should cloud runtime credentials share `CredentialStore` (in
  `glue_strategies/credentials/`)?
- Should runtime selection be per-session, per-tool, or global config?
- Should browser sessions be owned by runtime sessions or remain independent?
- Should Ask Mode be session-wide, per-command, or both?
