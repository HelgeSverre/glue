/// CLI wiring for the ACP server: a [AcpServerDelegate] that creates a
/// per-session [AgentCore] + tool registry through the harness's
/// [ServiceLocator], runs prompts, and routes permission decisions
/// through the harness's [PermissionGate].
///
/// One CLI process can host multiple ACP sessions concurrently — each
/// gets its own AgentCore + tool registry but shares the
/// [GlueConfig] / [Observability] / [SkillRuntime] from the locator's
/// startup work.
library;

import 'dart:async';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_server/glue_server.dart';

class CliAcpDelegate extends AcpServerDelegate {
  CliAcpDelegate({required this.services});

  final AppServices services;

  // Per-session state, keyed by ACP sessionId.
  final Map<String, _AcpSession> _sessions = {};
  int _sessionCounter = 0;

  @override
  Future<String> createSession(SessionNewParams params) async {
    _sessionCounter++;
    final id = 'glue-${DateTime.now().millisecondsSinceEpoch}-$_sessionCounter';

    // Build a tool registry using the locator's executor + shared
    // services. Subagent tools are intentionally omitted in v1 — they
    // need their own permission flow per spawned child.
    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(services.executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
    };

    final llm = services.llmFactory.createFromConfig(
      systemPrompt: services.systemPrompt,
    );
    final agent = AgentCore(
      llm: llm,
      tools: tools,
      modelId: services.config.activeModel.modelId,
      obs: services.obs,
    );

    // Permission gate: confirm-mode unless the client allowlists tools
    // via a future capability. v1 always asks for mutating tools.
    final gate = PermissionGate(
      approvalMode: ApprovalMode.confirm,
      trustedTools: services.trustedTools,
      tools: tools,
      cwd: params.cwd,
    );

    _sessions[id] = _AcpSession(agent: agent, gate: gate);
    return id;
  }

  @override
  Stream<AgentEvent> prompt({
    required String sessionId,
    required String userMessage,
    required Future<bool> Function(ToolCall call) requestPermission,
    List<ContentPart> userContentParts = const [],
  }) async* {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('unknown ACP session: $sessionId');
    }

    final controller = StreamController<AgentEvent>();
    session.activeController = controller;
    final agentEvents = session.agent.run(
      userMessage,
      userContentParts: userContentParts.isEmpty ? null : userContentParts,
    );

    final innerSub = agentEvents.listen(
      (event) async {
        // Forward straight through for non-tool events.
        if (event is! AgentToolCall) {
          controller.add(event);
          return;
        }

        // For tool calls: gate locally first, fall back to client.
        controller.add(event); // tell the client a tool is starting
        final decision = session.gate.resolve(event.call);
        bool granted;
        switch (decision) {
          case PermissionDecision.allow:
            granted = true;
          case PermissionDecision.deny:
            granted = false;
          case PermissionDecision.ask:
            granted = await requestPermission(event.call);
        }

        try {
          final result = granted
              ? await session.agent.executeTool(event.call)
              : ToolResult.denied(event.call.id);
          session.agent.completeToolCall(result.withCallId(event.call.id));
          controller.add(AgentToolResult(result.withCallId(event.call.id)));
        } on Object catch (e) {
          final err = ToolResult(
            callId: event.call.id,
            success: false,
            content: 'tool execution failed: $e',
          );
          session.agent.completeToolCall(err);
          controller.add(AgentToolResult(err));
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    try {
      yield* controller.stream;
    } finally {
      await innerSub.cancel();
      session.activeController = null;
    }
  }

  @override
  UsageReport usageSummary(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      // Empty report rather than throwing — matches the CLI's "no calls"
      // behaviour and lets a polling client distinguish "session exists
      // but quiet" from "unknown session" via the JSON-RPC error level.
      return buildUsageReport(usageEvents: const [], sessionId: sessionId);
    }
    final stats = session.agent.stats;
    if (stats.turnCount == 0) {
      return buildUsageReport(
        usageEvents: const [],
        sessionId: sessionId,
        modelLabel: services.config.activeModel.toString(),
      );
    }
    // ACP sessions go straight through AgentCore — there's no
    // SessionManager writing JSONL — so we synthesise a single 'main'
    // row from the live agent stats. Subagent / title roles will fall
    // out for free once those flows are wired into ACP sessions.
    return buildUsageReport(
      usageEvents: [
        {
          'type': 'usage',
          'role': 'main',
          'input_tokens': stats.inputTokens,
          'output_tokens': stats.outputTokens,
          'cache_read_tokens': stats.cacheReadTokens,
          'cache_creation_tokens': stats.cacheCreationTokens,
          'turn_count': stats.turnCount,
        }
      ],
      sessionId: sessionId,
      modelLabel: services.config.activeModel.toString(),
    );
  }

  @override
  void cancelPrompt(String sessionId) {
    final session = _sessions[sessionId];
    final controller = session?.activeController;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  @override
  Future<void> closeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    final controller = session?.activeController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    // Tool resources (browsers, executors) are owned by AppServices;
    // closing them is the harness's responsibility on process exit.
  }
}

class _AcpSession {
  _AcpSession({required this.agent, required this.gate});
  final AgentCore agent;
  final PermissionGate gate;
  StreamController<AgentEvent>? activeController;
}
