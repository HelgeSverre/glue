# Glue A2A Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Glue expose itself as an A2A v1.0 agent and consume configured remote A2A agents as namespaced capabilities.

**Architecture:** Depend on `packages/dart-a2a` for protocol and transports. Keep reusable A2A-to-Glue mapping in `packages/glue_server`, remote-agent client/tool logic in `packages/glue_strategies`, config/session orchestration in `packages/glue_harness`, and user-facing commands in `cli`.

**Tech Stack:** Dart 3.12 workspace, `dart_a2a`, Glue four-layer architecture, `AgentCore`, `PermissionGate`, `ServiceLocator`, Glue config/credentials/session storage.

---

## Status

Plan only. This depends on `docs/plans/2026-05-22-dart-a2a-package-plan.md` landing first through at least the JSON-RPC and REST bundles.

Implementation is phased:

1. Expose Glue as an A2A server.
2. Consume remote A2A agents as Glue tools.
3. Add polish, docs, and compliance coverage across both directions.

## Current Glue Shape

Glue already has the right separation pattern in its ACP implementation:

- `packages/glue_server` owns protocol dispatch and has no `glue_harness` dependency.
- `cli/lib/src/acp/cli_acp_delegate.dart` wires protocol events to `AgentCore`, tools, and permission gates.
- `cli/bin/glue.dart` hosts the user-facing command and loopback/non-loopback safety checks.
- `GlueConfig` already has a typed `mcp` section; A2A should follow that parser/config-template pattern instead of inventing a new config path.

## Configuration

Add this top-level config section:

```yaml
a2a:
  expose:
    enabled: false
    host: 127.0.0.1
    port: 4099
    base_url: null
    bindings: [http_json, json_rpc]
    token: ${GLUE_A2A_TOKEN}
    permission_mode: input_required # input_required | deny | auto
    push_notifications:
      enabled: false
      allow_private_urls: false

  agents:
    reviewer:
      card_url: https://agent.example/.well-known/agent-card.json
      preferred_binding: auto # auto | http_json | json_rpc | grpc
      enabled: true
      timeout_seconds: 120
      auth:
        kind: bearer
        token: ${REVIEWER_A2A_TOKEN}
      allowed_skills: []
```

Rules:

- `a2a.expose.enabled` controls startup from config only. `glue a2a serve` can still be run explicitly.
- Non-loopback binds require `token`, matching the existing ACP safety posture.
- `base_url` is required for a production Agent Card that advertises non-loopback HTTP interfaces; if absent, `glue a2a serve` derives loopback URLs.
- `permission_mode: input_required` is the default and maps mutating tool permission requests to A2A `TASK_STATE_INPUT_REQUIRED`.
- Remote agent IDs use the same grammar as MCP server IDs: lowercase alphanumeric plus `_`/`-`, starting with an alphanumeric character.
- `allowed_skills: []` means all advertised skills are exposed. A non-empty list allowlists skill ids from the Agent Card.

## New Types

Create config and runtime structs:

- `A2aConfig`
- `A2aExposeConfig`
- `A2aExposeBinding`
- `A2aPushConfig`
- `A2aRemoteAgentSpec`
- `A2aRemoteAgentAuth`
- `A2aPreferredBinding`
- `A2aAgentSnapshot`
- `A2aPoolEvent`
- `A2aTaskRecord`
- `A2aContextRecord`
- `A2aPermissionChallenge`

Credential namespace:

- Bearer/API-key fields live under `a2a:<agent-id>`.
- Exposed-server bearer token can be read from config/env and is not persisted automatically.

## Bundle 1 - Config Parser And Docs

**Files:**

- Create: `packages/glue_harness/lib/src/config/a2a_config.dart`
- Modify: `packages/glue_harness/lib/src/config/glue_config.dart`
- Modify: `packages/glue_harness/lib/src/config/config_template.dart`
- Modify: `packages/glue_harness/lib/glue_harness.dart`
- Modify: `docs/reference/config-yaml.md`
- Test: `packages/glue_harness/test/config/a2a_config_test.dart`

- [ ] Add typed config structs and parser.
- [ ] Parse `a2a.expose`, `a2a.expose.push_notifications`, and `a2a.agents`.
- [ ] Expand `${VAR}` in remote `card_url`, auth tokens, and exposed `token` with the same loud missing-env behavior as MCP.
- [ ] Validate server IDs, URLs, bindings, ports, timeouts, and permission modes.
- [ ] Add commented examples to the config template and reference docs.
- [ ] Run:

```bash
dart test packages/glue_harness/test/config/a2a_config_test.dart
```

Expected: defaults, full config, disabled agents, missing env vars, malformed URLs, invalid IDs, and invalid bindings are all covered.

## Bundle 2 - Glue Server Mapping Layer

**Files:**

- Create: `packages/glue_server/lib/src/a2a/glue_a2a_mapper.dart`
- Create: `packages/glue_server/lib/src/a2a/glue_a2a_service_base.dart`
- Create: `packages/glue_server/lib/src/a2a/glue_agent_card.dart`
- Modify: `packages/glue_server/lib/glue_server.dart`
- Modify: `packages/glue_server/pubspec.yaml`
- Test: `packages/glue_server/test/a2a/glue_a2a_mapper_test.dart`
- Test: `packages/glue_server/test/a2a/glue_agent_card_test.dart`

- [ ] Add a dependency on `dart_a2a`.
- [ ] Map Glue `ContentPart` values to A2A `Part`: text to `text`, images to `raw` plus `mediaType`, resource links to `url`.
- [ ] Map `AgentEvent` values to A2A stream responses:
  - `AgentTextDelta` becomes an agent `Message` event with text part chunks.
  - `AgentToolCallPending` and `AgentToolCall` become `TaskStatusUpdateEvent` with `TASK_STATE_WORKING` and metadata describing the tool.
  - `AgentToolResult` becomes `TaskArtifactUpdateEvent` with text/resource/diff output.
  - `AgentDone` completes the task.
  - `AgentError` fails the task.
  - `AgentNotice` becomes an agent `Message` with metadata `glue.notice.kind`.
- [ ] Build public Agent Cards for Glue with `streaming: true`, `pushNotifications` from config, and supported interfaces from selected bindings.
- [ ] Add a Glue permission extension URI: `https://getglue.dev/a2a/extensions/permission/v1`.
- [ ] Run:

```bash
dart test packages/glue_server/test/a2a
```

Expected: mapper tests cover text, images, resources, tool lifecycle, failures, notices, and Agent Card interface generation.

## Bundle 3 - CLI A2A Service

**Files:**

- Create: `cli/lib/src/a2a/cli_a2a_service.dart`
- Create: `cli/lib/src/a2a/a2a_task_store.dart`
- Create: `cli/lib/src/a2a/a2a_permission_bridge.dart`
- Test: `cli/test/a2a/cli_a2a_service_test.dart`
- Test: `cli/test/a2a/a2a_permission_bridge_test.dart`

- [ ] Implement `CliA2aService` backed by `ServiceLocator`, `AgentCore`, Glue tools, and `PermissionGate`.
- [ ] Reuse the same native tool set as ACP initially: `read_file`, `write_file`, `edit_file`, `bash`, `grep`, and `list_directory`.
- [ ] Store A2A task records under `${GLUE_HOME}/a2a/tasks/<task-id>.json`.
- [ ] Use `contextId` to group turns. If the client provides only `taskId`, infer `contextId` from the task store.
- [ ] Implement `SendMessage` with `returnImmediately` support:
  - `false`: wait until terminal or interrupted state.
  - `true`: return submitted/working task and continue streaming state into the task store.
- [ ] Implement `SendStreamingMessage` by yielding submitted, working, message/artifact, and terminal updates.
- [ ] Implement `GetTask`, `ListTasks`, `CancelTask`, and `SubscribeToTask`.
- [ ] Implement push config CRUD in the task store but do not deliver outbound webhooks until Bundle 6.
- [ ] Map permission decisions:
  - `auto`: use Glue config/trusted tools and execute when allowed.
  - `deny`: deny mutating tool calls and mark task failed with a clear status message.
  - `input_required`: pause the task with `TASK_STATE_INPUT_REQUIRED` and a Glue permission extension payload.
- [ ] Run:

```bash
dart test cli/test/a2a/cli_a2a_service_test.dart
dart test cli/test/a2a/a2a_permission_bridge_test.dart
```

Expected: task lifecycle, history limits, cancellation, permission interruption, and resume-after-approval are covered with fake LLM/tools.

## Bundle 4 - `glue a2a serve`

**Files:**

- Create: `cli/lib/src/commands/a2a_command.dart`
- Create: `cli/lib/src/commands/a2a_serve_format.dart`
- Modify: `cli/bin/glue.dart`
- Test: `cli/test/commands/a2a_command_test.dart`
- Test: `cli/test/bin/glue_a2a_test.dart`

- [ ] Add top-level command `glue a2a`.
- [ ] Add subcommand `glue a2a serve`.
- [ ] Options:

```text
--host <host>                 default from config or 127.0.0.1
--port <port>                 default from config or 4099, 0 allowed
--base-url <url>              public URL advertised in Agent Card
--binding <binding>           repeatable: http-json, json-rpc, grpc
--token <token>               bearer token for inbound requests
--permission-mode <mode>      input-required, deny, auto
--debug                       enable observability sinks
```

- [ ] Bind loopback by default.
- [ ] Refuse non-loopback without token.
- [ ] Mount Agent Card discovery, selected A2A bindings, and extended card route.
- [ ] Print the startup banner to stderr so protocol responses stay clean.
- [ ] Run:

```bash
dart test cli/test/commands/a2a_command_test.dart
dart test cli/test/bin/glue_a2a_test.dart
```

Expected: command parsing, non-loopback safety, banner output, and a full local HTTP send/get flow are covered.

## Bundle 5 - Remote A2A Agent Pool

**Files:**

- Create: `packages/glue_strategies/lib/src/a2a_client/config.dart`
- Create: `packages/glue_strategies/lib/src/a2a_client/pool.dart`
- Create: `packages/glue_strategies/lib/src/a2a_client/tool_factory.dart`
- Create: `packages/glue_strategies/lib/src/a2a_client/connection_state.dart`
- Modify: `packages/glue_strategies/lib/glue_strategies.dart`
- Modify: `packages/glue_strategies/pubspec.yaml`
- Test: `packages/glue_strategies/test/a2a_client/pool_test.dart`
- Test: `packages/glue_strategies/test/a2a_client/tool_factory_test.dart`

- [ ] Add dependency on `dart_a2a`.
- [ ] Fetch each enabled remote Agent Card on startup.
- [ ] Select a binding from `supportedInterfaces` by `preferred_binding`, version support, and client capability.
- [ ] Build one Glue `Tool` per exposed skill with name `<agentId>__<skillId>`.
- [ ] Tool input schema accepts:

```json
{
  "type": "object",
  "properties": {
    "message": {"type": "string"},
    "context_id": {"type": "string"},
    "task_id": {"type": "string"},
    "attachments": {
      "type": "array",
      "items": {"type": "object"}
    }
  },
  "required": ["message"]
}
```

- [ ] On execution, call `SendStreamingMessage` when supported, otherwise `SendMessage` plus polling `GetTask` until terminal or interrupted.
- [ ] Convert returned A2A messages/artifacts to `ToolResult.contentParts`.
- [ ] Treat `TASK_STATE_INPUT_REQUIRED` and `TASK_STATE_AUTH_REQUIRED` as failed tool results with clear remediation text in v1.
- [ ] Run:

```bash
dart test packages/glue_strategies/test/a2a_client
```

Expected: pool discovery, tool naming, binding selection, disabled agents, auth headers, streaming output, polling fallback, and namespace conflicts are covered.

## Bundle 6 - Harness Wiring And Push Delivery

**Files:**

- Modify: `packages/glue_harness/lib/src/core/service_locator.dart`
- Modify: `packages/glue_harness/lib/glue_harness.dart`
- Create: `packages/glue_harness/lib/src/a2a/a2a_push_delivery.dart`
- Test: `packages/glue_harness/test/a2a/service_locator_a2a_test.dart`
- Test: `packages/glue_harness/test/a2a/a2a_push_delivery_test.dart`

- [ ] Construct `A2aAgentPool` from `config.a2a.agents`.
- [ ] Register remote A2A tools in the normal tool map, with the same permission and observability behavior as other `Tool` instances.
- [ ] Expose pool state through `AppServices`.
- [ ] Implement push delivery for exposed Glue server tasks only when `a2a.expose.push_notifications.enabled` is true.
- [ ] Block localhost, link-local, private-network, and file URLs unless `allow_private_urls` is true.
- [ ] Include configured auth data when delivering push callbacks.
- [ ] Run:

```bash
dart test packages/glue_harness/test/a2a
```

Expected: remote A2A tools appear in service locator, push delivery is off by default, and SSRF protections are enforced.

## Bundle 7 - CLI And Slash Management Surfaces

**Files:**

- Modify: `cli/lib/src/commands/a2a_command.dart`
- Create: `cli/lib/src/commands/a2a_list_format.dart`
- Create: `cli/lib/src/commands/slash/a2a.dart`
- Modify: `cli/lib/src/commands/builtin_commands.dart`
- Modify: `cli/lib/src/commands/slash_command_context.dart`
- Test: `cli/test/commands/a2a_command_test.dart`
- Test: `cli/test/commands/slash/a2a_test.dart`

- [ ] Add CLI subcommands:

```text
glue a2a list
glue a2a inspect <agent>
glue a2a test <agent>
glue a2a auth set <agent> --bearer
glue a2a auth logout <agent>
glue a2a serve
```

- [ ] Add `/a2a` slash command with status panel, inspect, reconnect, toggle, tools, auth status, and last error actions.
- [ ] Keep command output style aligned with existing MCP command surfaces.
- [ ] Run:

```bash
dart test cli/test/commands/a2a_command_test.dart
dart test cli/test/commands/slash/a2a_test.dart
```

Expected: CLI and slash surfaces can inspect fake configured agents and handle empty config cleanly.

## Bundle 8 - Docs, Website, And Compliance

**Files:**

- Create: `website/docs/advanced/a2a.md`
- Modify: `website/.vitepress/config.ts`
- Modify: `docs/reference/glue-home-layout.md`
- Modify: `docs/reference/config-yaml.md`
- Modify: `website/data/feature-status.yaml`
- Test: `cli/tool/check_site_consistency.dart`

- [ ] Document the difference between ACP, MCP, and A2A:
  - ACP: editor/client drives Glue.
  - MCP: Glue consumes tools/resources.
  - A2A: task-oriented agent-to-agent interoperability, both expose and consume.
- [ ] Document `glue a2a serve`, security defaults, Agent Card URL, REST endpoints, and remote-agent config.
- [ ] Document `${GLUE_HOME}/a2a/tasks/`.
- [ ] Add a compliance matrix for Glue exposure and remote consumption.
- [ ] Run:

```bash
cd cli
dart run tool/check_site_consistency.dart
cd ..
just check
```

Expected: full repo checks pass.

## Test Plan

- Config parser tests for defaults, full configs, invalid values, and env interpolation.
- Glue server mapper tests for every `AgentEvent` currently emitted by `AgentCore`.
- CLI A2A service tests for send, stream, get/list/cancel/subscribe, task history, task artifacts, and permission interruption.
- Command tests for `glue a2a serve`, `list`, `inspect`, `test`, and auth commands.
- Remote pool tests for Agent Card fetch, binding selection, skill exposure, reconnect, disabled agents, and auth failure.
- Integration test starting `glue a2a serve` locally, fetching `/.well-known/agent-card.json`, sending a task, streaming updates, getting the task, listing tasks, and canceling a working task.
- Security tests for non-loopback bind refusal without token, token redaction, private push URL blocking, and remote agent token storage.

## Assumptions

- `packages/dart-a2a` owns protocol compliance. Glue code should not duplicate protocol parsing or transport semantics.
- Glue exposes HTTP+JSON and JSON-RPC first. gRPC exposure can land after the package gRPC binding exists and is tested.
- Remote A2A agents are coarse task delegates, not a replacement for MCP tools.
- In-task auth from remote agents is represented as a clear failed tool result in v1; interactive OAuth/device-code bridging can be added after the basic remote-agent loop is stable.
- Existing ACP behavior remains unchanged.
