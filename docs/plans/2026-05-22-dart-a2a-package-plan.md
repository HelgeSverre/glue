# Dart A2A Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Glue-local, fully featured Dart implementation of A2A v1.0 under `packages/dart-a2a`.

**Architecture:** Keep A2A protocol types, clients, servers, transports, auth hooks, and compliance tests in `packages/dart-a2a`, with no dependency on Glue packages. Generate the canonical proto/grpc types from the upstream `a2a.proto`, then layer idiomatic Dart builders, service interfaces, task storage, and binding adapters over the generated model.

**Tech Stack:** Dart 3.12 workspace, A2A v1.0 proto, `protobuf`, `grpc`, `http`, `shelf`, `shelf_router`, `protoc_plugin`, `test`, Effective Dart naming/API guidance.

---

## Status

Plan only. No package files have been created yet.

The package is Glue-local for now, per product choice, so `pubspec.yaml` uses `publish_to: none`. The public API should still be clean enough that publishing later is a metadata and docs decision rather than a rewrite. Use pub package name `dart_a2a` because `a2a` is already occupied on pub.dev and that package currently documents JSON-RPC-only/no-auth limitations.

## Source Notes

- A2A v1.0 is the target. The stable spec is proto-canonical and supports JSON-RPC, gRPC, and HTTP+JSON/REST bindings.
- Core operations are `SendMessage`, `SendStreamingMessage`, `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, push-notification config CRUD, and `GetExtendedAgentCard`.
- REST endpoints include `POST /message:send`, `POST /message:stream`, `GET /tasks/{id}`, `GET /tasks`, `POST /tasks/{id}:cancel`, `GET /tasks/{id}:subscribe`, push-notification config routes, and `GET /extendedAgentCard`.
- Agent Card discovery uses `GET /.well-known/agent-card.json`; Agent Cards declare `supportedInterfaces`, security schemes/requirements, default input/output modes, skills, signatures, and optional extended-card support.
- JSON-RPC method names are PascalCase, for example `SendMessage`, not the older slash-style names.

Primary references:

- https://a2a-protocol.org/latest/specification/
- https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto
- https://a2a-protocol.org/latest/announcing-1.0/
- https://dart.dev/effective-dart
- https://pub.dev/packages/protobuf
- https://pub.dev/packages/grpc
- https://pub.dev/packages/shelf
- https://pub.dev/packages/shelf_router
- https://pub.dev/packages/protoc_plugin

## Package Shape

Create:

```text
packages/dart-a2a/
  pubspec.yaml
  analysis_options.yaml
  lib/dart_a2a.dart
  lib/src/generated/
  lib/src/core/
  lib/src/json_rpc/
  lib/src/rest/
  lib/src/grpc/
  lib/src/client/
  lib/src/server/
  lib/src/security/
  lib/src/testing/
  tool/sync_a2a_proto.dart
  tool/check_generated.dart
  protos/a2a.proto
  protos/google/api/*.proto
  test/
```

Root workspace change:

```yaml
workspace:
  - cli
  - packages/dart-a2a
  - packages/glue_core
  - packages/glue_strategies
  - packages/glue_runtimes
  - packages/glue_harness
  - packages/glue_server
```

Package dependencies:

```yaml
dependencies:
  collection: ^1.19.0
  grpc: ^5.1.0
  http: ^1.6.0
  meta: ^1.15.0
  protobuf: ^6.0.0
  shelf: ^1.4.2
  shelf_router: ^1.1.4

dev_dependencies:
  lints: ^6.1.0
  protoc_plugin: ^25.0.0
  test: ^1.30.0
```

## Public API

`lib/dart_a2a.dart` exports only stable user-facing APIs:

- Generated protocol objects from `src/generated/a2a.pb.dart` and `src/generated/a2a.pbgrpc.dart`.
- `A2aClient` with constructors `jsonRpc`, `rest`, and `grpc`.
- `A2aService`, the transport-neutral server contract.
- `A2aServer`, route mounting, and binding helpers.
- `TaskStore`, `MemoryTaskStore`, `TaskSubscriptionHub`, and `PushNotificationStore`.
- `A2aRequestContext`, `A2aPrincipal`, `A2aAuthProvider`, and `A2aVersionPolicy`.
- `A2aError` and typed subclasses for spec errors.
- Builders/factories that make generated types ergonomic without hiding the canonical model.

API skeleton:

```dart
abstract interface class A2aService {
  Future<SendMessageResponse> sendMessage(
    SendMessageRequest request,
    A2aRequestContext context,
  );

  Stream<StreamResponse> sendStreamingMessage(
    SendMessageRequest request,
    A2aRequestContext context,
  );

  Future<Task> getTask(GetTaskRequest request, A2aRequestContext context);
  Future<ListTasksResponse> listTasks(
    ListTasksRequest request,
    A2aRequestContext context,
  );
  Future<Task> cancelTask(CancelTaskRequest request, A2aRequestContext context);

  Stream<StreamResponse> subscribeToTask(
    SubscribeToTaskRequest request,
    A2aRequestContext context,
  );

  Future<TaskPushNotificationConfig> createTaskPushNotificationConfig(
    TaskPushNotificationConfig request,
    A2aRequestContext context,
  );
  Future<TaskPushNotificationConfig> getTaskPushNotificationConfig(
    GetTaskPushNotificationConfigRequest request,
    A2aRequestContext context,
  );
  Future<ListTaskPushNotificationConfigsResponse>
  listTaskPushNotificationConfigs(
    ListTaskPushNotificationConfigsRequest request,
    A2aRequestContext context,
  );
  Future<void> deleteTaskPushNotificationConfig(
    DeleteTaskPushNotificationConfigRequest request,
    A2aRequestContext context,
  );

  Future<AgentCard> getPublicAgentCard(A2aRequestContext context);
  Future<AgentCard> getExtendedAgentCard(
    GetExtendedAgentCardRequest request,
    A2aRequestContext context,
  );
}
```

Client skeleton:

```dart
final client = A2aClient.rest(
  baseUrl: Uri.parse('https://agent.example.com/a2a/v1'),
  auth: A2aBearerToken('token'),
);

final response = await client.sendMessage(
  MessageBuilder.userText('Explain this repository').build(),
);

await for (final event in client.sendStreamingMessage(
  MessageBuilder.userText('Run the long task').build(),
)) {
  switch (event.whichPayload()) {
    case StreamResponse_Payload.statusUpdate:
      // Render task status.
    case StreamResponse_Payload.artifactUpdate:
      // Render artifact.
    case StreamResponse_Payload.message:
    case StreamResponse_Payload.task:
    case StreamResponse_Payload.notSet:
  }
}
```

## Implementation Bundles

### Bundle 1 - Package Scaffold And Proto Pin

**Files:**

- Create: `packages/dart-a2a/pubspec.yaml`
- Create: `packages/dart-a2a/analysis_options.yaml`
- Create: `packages/dart-a2a/lib/dart_a2a.dart`
- Create: `packages/dart-a2a/protos/a2a.proto`
- Create: `packages/dart-a2a/tool/sync_a2a_proto.dart`
- Create: `packages/dart-a2a/tool/check_generated.dart`
- Modify: `pubspec.yaml`

- [ ] Add the package scaffold and workspace entry.
- [ ] Vendor the upstream `a2a.proto` at a pinned commit recorded in `protos/UPSTREAM.md`.
- [ ] Vendor only the Google annotation protos needed for Dart generation.
- [ ] Add a generated-code check script that exits non-zero when `protos/a2a.proto` or generated outputs are stale.
- [ ] Run:

```bash
dart pub get
dart analyze packages/dart-a2a
```

Expected: analyzer reports no issues in the scaffold.

### Bundle 2 - Generated Model And ProtoJSON Helpers

**Files:**

- Create: `packages/dart-a2a/lib/src/generated/a2a.pb.dart`
- Create: `packages/dart-a2a/lib/src/generated/a2a.pbjson.dart`
- Create: `packages/dart-a2a/lib/src/generated/a2a.pbgrpc.dart`
- Create: `packages/dart-a2a/lib/src/core/proto_json.dart`
- Create: `packages/dart-a2a/lib/src/core/validation.dart`
- Test: `packages/dart-a2a/test/core/proto_json_test.dart`
- Test: `packages/dart-a2a/test/core/validation_test.dart`

- [ ] Generate Dart protobuf/grpc outputs from the pinned proto.
- [ ] Add `A2aJson.encodeMessage()` and `A2aJson.mergeMessage()` wrappers so all bindings use the same ProtoJSON naming and default-field policy.
- [ ] Add validators for required fields and oneof invariants that protobuf alone does not enforce.
- [ ] Assert that `SendMessageResponse` and `StreamResponse` contain exactly one payload.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/core/proto_json_test.dart
dart test packages/dart-a2a/test/core/validation_test.dart
```

Expected: tests cover AgentCard, Message, Part, Task, SendMessageResponse, StreamResponse, and validation failures.

### Bundle 3 - Ergonomic Builders And Error Model

**Files:**

- Create: `packages/dart-a2a/lib/src/core/builders.dart`
- Create: `packages/dart-a2a/lib/src/core/errors.dart`
- Create: `packages/dart-a2a/lib/src/core/version.dart`
- Create: `packages/dart-a2a/lib/src/core/headers.dart`
- Test: `packages/dart-a2a/test/core/builders_test.dart`
- Test: `packages/dart-a2a/test/core/errors_test.dart`

- [ ] Add `MessageBuilder`, `PartBuilder`, `AgentCardBuilder`, `TaskBuilder`, and convenience constructors for text, raw bytes, URL, and structured data parts.
- [ ] Add `A2aError` subclasses for parse, invalid request, invalid params, method not found, task not found, unsupported operation, version not supported, authorization, push notification, and extension errors.
- [ ] Map each error to JSON-RPC, REST problem JSON, and gRPC status data.
- [ ] Add `A2aVersionPolicy` with default supported versions `['1.0']`.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/core/builders_test.dart
dart test packages/dart-a2a/test/core/errors_test.dart
```

Expected: builders produce spec-shaped ProtoJSON and errors round-trip through all binding mappers.

### Bundle 4 - Task Store And Service Test Harness

**Files:**

- Create: `packages/dart-a2a/lib/src/server/service.dart`
- Create: `packages/dart-a2a/lib/src/server/task_store.dart`
- Create: `packages/dart-a2a/lib/src/server/subscriptions.dart`
- Create: `packages/dart-a2a/lib/src/server/push_notifications.dart`
- Create: `packages/dart-a2a/lib/src/testing/fake_service.dart`
- Test: `packages/dart-a2a/test/server/task_store_test.dart`
- Test: `packages/dart-a2a/test/server/service_contract_test.dart`

- [ ] Define `A2aService` and request context types.
- [ ] Implement `MemoryTaskStore` with task create/update/get/list/cancel semantics, context filtering, state filtering, pagination, history limits, and artifact inclusion flags.
- [ ] Implement `TaskSubscriptionHub` for streaming status/artifact/message updates to active subscribers.
- [ ] Implement in-memory push config storage with URL validation and duplicate-id replacement.
- [ ] Add a fake service used by binding tests.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/server
```

Expected: in-memory service behavior is deterministic and transport-free.

### Bundle 5 - JSON-RPC Binding

**Files:**

- Create: `packages/dart-a2a/lib/src/json_rpc/messages.dart`
- Create: `packages/dart-a2a/lib/src/json_rpc/codec.dart`
- Create: `packages/dart-a2a/lib/src/json_rpc/handler.dart`
- Create: `packages/dart-a2a/lib/src/json_rpc/sse.dart`
- Test: `packages/dart-a2a/test/json_rpc/json_rpc_binding_test.dart`

- [ ] Implement JSON-RPC 2.0 decode/encode without depending on Glue's existing JSON-RPC package.
- [ ] Dispatch exactly these methods: `SendMessage`, `SendStreamingMessage`, `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, `CreateTaskPushNotificationConfig`, `GetTaskPushNotificationConfig`, `ListTaskPushNotificationConfigs`, `DeleteTaskPushNotificationConfig`, and `GetExtendedAgentCard`.
- [ ] Stream JSON-RPC results as SSE `data:` frames for streaming methods.
- [ ] Validate `A2A-Version` and `A2A-Extensions` service parameters before dispatch.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/json_rpc/json_rpc_binding_test.dart
```

Expected: every JSON-RPC method dispatches to the fake service and returns spec-mapped errors on bad input.

### Bundle 6 - HTTP+JSON/REST Binding

**Files:**

- Create: `packages/dart-a2a/lib/src/rest/routes.dart`
- Create: `packages/dart-a2a/lib/src/rest/sse.dart`
- Create: `packages/dart-a2a/lib/src/rest/problem_json.dart`
- Test: `packages/dart-a2a/test/rest/rest_binding_test.dart`
- Test: `packages/dart-a2a/test/rest/agent_card_test.dart`

- [ ] Mount `/.well-known/agent-card.json`.
- [ ] Mount `POST /message:send`, `POST /message:stream`, `GET /tasks/{id}`, `GET /tasks`, `POST /tasks/{id}:cancel`, `GET /tasks/{id}:subscribe`, push config routes, and `GET /extendedAgentCard`.
- [ ] Support optional tenant path variants by passing tenant into `A2aRequestContext`.
- [ ] Return `application/a2a+json` for normal responses, `text/event-stream` for streaming, and `application/problem+json` for REST errors.
- [ ] Add ETag and `Cache-Control` headers to the public Agent Card route.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/rest
```

Expected: routes match the spec table, query parameters map to request fields, and Agent Card caching headers are present.

### Bundle 7 - gRPC Binding

**Files:**

- Create: `packages/dart-a2a/lib/src/grpc/service_adapter.dart`
- Create: `packages/dart-a2a/lib/src/grpc/client_adapter.dart`
- Test: `packages/dart-a2a/test/grpc/grpc_binding_test.dart`

- [ ] Implement a generated `A2AServiceBase` adapter backed by `A2aService`.
- [ ] Implement `A2aClient.grpc` backed by the generated gRPC client.
- [ ] Map `A2aError` subclasses to gRPC status and details.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/grpc/grpc_binding_test.dart
```

Expected: unary and server-streaming methods round-trip through an in-process fake service.

### Bundle 8 - Unified Client

**Files:**

- Create: `packages/dart-a2a/lib/src/client/a2a_client.dart`
- Create: `packages/dart-a2a/lib/src/client/agent_card_client.dart`
- Create: `packages/dart-a2a/lib/src/security/auth.dart`
- Create: `packages/dart-a2a/lib/src/security/agent_card_signatures.dart`
- Test: `packages/dart-a2a/test/client/client_test.dart`
- Test: `packages/dart-a2a/test/security/security_test.dart`

- [ ] Implement `A2aClient.jsonRpc`, `A2aClient.rest`, and `A2aClient.grpc` behind one interface.
- [ ] Implement Agent Card fetch/discovery with conditional GET support.
- [ ] Select a binding from `supportedInterfaces` by preference order and protocol version.
- [ ] Implement auth injectors for none, bearer, API key, and OAuth token callback.
- [ ] Implement Agent Card JCS canonicalization and JWS signature verification hooks. Hook APIs return verification results; key discovery is caller-provided.
- [ ] Run:

```bash
dart test packages/dart-a2a/test/client packages/dart-a2a/test/security
```

Expected: client construction is ergonomic, binding selection is deterministic, and auth headers never log token values.

### Bundle 9 - Compliance Matrix And Documentation

**Files:**

- Create: `packages/dart-a2a/test/compliance/compliance_matrix_test.dart`
- Create: `packages/dart-a2a/COMPLIANCE.md`
- Create: `packages/dart-a2a/README.md`

- [ ] Add a compliance matrix covering every A2A operation, every binding, every optional capability, and every intentionally unsupported extension.
- [ ] Add README examples for client use, server use, Agent Card construction, streaming, auth, and testing with a fake service.
- [ ] Run:

```bash
dart format --set-exit-if-changed packages/dart-a2a
dart analyze packages/dart-a2a --fatal-infos
dart test packages/dart-a2a
```

Expected: package-local checks are green.

## Test Plan

- Unit tests for validators, builders, errors, version headers, Agent Card canonicalization, auth injectors, and task storage.
- Binding tests for JSON-RPC, REST/SSE, and gRPC.
- Binding-equivalence tests proving the same fake service behavior is visible through all bindings.
- Golden ProtoJSON tests for AgentCard, Message, Part, Task, TaskStatusUpdateEvent, TaskArtifactUpdateEvent, SendMessageResponse, and StreamResponse.
- Security tests for token redaction, private-network push blocking, unsupported auth, malformed security requirements, and extended-card auth requirements.
- Integration tests marked explicitly when they bind local ports.

## Assumptions

- A2A v1.0 is the only supported protocol version in the initial package.
- Generated proto classes remain public because the spec is proto-canonical; builders are convenience APIs, not a replacement model.
- JSON-RPC and REST use ProtoJSON-compatible field names and enum strings.
- Push webhook delivery is supported by the package but disabled by Glue unless configured in the Glue integration plan.
- The package avoids Glue imports permanently.
