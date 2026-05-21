# ACP Registry Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Glue a truthful, registry-ready Agent Client Protocol agent, then prepare the ACP server for stable lifecycle features and draft RFD changes without advertising unsupported behavior.

**Architecture:** Keep the protocol wire model in `packages/glue_server`, keep Glue-specific runtime choices in `cli/lib/src/acp/cli_acp_delegate.dart` and `cli/bin/glue.dart`, and keep registry packaging artifacts separate from runtime code. Advertise only implemented capabilities in `initialize`; add future RFD support behind explicit task boundaries.

**Tech Stack:** Dart 3.12 workspace, JSON-RPC ACP over stdio/WebSocket, `glue_server` protocol DTOs, `glue_harness` session storage, GitHub release binaries, ACP registry `agent.schema.json`.

---

## Status

Planning only. No implementation has been performed by this document.

Current repo state relevant to this plan:

- `agent.json` exists at the repo root and validates against the ACP registry schema.
- `glue acp` supports ACP over stdio and Glue-specific WebSocket framing.
- `initialize` currently returns `protocolVersion`, `agentInfo`, and `agentCapabilities`; it does not emit `authMethods`.
- `session/close` is not implemented.
- `session/list`, `session/load`, `session/resume`, session config options, message IDs, and the draft streamable HTTP transport are not implemented as ACP server features.

## Source Notes

- Initialization requires the agent to return chosen protocol version, capabilities, implementation info, and may return `authMethods`: https://agentclientprotocol.com/protocol/initialization
- Registry authentication currently accepts Agent Auth or Terminal Auth only: https://github.com/agentclientprotocol/registry/blob/main/AUTHENTICATION.md
- `session/close` is stable and advertised through `agentCapabilities.sessionCapabilities.close`: https://agentclientprotocol.com/protocol/session-setup
- `session/list` is stable and advertised through `agentCapabilities.sessionCapabilities.list`: https://agentclientprotocol.com/protocol/session-list
- Session config options are stable and preferred over legacy modes: https://agentclientprotocol.com/protocol/session-config-options
- v2 draft work currently includes new prompt lifecycle, message IDs, and remote transports: https://agentclientprotocol.com/rfds/v2/overview
- Streamable HTTP/WebSocket transport is draft and not the same as Glue's current `--port` WebSocket host: https://agentclientprotocol.com/rfds/streamable-http-websocket-transport

## Non-Goals

- Do not implement draft v2 prompt lifecycle in this pass.
- Do not advertise MCP HTTP/SSE support until Glue actually honors ACP-provided `mcpServers`.
- Do not replace Glue's existing stdio ACP server.
- Do not publish to the external ACP registry from this repo. The final task only prepares the files and command checklist for a registry PR.

## File Structure

### Registry Artifacts

- `agent.json` - local source of the registry manifest. Keep schema-valid and version-pinned to a real GitHub release.
- External registry PR path: `agentclientprotocol/registry/glue/agent.json` - copy of this repo's `agent.json`.
- External registry PR path: `agentclientprotocol/registry/glue/icon.svg` - 16x16 monochrome icon required by the registry.

### ACP Protocol DTOs

- `packages/glue_server/lib/src/acp/messages.dart` - method constants, initialize result shape, auth method DTOs, close/list/config DTOs as tasks land.
- `packages/glue_server/lib/src/acp/server.dart` - JSON-RPC request dispatch for new methods and capability-aware responses.
- `packages/glue_server/lib/glue_server.dart` - barrel export, unchanged unless new files are split out.

### Glue ACP Runtime Wiring

- `cli/bin/glue.dart` - `AcpCommand`, `_config()`, and command registration. Keep thin; if a setup command grows, move it into `cli/lib/src/commands/setup_command.dart`.
- `cli/lib/src/acp/cli_acp_delegate.dart` - session lifecycle, session list/load/resume integration points, and any per-session configuration choices.

### Tests

- `packages/glue_server/test/acp/server_test.dart` - protocol unit tests for initialize, `session/close`, `session/list`, and DTO serialization.
- `packages/glue_server/test/acp/http_host_test.dart` - WebSocket host behavior when initialize changes.
- `cli/test/bin/glue_acp_test.dart` - full stdio process tests.
- `cli/test/bin/glue_acp_ws_test.dart` - full WebSocket process tests.
- `cli/test/commands/setup_command_test.dart` - setup/auth command tests if `glue setup` is added as a separate command file.

---

## Bundle 1 - Registry Manifest And Icon

**Scope:** Keep the local registry manifest valid, add the missing icon artifact for the external registry PR, and document the exact PR assembly commands. No ACP runtime behavior changes.

**Files:**

- Modify: `agent.json`
- Create: `docs/plans/2026-05-21-acp-registry-readiness-plan.md`
- External create: `agentclientprotocol/registry/glue/icon.svg`
- External create: `agentclientprotocol/registry/glue/agent.json`

- [ ] **Step 1: Verify `agent.json` is still pinned to the current release**

  Run:

  ```bash
  gh release view v0.6.0 --repo HelgeSverre/glue --json assets --jq '.assets[].name'
  ```

  Expected output includes:

  ```text
  glue-linux-arm64
  glue-linux-x64
  glue-macos-arm64
  glue-windows-x64.exe
  SHA256SUMS
  ```

- [ ] **Step 2: Validate `agent.json` against the registry schema**

  Run:

  ```bash
  curl -sS https://raw.githubusercontent.com/agentclientprotocol/registry/main/agent.schema.json -o /tmp/acp-agent.schema.json
  uv run --with jsonschema python -c "import json, jsonschema; schema=json.load(open('/tmp/acp-agent.schema.json')); agent=json.load(open('agent.json')); jsonschema.Draft7Validator.check_schema(schema); jsonschema.validate(agent, schema); print('agent.json validates')"
  ```

  Expected:

  ```text
  agent.json validates
  ```

- [ ] **Step 3: Prepare a 16x16 monochrome registry icon**

  In the external registry checkout, create `glue/icon.svg`:

  ```svg
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="none">
    <circle cx="8" cy="8" r="6" fill="currentColor"/>
    <circle cx="8" cy="8" r="2.25" fill="#fff"/>
  </svg>
  ```

  This deliberately uses `currentColor` for the outer mark so the registry can theme it.

- [ ] **Step 4: Assemble the external registry PR files**

  From a checkout of `agentclientprotocol/registry`:

  ```bash
  mkdir -p glue
  cp /Users/helge/code/glue/agent.json glue/agent.json
  test -f glue/icon.svg
  ```

  Expected:

  ```text
  # no output from mkdir/cp/test
  ```

- [ ] **Step 5: Commit the registry artifacts in the registry checkout**

  Run in the external registry checkout:

  ```bash
  git add glue/agent.json glue/icon.svg
  git commit -m "Add Glue ACP agent"
  ```

  Expected: a commit containing only `glue/agent.json` and `glue/icon.svg`.

---

## Bundle 2 - Terminal Setup Command For Registry Auth

**Scope:** Add a small terminal setup entry point that registry clients can invoke through Terminal Auth. This gives `authMethods` a real command to point at instead of pretending `glue acp` itself is an interactive setup flow.

**Files:**

- Create: `cli/lib/src/commands/setup_command.dart`
- Modify: `cli/bin/glue.dart`
- Test: `cli/test/commands/setup_command_test.dart`
- Test: `cli/test/cli_args_test.dart`

- [ ] **Step 1: Write failing tests for `glue setup --check`**

  Create `cli/test/commands/setup_command_test.dart`:

  ```dart
  import 'dart:io';

  import 'package:glue/src/commands/setup_command.dart';
  import 'package:test/test.dart';

  void main() {
    group('SetupCommand', () {
      test('check mode returns guidance without mutating GLUE_HOME', () async {
        final tmp = Directory.systemTemp.createTempSync('glue_setup_test_');
        addTearDown(() => tmp.deleteSync(recursive: true));

        final result = await runGlueSetupCheckForTest(
          environment: {'GLUE_HOME': tmp.path},
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('Glue setup'));
        expect(result.stdout, contains('glue config init'));
        expect(result.stdout, contains('glue doctor'));
        expect(File('${tmp.path}/config.yaml').existsSync(), isFalse);
      });
    });
  }
  ```

- [ ] **Step 2: Run the failing test**

  Run:

  ```bash
  dart test cli/test/commands/setup_command_test.dart
  ```

  Expected: FAIL because `setup_command.dart` does not exist.

- [ ] **Step 3: Implement `SetupCommand`**

  Create `cli/lib/src/commands/setup_command.dart`:

  ```dart
  import 'dart:io';

  import 'package:args/command_runner.dart';

  class SetupCheckResult {
    const SetupCheckResult({required this.exitCode, required this.stdout});
    final int exitCode;
    final String stdout;
  }

  Future<SetupCheckResult> runGlueSetupCheckForTest({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final home = env['GLUE_HOME'] ?? '${env['HOME'] ?? '~'}/.glue';
    return SetupCheckResult(
      exitCode: 0,
      stdout:
          'Glue setup\n\n'
          'Configuration home: $home\n\n'
          'Run these commands to prepare Glue:\n'
          '  glue config init\n'
          '  glue doctor\n\n'
          'Set one model provider credential before using `glue acp`:\n'
          '  export ANTHROPIC_API_KEY=...\n'
          '  export OPENAI_API_KEY=...\n'
          '  or choose GitHub Copilot in the interactive UI.\n',
    );
  }

  class SetupCommand extends Command<int> {
    SetupCommand() {
      argParser.addFlag(
        'check',
        defaultsTo: true,
        negatable: false,
        help: 'Print setup guidance for terminal-based ACP registry auth.',
      );
    }

    @override
    String get name => 'setup';

    @override
    String get description => 'Show terminal setup steps for Glue.';

    @override
    Future<int> run() async {
      final result = await runGlueSetupCheckForTest();
      stdout.write(result.stdout);
      return result.exitCode;
    }
  }
  ```

- [ ] **Step 4: Register the command**

  Modify `cli/bin/glue.dart` imports:

  ```dart
  import 'package:glue/src/commands/setup_command.dart';
  ```

  In `GlueCommandRunner()` add:

  ```dart
  addCommand(SetupCommand());
  ```

- [ ] **Step 5: Verify tests pass**

  Run:

  ```bash
  dart test cli/test/commands/setup_command_test.dart cli/test/cli_args_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add cli/lib/src/commands/setup_command.dart cli/bin/glue.dart cli/test/commands/setup_command_test.dart cli/test/cli_args_test.dart
  git commit -m "feat: add terminal setup command"
  ```

---

## Bundle 3 - Initialize Auth Methods And Truthful Capabilities

**Scope:** Add `authMethods` to `initialize`, advertise a real Terminal Auth method that points at `glue setup`, and add conservative capability metadata. Do not advertise session close until Bundle 4 lands.

**Files:**

- Modify: `packages/glue_server/lib/src/acp/messages.dart`
- Modify: `packages/glue_server/lib/src/acp/server.dart`
- Modify: `cli/bin/glue.dart`
- Test: `packages/glue_server/test/acp/server_test.dart`
- Test: `cli/test/bin/glue_acp_test.dart`
- Test: `cli/test/bin/glue_acp_ws_test.dart`

- [ ] **Step 1: Write failing protocol tests for `authMethods`**

  Extend `packages/glue_server/test/acp/server_test.dart` initialize test:

  ```dart
  expect(result['authMethods'], isA<List<Object?>>());
  final authMethods = result['authMethods']! as List<Object?>;
  expect(authMethods, isNotEmpty);
  expect(
    authMethods.any(
      (m) =>
          m is Map &&
          m['type'] == 'terminal' &&
          (m['args'] as List<Object?>).contains('setup'),
    ),
    isTrue,
  );
  ```

  Extend `cli/test/bin/glue_acp_test.dart` initialize test with the same assertion against the spawned CLI response.

- [ ] **Step 2: Run failing tests**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart
  ```

  Expected: FAIL because `authMethods` is missing.

- [ ] **Step 3: Add auth method DTOs**

  Modify `packages/glue_server/lib/src/acp/messages.dart`:

  ```dart
  class InitializeResult {
    const InitializeResult({
      required this.protocolVersion,
      required this.agentInfo,
      this.agentCapabilities = const {},
      this.authMethods = const [],
    });

    final int protocolVersion;
    final AgentInfo agentInfo;
    final Map<String, Object?> agentCapabilities;
    final List<AuthMethod> authMethods;

    Map<String, Object?> toJson() => {
      'protocolVersion': protocolVersion,
      'agentInfo': agentInfo.toJson(),
      'agentCapabilities': agentCapabilities,
      'authMethods': [for (final method in authMethods) method.toJson()],
    };
  }

  class AuthMethod {
    const AuthMethod({
      required this.id,
      required this.name,
      required this.description,
      required this.type,
      this.args = const [],
      this.env = const {},
    });

    final String id;
    final String name;
    final String description;
    final String type;
    final List<String> args;
    final Map<String, String> env;

    Map<String, Object?> toJson() => {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      if (args.isNotEmpty) 'args': args,
      if (env.isNotEmpty) 'env': env,
    };
  }
  ```

- [ ] **Step 4: Thread auth methods through server config**

  Modify `packages/glue_server/lib/src/acp/server.dart`:

  ```dart
  class AcpServerConfig {
    const AcpServerConfig({
      this.protocolVersion = 1,
      this.agentInfo = const AgentInfo(name: 'glue', title: 'Glue'),
      this.agentCapabilities = const {},
      this.authMethods = const [],
    });

    final int protocolVersion;
    final AgentInfo agentInfo;
    final Map<String, Object?> agentCapabilities;
    final List<AuthMethod> authMethods;
  }
  ```

  In the initialize response:

  ```dart
  result: InitializeResult(
    protocolVersion: config.protocolVersion,
    agentInfo: config.agentInfo,
    agentCapabilities: config.agentCapabilities,
    authMethods: config.authMethods,
  ).toJson(),
  ```

- [ ] **Step 5: Configure Glue's initial auth and capabilities**

  Modify `cli/bin/glue.dart` `_config()`:

  ```dart
  AcpServerConfig _config() => const AcpServerConfig(
    protocolVersion: 1,
    agentInfo: AgentInfo(
      name: 'glue',
      title: 'Glue',
      version: AppConstants.version,
    ),
    agentCapabilities: {
      'promptCapabilities': {
        'image': true,
        'audio': false,
        'embeddedContext': false,
      },
      'sessionCapabilities': {},
    },
    authMethods: [
      AuthMethod(
        id: 'glue-terminal-setup',
        name: 'Run Glue setup',
        description: 'Open a terminal setup flow for Glue configuration and provider credentials.',
        type: 'terminal',
        args: ['setup'],
      ),
    ],
  );
  ```

  Keep `mcpCapabilities` absent until ACP-provided MCP servers are actually honored.

- [ ] **Step 6: Verify tests pass**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart cli/test/bin/glue_acp_ws_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add packages/glue_server/lib/src/acp/messages.dart packages/glue_server/lib/src/acp/server.dart cli/bin/glue.dart packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart cli/test/bin/glue_acp_ws_test.dart
  git commit -m "feat: advertise ACP auth methods"
  ```

---

## Bundle 4 - Stable `session/close`

**Scope:** Implement the stabilized `session/close` method, release active sessions without killing the whole ACP process, and advertise `sessionCapabilities.close`.

**Files:**

- Modify: `packages/glue_server/lib/src/acp/messages.dart`
- Modify: `packages/glue_server/lib/src/acp/server.dart`
- Modify: `cli/bin/glue.dart`
- Test: `packages/glue_server/test/acp/server_test.dart`
- Test: `packages/glue_server/test/acp/http_host_test.dart`

- [ ] **Step 1: Write failing server tests for `session/close`**

  Add to `packages/glue_server/test/acp/server_test.dart`:

  ```dart
  test('session/close closes a known session and rejects later prompts', () async {
    final delegate = _FakeDelegate(scripted: const []);
    final server = AcpServer(transport: transport, delegate: delegate);
    final serverFuture = server.serve();

    input.add(utf8.encode(
      '{"jsonrpc":"2.0","id":1,"method":"session/new","params":{"cwd":"/tmp/p"}}\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    var sent = await readSent();
    final sessionId = (sent.single['result']! as Map)['sessionId'] as String;
    output.buffer.clear();

    input.add(utf8.encode(
      '{"jsonrpc":"2.0","id":2,"method":"session/close","params":{"sessionId":"$sessionId"}}\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    sent = await readSent();
    expect((sent.singleWhere((m) => m['id'] == 2)['result']! as Map), isEmpty);
    output.buffer.clear();

    input.add(utf8.encode(
      '{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"$sessionId","prompt":[{"type":"text","text":"hi"}]}}\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await input.close();
    await serverFuture;

    sent = await readSent();
    final err = sent.singleWhere((m) => m['id'] == 3)['error']! as Map;
    expect(err['code'], -32001);
  });
  ```

  Add an initialize capability assertion:

  ```dart
  final caps = result['agentCapabilities']! as Map<String, Object?>;
  expect(((caps['sessionCapabilities']! as Map)['close']! as Map), isEmpty);
  ```

- [ ] **Step 2: Run failing test**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart
  ```

  Expected: FAIL because `session/close` is not implemented.

- [ ] **Step 3: Add close method and DTOs**

  Modify `packages/glue_server/lib/src/acp/messages.dart`:

  ```dart
  abstract final class AcpMethod {
    static const initialize = 'initialize';
    static const sessionNew = 'session/new';
    static const sessionClose = 'session/close';
    static const sessionPrompt = 'session/prompt';
    static const sessionCancel = 'session/cancel';
    static const sessionUpdate = 'session/update';
    static const sessionRequestPermission = 'session/request_permission';
    static const sessionUsageSummary = 'session/usage_summary';
  }

  class SessionCloseParams {
    const SessionCloseParams({required this.sessionId});
    final String sessionId;

    factory SessionCloseParams.fromJson(Map<String, Object?> json) =>
        SessionCloseParams(sessionId: json['sessionId'] as String);
  }
  ```

- [ ] **Step 4: Handle `session/close` in the server**

  Modify `packages/glue_server/lib/src/acp/server.dart` request dispatch:

  ```dart
  case AcpMethod.sessionClose:
    if (params == null) {
      _replyInvalidParams(id, 'session/close requires params');
      return;
    }
    final closeParams = SessionCloseParams.fromJson(params);
    if (!_knownSessions.contains(closeParams.sessionId)) {
      transport.send(
        JsonRpcError(
          id: id,
          code: JsonRpcErrorCode.sessionNotFound,
          message: 'unknown session: ${closeParams.sessionId}',
        ),
      );
      return;
    }
    delegate.cancelPrompt(closeParams.sessionId);
    await delegate.closeSession(closeParams.sessionId);
    _knownSessions.remove(closeParams.sessionId);
    transport.send(JsonRpcResponse(id: id, result: <String, Object?>{}));
  ```

- [ ] **Step 5: Advertise close capability**

  Modify `cli/bin/glue.dart` `_config()` after the close handler lands:

  ```dart
  agentCapabilities: {
    'promptCapabilities': {
      'image': true,
      'audio': false,
      'embeddedContext': false,
    },
    'sessionCapabilities': {
      'close': {},
    },
  },
  ```

- [ ] **Step 6: Verify tests pass**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart packages/glue_server/test/acp/http_host_test.dart cli/test/bin/glue_acp_test.dart cli/test/bin/glue_acp_ws_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add packages/glue_server/lib/src/acp/messages.dart packages/glue_server/lib/src/acp/server.dart cli/bin/glue.dart packages/glue_server/test/acp/server_test.dart packages/glue_server/test/acp/http_host_test.dart cli/test/bin/glue_acp_test.dart cli/test/bin/glue_acp_ws_test.dart
  git commit -m "feat: support ACP session close"
  ```

---

## Bundle 5 - Stable `session/list`

**Scope:** Let ACP clients discover saved Glue sessions. This is stable ACP and maps to `SessionStore.listSessions()`, but it should land after close because it increases the active session surface clients can manage.

**Files:**

- Modify: `packages/glue_server/lib/src/acp/messages.dart`
- Modify: `packages/glue_server/lib/src/acp/server.dart`
- Modify: `cli/lib/src/acp/cli_acp_delegate.dart`
- Modify: `cli/bin/glue.dart`
- Test: `packages/glue_server/test/acp/server_test.dart`
- Test: `cli/test/bin/glue_acp_test.dart`

- [ ] **Step 1: Add delegate contract for list sessions**

  Modify `packages/glue_server/lib/src/acp/server.dart`:

  ```dart
  abstract class AcpServerDelegate {
    Future<String> createSession(SessionNewParams params);
    Future<ListSessionsResult> listSessions(ListSessionsParams params);
    Stream<AgentEvent> prompt({
      required String sessionId,
      required String userMessage,
      required Future<bool> Function(ToolCall call) requestPermission,
      List<ContentPart> userContentParts = const [],
    });
    void cancelPrompt(String sessionId);
    UsageReport usageSummary(String sessionId);
    Future<void> closeSession(String sessionId);
  }
  ```

  Update fake delegates in tests to return an empty list until each test overrides it.

- [ ] **Step 2: Add list DTOs**

  Modify `packages/glue_server/lib/src/acp/messages.dart`:

  ```dart
  class ListSessionsParams {
    const ListSessionsParams({this.cwd, this.cursor});
    final String? cwd;
    final String? cursor;

    factory ListSessionsParams.fromJson(Map<String, Object?> json) =>
        ListSessionsParams(
          cwd: json['cwd'] as String?,
          cursor: json['cursor'] as String?,
        );
  }

  class ListSessionsResult {
    const ListSessionsResult({required this.sessions, this.nextCursor});
    final List<AcpSessionInfo> sessions;
    final String? nextCursor;

    Map<String, Object?> toJson() => {
      'sessions': [for (final session in sessions) session.toJson()],
      if (nextCursor != null) 'nextCursor': nextCursor,
    };
  }

  class AcpSessionInfo {
    const AcpSessionInfo({
      required this.sessionId,
      required this.cwd,
      this.title,
      this.updatedAt,
      this.meta = const {},
    });

    final String sessionId;
    final String cwd;
    final String? title;
    final DateTime? updatedAt;
    final Map<String, Object?> meta;

    Map<String, Object?> toJson() => {
      'sessionId': sessionId,
      'cwd': cwd,
      if (title != null) 'title': title,
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      if (meta.isNotEmpty) '_meta': meta,
    };
  }
  ```

- [ ] **Step 3: Dispatch `session/list`**

  Add `static const sessionList = 'session/list';` to `AcpMethod`.

  Add a request handler in `packages/glue_server/lib/src/acp/server.dart`:

  ```dart
  case AcpMethod.sessionList:
    final listParams = ListSessionsParams.fromJson(params ?? const {});
    final result = await delegate.listSessions(listParams);
    transport.send(JsonRpcResponse(id: id, result: result.toJson()));
  ```

- [ ] **Step 4: Implement Glue session listing**

  Modify `cli/lib/src/acp/cli_acp_delegate.dart`:

  ```dart
  @override
  Future<ListSessionsResult> listSessions(ListSessionsParams params) async {
    final all = services.manager.listSessions();
    final filtered = params.cwd == null
        ? all
        : all.where((meta) => meta.cwd == params.cwd).toList();
    final page = filtered.take(50).map((meta) {
      final updatedAt = meta.titleLastEvaluatedAt ??
          meta.titleGeneratedAt ??
          meta.endTime ??
          meta.startTime;
      return AcpSessionInfo(
        sessionId: meta.id.value,
        cwd: meta.cwd,
        title: meta.title,
        updatedAt: updatedAt,
        meta: {
          if (meta.messageCount != null) 'messageCount': meta.messageCount,
          if (meta.summary != null) 'summary': meta.summary,
        },
      );
    }).toList();
    return ListSessionsResult(sessions: page);
  }
  ```

  This first iteration returns at most 50 newest sessions and omits pagination. Add pagination in a follow-up only if a client needs it.

- [ ] **Step 5: Advertise list capability**

  Modify `cli/bin/glue.dart`:

  ```dart
  'sessionCapabilities': {
    'close': {},
    'list': {},
  },
  ```

- [ ] **Step 6: Verify tests pass**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add packages/glue_server/lib/src/acp/messages.dart packages/glue_server/lib/src/acp/server.dart cli/lib/src/acp/cli_acp_delegate.dart cli/bin/glue.dart packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart
  git commit -m "feat: support ACP session list"
  ```

---

## Bundle 6 - Session Config Options Substrate

**Scope:** Add protocol DTOs for session config options and return read-only initial state for the current model and approval mode in `session/new`. Do not add mutation until client demand is clear.

**Files:**

- Modify: `packages/glue_server/lib/src/acp/messages.dart`
- Modify: `cli/lib/src/acp/cli_acp_delegate.dart`
- Test: `packages/glue_server/test/acp/server_test.dart`

- [ ] **Step 1: Add config option DTOs**

  Modify `packages/glue_server/lib/src/acp/messages.dart`:

  ```dart
  class SessionConfigOption {
    const SessionConfigOption({
      required this.id,
      required this.name,
      required this.category,
      required this.type,
      required this.currentValue,
      this.description,
      this.options = const [],
    });

    final String id;
    final String name;
    final String category;
    final String type;
    final String currentValue;
    final String? description;
    final List<SessionConfigChoice> options;

    Map<String, Object?> toJson() => {
      'id': id,
      'name': name,
      'category': category,
      'type': type,
      'currentValue': currentValue,
      if (description != null) 'description': description,
      if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
    };
  }

  class SessionConfigChoice {
    const SessionConfigChoice({
      required this.value,
      required this.name,
      this.description,
    });

    final String value;
    final String name;
    final String? description;

    Map<String, Object?> toJson() => {
      'value': value,
      'name': name,
      if (description != null) 'description': description,
    };
  }
  ```

- [ ] **Step 2: Extend `SessionNewResult`**

  Modify `SessionNewResult`:

  ```dart
  class SessionNewResult {
    const SessionNewResult({
      required this.sessionId,
      this.configOptions = const [],
    });

    final String sessionId;
    final List<SessionConfigOption> configOptions;

    Map<String, Object?> toJson() => {
      'sessionId': sessionId,
      if (configOptions.isNotEmpty)
        'configOptions': [for (final option in configOptions) option.toJson()],
    };
  }
  ```

- [ ] **Step 3: Add delegate hook for session-new config**

  Modify `AcpServerDelegate.createSession` to return a richer object only if needed:

  ```dart
  class AcpCreatedSession {
    const AcpCreatedSession({
      required this.sessionId,
      this.configOptions = const [],
    });
    final String sessionId;
    final List<SessionConfigOption> configOptions;
  }
  ```

  Change the delegate signature:

  ```dart
  Future<AcpCreatedSession> createSession(SessionNewParams params);
  ```

  Update all implementations and tests.

- [ ] **Step 4: Return model and approval config options**

  In `cli/lib/src/acp/cli_acp_delegate.dart`, return:

  ```dart
  return AcpCreatedSession(
    sessionId: id,
    configOptions: [
      SessionConfigOption(
        id: 'model',
        name: 'Model',
        category: 'model',
        type: 'select',
        currentValue: services.config.activeModel.toString(),
      ),
      const SessionConfigOption(
        id: 'approval',
        name: 'Approval mode',
        category: 'mode',
        type: 'select',
        currentValue: 'confirm',
        options: [
          SessionConfigChoice(value: 'confirm', name: 'Confirm'),
        ],
      ),
    ],
  );
  ```

- [ ] **Step 5: Verify tests pass**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add packages/glue_server/lib/src/acp/messages.dart packages/glue_server/lib/src/acp/server.dart cli/lib/src/acp/cli_acp_delegate.dart packages/glue_server/test/acp/server_test.dart cli/test/bin/glue_acp_test.dart
  git commit -m "feat: expose ACP session config options"
  ```

---

## Bundle 7 - Draft RFD Guardrails

**Scope:** Add comments, tests, and issue-ready notes that make future v2 work easier without implementing draft protocol features.

**Files:**

- Modify: `packages/glue_server/lib/src/acp/messages.dart`
- Modify: `packages/glue_server/lib/src/acp/http_host.dart`
- Modify: `website/docs/advanced/acp-server.md`
- Test: `packages/glue_server/test/acp/http_host_test.dart`

- [ ] **Step 1: Document current WebSocket transport accurately**

  In `website/docs/advanced/acp-server.md`, add a short section:

  ```markdown
  ## Transport status

  `glue acp --stdio` is the primary ACP transport.

  `glue acp --port` exposes Glue's current JSON-RPC-over-WebSocket host for
  local clients and testing. It is not the draft ACP Streamable HTTP transport:
  it does not implement `Acp-Connection-Id`, per-session SSE streams, POST/GET
  routing, or HTTP/2 stream semantics yet.
  ```

- [ ] **Step 2: Add `_meta` tolerance note**

  In `packages/glue_server/lib/src/acp/messages.dart`, add a file-level note near DTO parsing:

  ```dart
  // ACP reserves `_meta` on most request/response objects. Glue DTOs ignore it
  // unless a feature explicitly needs it, which keeps the server tolerant of
  // clients that attach extension metadata.
  ```

- [ ] **Step 3: Add unknown-field regression test**

  In `packages/glue_server/test/acp/server_test.dart`, add a `session/new` test with `_meta`:

  ```dart
  input.add(
    utf8.encode(
      '{"jsonrpc":"2.0","id":1,"method":"session/new","params":'
      '{"cwd":"/tmp/abc","_meta":{"client":"future-test"}}}\n',
    ),
  );
  ```

  Expected: server returns a normal `sessionId`.

- [ ] **Step 4: Add transport guardrail test**

  In `packages/glue_server/test/acp/http_host_test.dart`, keep existing WebSocket tests and add one explicit assertion that plain POST is rejected until Streamable HTTP is implemented:

  ```dart
  test('plain POST is not treated as draft streamable HTTP', () async {
    final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
    final port = await host.start(port: 0);
    addTearDown(host.stop);

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/acp'));
    request.headers.contentType = ContentType.json;
    request.write('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}');
    final response = await request.close();
    expect(response.statusCode, 400);
    await response.drain<void>();
  });
  ```

- [ ] **Step 5: Verify tests pass**

  Run:

  ```bash
  dart test packages/glue_server/test/acp/server_test.dart packages/glue_server/test/acp/http_host_test.dart
  ```

  Expected: all selected tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add packages/glue_server/lib/src/acp/messages.dart packages/glue_server/lib/src/acp/http_host.dart packages/glue_server/test/acp/server_test.dart packages/glue_server/test/acp/http_host_test.dart website/docs/advanced/acp-server.md
  git commit -m "docs: clarify ACP transport boundaries"
  ```

---

## Bundle 8 - Registry PR Dry Run

**Scope:** Prove the registry entry works against the current public registry checks after Bundles 1-4. This should be done in a temporary checkout of `agentclientprotocol/registry`.

**Files:**

- External modify: `agentclientprotocol/registry/glue/agent.json`
- External create: `agentclientprotocol/registry/glue/icon.svg`
- No Glue repo code changes

- [ ] **Step 1: Create a temporary registry checkout**

  Run:

  ```bash
  mkdir -p /private/tmp/acp-registry-glue
  git clone https://github.com/agentclientprotocol/registry.git /private/tmp/acp-registry-glue/registry
  ```

- [ ] **Step 2: Copy Glue registry files**

  Run:

  ```bash
  cd /private/tmp/acp-registry-glue/registry
  mkdir -p glue
  cp /Users/helge/code/glue/agent.json glue/agent.json
  test -f glue/icon.svg
  ```

- [ ] **Step 3: Run registry validation commands**

  First inspect the registry README and package scripts:

  ```bash
  sed -n '1,220p' README.md
  test -f package.json && node -e "const p=require('./package.json'); console.log(p.scripts)"
  ```

  Then run the validation command documented by the registry. If the registry uses npm scripts, prefer:

  ```bash
  npm test
  ```

  Expected: validation succeeds. If it fails on auth handshake, inspect the failure before changing Glue; the likely missing piece is the `authMethods` shape from Bundle 3.

- [ ] **Step 4: Commit in registry checkout**

  ```bash
  git add glue/agent.json glue/icon.svg
  git commit -m "Add Glue ACP agent"
  ```

---

## Review Checklist

- [ ] `initialize` includes `authMethods` in both unit and spawned CLI tests.
- [ ] `authMethods` points to a command that exists and exits cleanly.
- [ ] `agentCapabilities` does not advertise MCP HTTP/SSE until ACP `mcpServers` are honored.
- [ ] `sessionCapabilities.close` is advertised only after `session/close` works.
- [ ] `sessionCapabilities.list` is advertised only after `session/list` works.
- [ ] `glue acp --port` docs clearly distinguish current WebSocket support from draft Streamable HTTP.
- [ ] `agent.json` uses versioned release URLs, not `latest`.
- [ ] Registry icon is 16x16 and monochrome/themable.

## Verification Commands

Run these from `/Users/helge/code/glue` after each relevant bundle:

```bash
dart test packages/glue_server/test/acp/server_test.dart
dart test packages/glue_server/test/acp/http_host_test.dart
dart test cli/test/bin/glue_acp_test.dart
dart test cli/test/bin/glue_acp_ws_test.dart
python3 -m json.tool agent.json >/tmp/glue-agent-json.pretty
uv run --with jsonschema python -c "import json, jsonschema; schema=json.load(open('/tmp/acp-agent.schema.json')); agent=json.load(open('agent.json')); jsonschema.validate(agent, schema); print('agent.json validates')"
```

Use the full workspace gate before a release:

```bash
just check
```
