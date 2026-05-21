# Cloud Runtimes — Daytona V1 Implementation Plan

## Context

Glue currently executes work in two places: the user's host shell (`HostExecutor`) and an ephemeral Docker container (`DockerExecutor`). The product is positioned for cloud runtimes (E2B / Daytona / Sprites etc.) but the prerequisite refactoring (the "task-26 runtime boundary prep" described in `docs/plans/2026-04-19-runtime-boundary-plan.md`) has not landed, and the cloud runtimes plan itself (`docs/plans/2026-04-19-cloud-runtimes-plan.md`) is marked deferred.

A code audit (this session) found one major gap the existing plans don't address: **`ReadFileTool`, `WriteFileTool`, `EditFileTool`, `ListDirectoryTool`, and `GrepTool` bypass `CommandExecutor` and use `dart:io` / `Process.run` directly** (`packages/glue_harness/lib/src/agent/tools.dart:44, 124, 280, 379, 479`). Docker only works because the host CWD is bind-mounted — for any remote runtime this is a hard break: the file tools would read the user's laptop while bash ran in the cloud. The boundary plan must be extended to route file tools through a runtime-aware handle.

This plan implements that extended boundary refactor end-to-end, then ships **Daytona as the first cloud runtime**. We write the Daytona REST client ourselves — no third-party SDK dependency. Scope decisions confirmed with the user:

- **First adapter:** Daytona (clean REST, native git-clone, persistent FS).
- **Background jobs in cloud:** yes, full parity — `ShellJobManager` must work against Daytona too. Drives the `RunningCommandHandle` refactor.
- **Cloud-provided browser:** out of scope for V1. `BrowserEndpointSource` union and `WebBrowserTool` rewiring are deferred.
- **Website / docs / capability matrix updates:** out of scope for this plan; tracked as a follow-up after the feature works.

The plan is structured as 5 PRs. PRs 1–3 are pure refactors (no user-visible change, mergeable independently). PR 4 ships the Daytona adapter. PR 5 is polish + integration tests.

---

## PR 1 — Decouple background jobs from `Process` + grep fix

**Goal:** `ShellJob` no longer stores `dart:io.Process`. `GrepTool` no longer shells out via `Process.run`.

### Changes

1. **Introduce `RunningCommandHandle` in `glue_core`**
   - New file: `packages/glue_core/lib/src/running_command_handle.dart`
   - Abstract class with `Stream<List<int>> stdout`, `Stream<List<int>> stderr`, `Future<int> exitCode`, `Future<void> kill()`. Mirrors the design sketch in the runtime-boundary plan §"Decouple Background Jobs From `Process`".
   - Export from `packages/glue_core/lib/glue_core.dart`.

2. **`RunningCommand` (in `glue_strategies`) implements `RunningCommandHandle`**
   - Edit `packages/glue_strategies/lib/src/shell/command_executor.dart`:
     - `RunningCommand` (and `DockerRunningCommand` in `docker_executor.dart`) implement the new interface. Their existing `Process process` field stays as a package-private impl detail.
   - Add `runtimeId` (`'host'` | `'docker'`) and `sessionId` fields to `CaptureResult`. Surface concerns can use them later; required by the SessionEvent work in PR 3.

3. **`ShellJobManager` stores the handle, not the process**
   - Edit `packages/glue_harness/lib/src/agent/shell_job_manager.dart`:
     - Replace `final Process process` on `ShellJob` with `final RunningCommandHandle handle`.
     - Replace `job.process.kill(ProcessSignal.sigterm)` calls (lines 179, 197, 203) with `job.handle.kill()`. SIGTERM-then-SIGKILL escalation moves *into* `RunningCommand.kill()` so the manager doesn't need signal types.
     - Replace `process.stdout.transform(...)` / `process.stderr.transform(...)` listeners (lines 117–122) with the equivalent reads from `job.handle.stdout` / `.stderr`.
     - Replace `process.exitCode` await (line 126) with `job.handle.exitCode`.
   - Remove `import 'dart:io'` from `shell_job_manager.dart` (or keep only for `ProcessSignal` if escalation stays here — preference is to push escalation into the handle).

4. **`GrepTool` routes through `CommandExecutor`**
   - Edit `packages/glue_harness/lib/src/agent/tools.dart`:
     - `GrepTool` gains a `CommandExecutor` constructor parameter, matching the `BashTool(this.executor)` pattern at line 156.
     - Replace `Process.run(executable, arguments)` at line 280 with `executor.runCapture('$executable ${args.join(' ')}', timeout: ...)`.
     - Remove the `_which` helper (line 321) — rely on the executor's `command -v rg || command -v grep` instead, or inline the discovery as part of the runCapture command.
   - Edit `packages/glue_harness/lib/src/core/service_locator.dart:168`: `'grep': GrepTool(executor),`.

### Tests

- `packages/glue_strategies/test/shell/` (or `cli/test/shell/` if tests still live there post-split — verify and put new tests next to existing): add `running_command_handle_test.dart` covering the host-side `RunningCommand` implementing the handle interface, kill behavior.
- `packages/glue_harness/test/agent/shell_job_manager_test.dart`: existing kill-on-running-job tests must still pass after the `process` → `handle` migration. Add a fake `RunningCommandHandle` to exercise the manager without a real `Process`.
- Add `grep_tool_test.dart` (next to `bash_tool_test.dart`): assert it constructs a shell command and delegates to the executor, including the rg-vs-grep discovery path.

### Acceptance

- `just check` green.
- No remaining `dart:io.Process` references in `shell_job_manager.dart`.
- No remaining `Process.run` calls in `grep` tool path.

---

## PR 2 — `Workspace` abstraction + `WorkspaceMapping`

**Goal:** File tools (`ReadFile`, `WriteFile`, `EditFile`, `ListDirectory`) route through a `Workspace` handle injected at construction. Behavior unchanged on host/Docker.

### Changes

1. **Introduce `WorkspaceMapping` data type in `glue_core`**
   - New file: `packages/glue_core/lib/src/workspace_mapping.dart`
   - Shape per runtime-boundary plan §"Normalize Workspace Mapping": `String hostCwd`, `String runtimeCwd` (default `/workspace`), `List<MountEntry> additionalMounts`, `String artifactsDir`.
   - Path translation helpers: `String? toRuntimePath(String hostPath)`, `String toHostPath(String runtimePath)`. Paths outside the mapping return `null` from `toRuntimePath` so callers can reject them.
   - Export from `glue_core.dart`.

2. **Introduce `Workspace` interface in `glue_strategies`**
   - New file: `packages/glue_strategies/lib/src/fs/workspace.dart`
   - Abstract class with:
     - `WorkspaceMapping get mapping`
     - `Future<String> readFileAsString(String path, {Encoding? encoding})`
     - `Future<List<int>> readFileAsBytes(String path)`
     - `Future<void> writeFileAsString(String path, String content)`
     - `Future<void> writeFileAsBytes(String path, List<int> bytes)`
     - `Future<bool> exists(String path)`
     - `Future<List<WorkspaceEntry>> list(String path)` — `WorkspaceEntry { String name; bool isDirectory }`
   - Paths are runtime-side paths (e.g. `/workspace/foo.dart`) by convention; implementations translate via `mapping` as needed.

3. **`LocalWorkspace` impl in `glue_strategies`**
   - New file: `packages/glue_strategies/lib/src/fs/local_workspace.dart`
   - `dart:io` passthrough. Handles both host and Docker today (since Docker bind-mounts the host CWD). On read, translates `/workspace/...` to `<hostCwd>/...` via the mapping; on write, same direction. Outside-mapping paths throw `WorkspaceAccessError` (new exception type in same file).
   - Export from `packages/glue_strategies/lib/glue_strategies.dart`.

4. **Refactor file tools to take `Workspace` via constructor**
   - Edit `packages/glue_harness/lib/src/agent/tools.dart`:
     - `ReadFileTool(this.workspace)` — replace `File(path).readAsString()` with `workspace.readFileAsString(path)`.
     - `WriteFileTool(this.workspace)` — replace `File(path).writeAsString(content)` with `workspace.writeFileAsString(path, content)`.
     - `EditFileTool(this.workspace)` — read-modify-write goes through workspace.
     - `ListDirectoryTool(this.workspace)` — replace `Directory(path).listSync()` with `workspace.list(path)`.
   - Remove `import 'dart:io'` from these tools (keep only what `BashTool` still needs).

5. **Construct `LocalWorkspace` and inject in `ServiceLocator`**
   - Edit `packages/glue_harness/lib/src/core/service_locator.dart`:
     - After `executor` is created (line 105), build `final mapping = WorkspaceMapping(hostCwd: resolvedEnv.cwd, runtimeCwd: dockerConfig.enabled ? '/workspace' : resolvedEnv.cwd, ...)`.
     - Build `final workspace = LocalWorkspace(mapping);`.
     - Pass to tool constructors at lines 164–169.
     - Add `workspace` to `AppServices` so surfaces can read it (e.g. for prompt path hints).

6. **Update system prompt to use `mapping.runtimeCwd`** — minor: `Prompts.build` already injects `cwd`. Confirm whether it hard-codes the host cwd or already passes it through. Adjust so agent sees `/workspace` paths when Docker is active.

### Tests

- `packages/glue_core/test/workspace_mapping_test.dart`: path translation, outside-mapping rejection.
- `packages/glue_strategies/test/fs/local_workspace_test.dart`: read/write/list against `Directory.systemTemp.createTempSync()` fixtures; mapping-aware paths.
- Existing `read_file_tool_test.dart` / `write_file_tool_test.dart` / `edit_file_tool_test.dart` / `list_directory_tool_test.dart` (or `cli/test/tools/...` equivalents): updated to construct a `LocalWorkspace` over a temp dir and pass it into the tool. No behavior change asserted.

### Acceptance

- `just check` green.
- No `dart:io.File` / `dart:io.Directory` imports remain in `packages/glue_harness/lib/src/agent/tools.dart`.
- All five file/list tools work identically to today when running on host.
- Docker run still passes existing integration tests (`just integration` if applicable, or manual smoke).

---

## PR 3 — Runtime `SessionEvent`s

**Goal:** Command and container lifecycle become typed `SessionEvent` variants in `glue_core`, emitted by executors, mapped to ACP in `glue_server`. Required for cloud observability and uniform replay.

### Changes

1. **New `SessionEvent` variants in `glue_core/session_event.dart`**
   - `RuntimeCommandStartedEvent` — `runtimeId`, `sessionId`, `commandId`, `command` (redacted/truncated), `mapping` (a `WorkspaceMapping` snapshot or just `hostCwd`/`runtimeCwd`), `startedAt`.
   - `RuntimeCommandOutputEvent` — `commandId`, `stream` (`stdout` | `stderr`), `bytes` or `text`, `at`. (Optional in V1; can be high-volume; gate behind a debug flag.)
   - `RuntimeCommandCompletedEvent` — `commandId`, `exitCode`, `durationMs`, `stdoutBytes`, `stderrBytes`.
   - `RuntimeCommandFailedEvent` — `commandId`, `errorType`, `errorMessage`.
   - `RuntimeCommandCancelledEvent` — `commandId`, `reason`.
   - `RuntimeContainerStartedEvent` / `RuntimeContainerStoppedEvent` — `runtimeId`, `sessionId`, `containerId`, `image` (where applicable).
   - All variants extend the existing `SessionEvent` sealed class. Follow the existing variant pattern (look at `McpServerConnectedEvent` et al. lines 23–27 of agent's report — they were added recently and are good precedents).

2. **Emit from executors**
   - `HostExecutor` and `DockerExecutor` accept an optional `SessionEventSink` (a callback `void Function(SessionEvent)` or a typed sink interface — match whatever pattern other producers use). Emit `RuntimeCommandStarted/Completed/Failed/Cancelled` around `runCapture` and `startStreaming`. `RuntimeContainerStarted/Stopped` for Docker only.
   - Wire the sink in `ServiceLocator` so events flow into the harness's existing event stream consumed by `AgentCore` / `App`.

3. **ACP mapping**
   - Edit `packages/glue_server/lib/src/acp/event_mapping.dart`: add cases for the new variants. Forward as ACP tool-output / status updates per the existing convention. The agent's report noted this mapper exists and was designed to handle the new events; we add the cases.

### Tests

- `packages/glue_core/test/session_event_test.dart` (extend): construct each new variant, round-trip via the existing equality/serialization tests.
- `packages/glue_strategies/test/shell/host_executor_test.dart` (extend): assert events are emitted in the right order around a `runCapture` call.
- `packages/glue_server/test/acp/event_mapping_test.dart` (extend): each new variant produces a non-null `SessionUpdate`.

### Acceptance

- `just check` green.
- Running a command in either runtime produces `RuntimeCommandStarted` → `RuntimeCommandCompleted` (or `Failed`/`Cancelled`) on the session event stream.
- ACP server forwards these to subscribed clients (verifiable by tapping `event_mapping.dart` output).

---

## PR 4 — Daytona adapter package

**Goal:** Ship a working Daytona runtime. Users can set `runtime: daytona` in config (or `GLUE_RUNTIME=daytona`) and Glue executes against a Daytona sandbox end-to-end: bash, file ops, grep, background jobs.

### Package layout

New package: `packages/glue_daytona/`.

```
packages/glue_daytona/
├── pubspec.yaml          # depends on: glue_core, glue_strategies, http
├── lib/
│   └── glue_daytona.dart # barrel
│   └── src/
│       ├── daytona_client.dart      # hand-written REST client over package:http
│       ├── daytona_config.dart      # api_key, base_url, image/snapshot, etc.
│       ├── daytona_executor.dart    # implements CommandExecutor + emits SessionEvents
│       ├── daytona_workspace.dart   # implements Workspace via REST fs.read/write/list
│       ├── daytona_bootstrap.dart   # git-clone-or-tarball workspace into /workspace
│       └── daytona_running_command.dart # implements RunningCommandHandle (streaming exec)
└── test/
    └── ...
```

`pubspec.yaml` declares dependencies only on `glue_core`, `glue_strategies`, and `http`. **No `glue_harness` dependency** — keeps the harness free of cloud SDKs, per the runtime-boundary plan §"Provider factories in separate packages".

### Implementation outline

1. **`DaytonaClient`** — thin wrapper over `package:http`:
   - `Future<DaytonaSandbox> createSandbox({String image, String? snapshot})` → `POST /api/sandbox`
   - `Future<DaytonaCaptureResult> execCapture(String sandboxId, String command, {Duration? timeout})` → `POST /api/sandbox/<id>/exec`
   - `Future<DaytonaStreamingExec> execStream(String sandboxId, String command)` → opens streaming exec channel (SSE or chunked HTTP per Daytona's actual contract — verify at implementation time against `app.daytona.io/api` docs)
   - `Future<List<int>> readFile(String sandboxId, String path)` → `GET /api/sandbox/<id>/fs/file?path=...`
   - `Future<void> writeFile(String sandboxId, String path, List<int> bytes)` → `PUT /api/sandbox/<id>/fs/file?path=...`
   - `Future<List<DaytonaFsEntry>> listDir(String sandboxId, String path)` → `GET /api/sandbox/<id>/fs/list?path=...`
   - `Future<void> stopSandbox(String sandboxId)`
   - All errors → typed `DaytonaApiException`.

2. **`DaytonaConfig`** — YAML/env-driven:
   - `apiKey` (from `DAYTONA_API_KEY` env or `runtime.daytona.api_key` config key resolving `env:...`)
   - `baseUrl` (default `https://app.daytona.io/api`)
   - `image` or `snapshot`
   - Mirrors the `DockerConfig` shape — see `packages/glue_strategies/lib/src/shell/docker_config.dart` for the pattern, and `glue_config.dart` lines 348–369 for how env vars get parsed.

3. **`DaytonaBootstrap`** — Option D from the cloud runtimes plan:
   - On session start, prepare the workspace inside the sandbox at `/workspace`:
     - If host cwd is a git repo: `git rev-parse HEAD`, push uncommitted state to a scratch ref on origin (or fall back to tarball), `daytonaClient.execCapture("git clone <ref> /workspace")` inside the sandbox.
     - If host cwd is not a git repo: tarball with `.gitignore` respect, `writeFile` it, extract.
   - Record the bootstrap SHA so end-of-session can produce a diff (deferred to a polish PR; not strictly required for V1).

4. **`DaytonaRunningCommand`** — `RunningCommandHandle` impl backed by a streaming HTTP exec. `stdout` / `stderr` are broadcast `Stream<List<int>>`s pumped from the chunked response; `exitCode` resolves when the stream closes; `kill()` calls a `POST /exec/<id>/cancel` endpoint (or whatever Daytona exposes).

5. **`DaytonaExecutor`** — implements `CommandExecutor`. `runCapture` calls `client.execCapture`; `startStreaming` returns a `DaytonaRunningCommand`. Emits `RuntimeCommand*Event`s via the sink.

6. **`DaytonaWorkspace`** — implements `Workspace`. Each method translates to the corresponding `DaytonaClient` call. `mapping` is fixed at `hostCwd = resolvedEnv.cwd`, `runtimeCwd = '/workspace'`.

### Config + wiring

1. **New `runtime:` config section** — in `packages/glue_harness/lib/src/config/glue_config.dart`:
   - Top-level key: `runtime: host | docker | daytona` (default: keep existing host/docker semantics: if unset and `docker.enabled = true`, runtime = docker; else host. This preserves backwards compat.)
   - Env override: `GLUE_RUNTIME=daytona`.
   - New `runtime:` subsection (sibling of `docker:`) holds adapter-specific config:
     ```yaml
     runtime: daytona
     daytona:
       api_key: env:DAYTONA_API_KEY
       image: ubuntu:24.04
       base_url: https://app.daytona.io/api
     ```

2. **`RuntimeFactory` (or extend `ExecutorFactory`)** — `packages/glue_strategies/lib/src/runtime/runtime_factory.dart` (new):
   - Static `create({GlueConfig config, String cwd, ...}) → Future<(CommandExecutor, Workspace)>`.
   - Dispatches on `config.runtime`:
     - `host` → `(HostExecutor(shellConfig), LocalWorkspace(mapping with runtimeCwd=hostCwd))`
     - `docker` → `(DockerExecutor(...), LocalWorkspace(mapping with runtimeCwd='/workspace'))`
     - `daytona` → bootstrap sandbox, then `(DaytonaExecutor(client, sandboxId), DaytonaWorkspace(client, sandboxId))`. The daytona case is only reachable when `glue_daytona` is depended on by the surface (cli) — `glue_strategies` itself does **not** depend on `glue_daytona`. Wire via a registration pattern: `RuntimeFactory.register('daytona', (config, cwd) => DaytonaRuntime.start(...))` called from `cli/bin/glue.dart` before `ServiceLocator.create()`.

3. **`ServiceLocator` updates** — `packages/glue_harness/lib/src/core/service_locator.dart`:
   - Replace `ExecutorFactory.create(...)` call (line 105) with `RuntimeFactory.create(...)`.
   - Pass returned `Workspace` into file tools (already done in PR 2; this just wires the cloud variant).
   - On shutdown, call `runtime.close()` (or the equivalent) so Daytona sandboxes get stopped — important so the user isn't billed indefinitely.

### Tests

- `packages/glue_daytona/test/daytona_client_test.dart` — unit tests with a `MockClient` from `package:http`: assert correct URL/method/headers/payload for each endpoint.
- `packages/glue_daytona/test/daytona_executor_test.dart` — exercise `CommandExecutor` contract against the mock client; verify `SessionEvent` emission.
- `packages/glue_daytona/test/daytona_workspace_test.dart` — exercise `Workspace` contract against the mock client; path translation.
- `packages/glue_daytona/test/daytona_bootstrap_test.dart` — bootstrap creates the expected sequence of API calls for a git repo vs tarball fallback. Use a temp git repo fixture.
- **Live integration test (opt-in, tagged):** `packages/glue_daytona/test/integration/daytona_live_test.dart` with `@Tags(['cloud-daytona'])`. Requires `DAYTONA_API_KEY`. Skipped by default like `just e2e` / `just integration`. Add `just daytona` (or extend `just integration`) to run it.

### Acceptance

- `just check` green.
- With `GLUE_RUNTIME=daytona` and `DAYTONA_API_KEY` set, the smoke flow works end-to-end:
  - `glue --print "list files in /workspace"` → agent calls `list_directory` → DaytonaWorkspace → succeeds with real directory listing.
  - `glue --print "run 'echo hello' and tell me what it printed"` → agent calls `bash` → DaytonaExecutor → succeeds.
  - `glue --print "read /workspace/README.md and summarize"` → file tool routes through DaytonaWorkspace.
- Daytona sandbox is stopped on session close (verifiable in Daytona dashboard).
- Sandbox cleanup also runs on `SIGINT` / fatal error.

---

## PR 5 — Polish: doctor, `/runtime` slash command, end-of-session diff

**Goal:** A discoverable, debuggable cloud runtime experience.

### Changes

1. **`glue doctor` adds a Daytona section**
   - `packages/glue_harness/lib/src/doctor/` (or wherever doctor checks live — `cli/lib/src/doctor/` if surface-side): probe `DAYTONA_API_KEY` presence, `GET /api/health` (or equivalent), report sandbox count / quota if the API exposes it.

2. **`/runtime` slash command**
   - Edit `packages/glue_harness/lib/src/commands/` or `cli/lib/src/commands/slash/` (whichever holds existing class-based slash commands per commit `d2cba58`):
     - `/runtime` (no arg) — show current runtime, sandbox id if any, capabilities snapshot.
     - `/runtime switch <name>` — defer to a polish follow-up; out of scope for V1.
   - Follows the registry pattern used by `/model`, `/provider`, etc.

3. **End-of-session diff-out (Daytona only)**
   - On graceful close, run `git -C /workspace diff <bootstrap-sha>` inside the sandbox, fetch the patch via `DaytonaWorkspace.readFileAsString('/tmp/session.patch')`, surface as a final assistant message or save next to the session log. Per cloud runtimes plan §"End-of-session diff-out (universal)".

4. **Cost guard for integration tests**
   - Live tests pin sandboxes to the smallest tier and the shortest TTL Daytona supports.
   - `tearDown` always calls `stopSandbox` even on failure. Verify no leaked sandboxes after the test suite.

### Tests

- `doctor_test.dart` extended with Daytona check coverage.
- `/runtime` slash command unit test.
- Manual: run `just daytona` (or whatever the integration alias is), verify zero leaked sandboxes in the Daytona dashboard.

### Acceptance

- `glue doctor` reports clearly when Daytona is configured / misconfigured.
- `/runtime` answers what's running where.
- Live integration suite leaves no orphaned sandboxes.

---

## Critical files (cross-PR reference)

| File | PRs |
|---|---|
| `packages/glue_core/lib/src/running_command_handle.dart` (new) | 1 |
| `packages/glue_core/lib/src/workspace_mapping.dart` (new) | 2 |
| `packages/glue_core/lib/src/session_event.dart` | 3 |
| `packages/glue_core/lib/glue_core.dart` (barrel) | 1, 2, 3 |
| `packages/glue_strategies/lib/src/shell/command_executor.dart` | 1, 3 |
| `packages/glue_strategies/lib/src/shell/host_executor.dart` | 3 |
| `packages/glue_strategies/lib/src/shell/docker_executor.dart` | 1, 3 |
| `packages/glue_strategies/lib/src/fs/workspace.dart` (new) | 2 |
| `packages/glue_strategies/lib/src/fs/local_workspace.dart` (new) | 2 |
| `packages/glue_strategies/lib/src/runtime/runtime_factory.dart` (new) | 4 |
| `packages/glue_strategies/lib/glue_strategies.dart` (barrel) | 1, 2, 4 |
| `packages/glue_harness/lib/src/agent/shell_job_manager.dart` | 1 |
| `packages/glue_harness/lib/src/agent/tools.dart` | 1, 2 |
| `packages/glue_harness/lib/src/core/service_locator.dart` | 2, 4 |
| `packages/glue_harness/lib/src/config/glue_config.dart` | 4 |
| `packages/glue_harness/lib/src/agent/prompts.dart` | 2 (system prompt cwd hint) |
| `packages/glue_server/lib/src/acp/event_mapping.dart` | 3 |
| `packages/glue_daytona/**` (new package) | 4 |
| `cli/bin/glue.dart` (Daytona adapter registration) | 4 |
| `cli/lib/src/commands/slash/...` (`/runtime`) | 5 |

---

## Existing utilities to reuse

- **`MountEntry` + `MountEntry.dedup`** (`packages/glue_strategies/lib/src/shell/docker_config.dart`) — already handles mount-spec parsing. `WorkspaceMapping.additionalMounts` should be a `List<MountEntry>`.
- **`ExecutorFactory.create` argument shape** — model `RuntimeFactory.create`'s signature on it (named args: `shellConfig`, `dockerConfig`, `cwd`, `sessionMounts`).
- **`ForwardingTool`** (`packages/glue_core/lib/src/tool.dart`) — decorator base. Not needed for the basic file-tool refactor (direct DI is simpler), but available if we need to layer concerns later (e.g., Ask Mode write-blocker).
- **`ToolTrust` enum** — file tools stay `ToolTrust.fileEdit`, bash stays `ToolTrust.command`. No permission model changes needed (confirmed by audit: trust enforcement is at `cli/lib/src/app.dart` and is orthogonal to which `Workspace`/`CommandExecutor` is plugged in).
- **`PermissionGate`** (`packages/glue_harness/lib/src/orchestrator/permission_gate.dart`) — unchanged.
- **`AppServices`** struct (`packages/glue_harness/lib/src/core/service_locator.dart`) — add `workspace` field in PR 2; surfaces can read it for path hints.
- **Existing `McpServerConnectedEvent` et al. in `session_event.dart`** — precedent for adding new variants in PR 3.
- **Existing `bash_tool_test.dart` and `edit_file_tool_test.dart` (`cli/test/tools/`)** — testing style to copy: real executor / temp directory fixtures, no heavyweight mocking.

---

## Verification (end-to-end)

### After each PR

```sh
just check                    # gen-check + analyze + test, repo-wide
just cli::test                # cli-only test suite
```

PR 1 specifically:
```sh
dart test packages/glue_harness/test/agent/shell_job_manager_test.dart
dart test packages/glue_strategies/test/shell/
```

PR 2 specifically:
```sh
dart test packages/glue_strategies/test/fs/
dart test packages/glue_harness/test/agent/  # file tool tests still pass
# Manual smoke: glue --print "read pubspec.yaml and tell me the version"
# Manual smoke with docker: GLUE_DOCKER_ENABLED=1 glue --print "list files in /workspace"
```

PR 3 specifically:
```sh
dart test packages/glue_core/test/session_event_test.dart
dart test packages/glue_server/test/acp/event_mapping_test.dart
# Manual: tail ~/.glue/logs/<latest>.jsonl while running a command, observe runtime events
```

PR 4 specifically:
```sh
# Unit suite (no network):
dart test packages/glue_daytona/

# Live integration (requires DAYTONA_API_KEY env var):
just daytona      # new alias, or: dart test --run-skipped -t cloud-daytona packages/glue_daytona/

# Manual end-to-end smoke (the canonical "it works" demo):
export DAYTONA_API_KEY=...
export GLUE_RUNTIME=daytona
glue --print "list files in /workspace, read pubspec.yaml, then echo 'hello from daytona' and tell me the exit code"
# Verify in Daytona dashboard: sandbox was created and stopped.
```

PR 5 specifically:
```sh
glue doctor               # Daytona section visible & accurate
glue                      # then type /runtime — shows daytona + sandbox id
# Live: run a session that modifies files, gracefully /exit, verify session.patch is captured.
```

### Final acceptance — full feature

With `GLUE_RUNTIME=daytona` and `DAYTONA_API_KEY` set:

1. Start `glue` (interactive).
2. Ask the agent to: list files, read one file, edit it (add a comment), run `cat <file>` via bash, start a background watcher (`/jobs` panel shows it running in the cloud), kill the job, exit.
3. Verify:
   - All tool calls succeed.
   - `/runtime` shows the sandbox id.
   - On exit, `session.patch` captures the agent's edits.
   - The sandbox is stopped (no leaks in dashboard).
   - `~/.glue/logs/<session>.jsonl` contains `RuntimeCommandStarted`/`Completed` events with `runtimeId=daytona`.

---

## Out of scope (explicit deferrals)

- **Website + docs updates** (per user request). Tracked as a follow-up. Includes:
  - `docs/reference/runtime-capabilities.yaml` — splitting `cloud:` row into `daytona:` row, adjusting capability cells.
  - `website/docs/advanced/runtimes.md` — replace "planned" line; fix stale `cli/lib/src/shell/` path reference.
  - `CLAUDE.md` — stale architecture description still references pre-monorepo `cli/lib/src/` layout.
  - `RuntimeMatrix.vue` if it needs structural changes for the new row.
- **`BrowserEndpointSource` union + `WebBrowserTool` rewiring** — deferred per user. `BrowserManager` continues to use its own providers (Steel, Browserbase, etc.) regardless of runtime.
- **`ExecutionRuntime` / `RuntimeSession` umbrella interface** — the cloud runtimes plan and runtime-boundary plan both sketched a `RuntimeSession` that bundles executor + workspace + browser + artifacts + `getHost(port)`. With only one cloud adapter, this would be premature abstraction. Defer until a second cloud adapter (E2B or Sprites) forces the extraction. `RuntimeFactory.create` returns a tuple `(CommandExecutor, Workspace)` for now.
- **Additional cloud adapters** (E2B, Sprites, hopx, Northflank, Modal) — these become straightforward once the Workspace + Runtime contracts have proven through Daytona.
- **End-of-session diff *application* to the host workspace** — PR 5 surfaces the diff but does not auto-apply it. Reviewing and applying remains a manual step.
- **`getHost(port)` for dev-server preview URLs** — defer to when the agent actually needs to spawn dev servers in the sandbox.
- **Credentials integration with `CredentialStore`** — V1 uses env-var-only (`DAYTONA_API_KEY`). Follow-up to integrate with the existing credential store (per cloud runtimes plan).
- **Ask Mode (read-only flag)** — separate small spike, can land any time after PR 2. Independent.
