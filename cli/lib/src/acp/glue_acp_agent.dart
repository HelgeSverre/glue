import 'dart:async';
import 'dart:convert';

import 'package:acp/acp.dart';
import 'package:acp/transport.dart';
import 'package:glue/src/acp/acp_session.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/prompts.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/shell/executor_factory.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_tool.dart';

final class GlueAcpRuntime {
  final AgentSideConnection connection;
  final Map<String, Tool> tools;

  GlueAcpRuntime({
    required this.connection,
    required this.tools,
  });

  Future<void> get done =>
      connection.onStateChange.firstWhere((s) => s == ConnectionState.closed);

  Future<void> close() async {
    await connection.close();
    for (final tool in tools.values) {
      try {
        await tool.dispose();
      } catch (_) {}
    }
  }
}

Future<void> runAcpServer({
  String? model,
  Environment? environment,
}) async {
  final runtime = await GlueAcpRuntimeFactory.create(
    model: model,
    environment: environment,
  );
  try {
    await runtime.done;
  } finally {
    await runtime.close();
  }
}

final class GlueAcpRuntimeFactory {
  static Future<GlueAcpRuntime> create({
    String? model,
    Environment? environment,
  }) async {
    final env = environment ?? Environment.detect();
    final config = GlueConfig.load(cliModel: model, environment: env);
    config.validate();

    final skillRuntime = SkillRuntime(
      cwd: env.cwd,
      extraPathsProvider: () => config.skillPaths,
      environment: env,
    );
    final llmFactory = LlmClientFactory(config);
    final executor = await ExecutorFactory.create(
      shellConfig: config.shellConfig,
      dockerConfig: config.dockerConfig,
      cwd: env.cwd,
    );

    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
      'skill': SkillTool(skillRuntime),
    };

    final transport = StdioTransport()..start();
    late final AgentSideConnection connection;
    connection = AgentSideConnection(
      transport,
      handlerFactory: (_) => GlueAcpAgent(
        connection: connection,
        llmFactory: llmFactory,
        skillRuntime: skillRuntime,
        tools: tools,
        modelId: config.activeModel.modelId,
      ),
    );

    return GlueAcpRuntime(connection: connection, tools: tools);
  }
}

final class GlueAcpAgent extends AgentHandler {
  final AgentSideConnection _connection;
  final LlmClientFactory _llmFactory;
  final SkillRuntime _skillRuntime;
  final Map<String, Tool> _tools;
  final String _modelId;
  final Map<String, AcpSession> _sessions = <String, AcpSession>{};
  int _sessionCounter = 0;

  GlueAcpAgent({
    required AgentSideConnection connection,
    required LlmClientFactory llmFactory,
    required SkillRuntime skillRuntime,
    required Map<String, Tool> tools,
    required String modelId,
  })  : _connection = connection,
        _llmFactory = llmFactory,
        _skillRuntime = skillRuntime,
        _tools = tools,
        _modelId = modelId;

  @override
  Future<InitializeResponse> initialize(
    InitializeRequest request, {
    required AcpCancellationToken cancelToken,
  }) async {
    return const InitializeResponse(
      protocolVersion: 1,
      agentInfo: ImplementationInfo(
        name: 'glue-acp',
        title: 'Glue ACP Agent',
        version: AppConstants.version,
      ),
      agentCapabilities: AgentCapabilities(
        sessionCapabilities: SessionCapabilities(list: <String, dynamic>{}),
      ),
    );
  }

  @override
  Future<ListSessionsResponse> listSessions(
    ListSessionsRequest request, {
    required AcpCancellationToken cancelToken,
  }) async {
    final sessions = _sessions.values
        .where((session) => request.cwd == null || session.cwd == request.cwd)
        .map((session) => session.toSessionInfo())
        .toList();
    return ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<NewSessionResponse> newSession(
    NewSessionRequest request, {
    required AcpCancellationToken cancelToken,
  }) async {
    final sessionId = 'glue-session-${++_sessionCounter}';
    final systemPrompt = Prompts.build(
      cwd: request.cwd,
      skills: _skillRuntime.list(),
    );
    final llm = _llmFactory.createFromConfig(systemPrompt: systemPrompt);
    final agent = AgentCore(
      llm: llm,
      tools: _tools,
      modelId: _modelId,
    );
    _sessions[sessionId] = AcpSession(
      id: sessionId,
      cwd: request.cwd,
      agent: agent,
      title: 'Glue session',
    );
    return NewSessionResponse(sessionId: sessionId);
  }

  @override
  Future<PromptResponse> prompt(
    PromptRequest request, {
    required AcpCancellationToken cancelToken,
  }) async {
    final session = _sessions[request.sessionId];
    if (session == null) {
      throw RpcErrorException.invalidParams('Unknown session: ${request.sessionId}');
    }

    final promptText = _promptToText(request.prompt);
    if (promptText.trim().isEmpty) {
      return const PromptResponse(stopReason: StopReason.endTurn);
    }

    session.updatedAt = DateTime.now().toUtc();

    try {
      await for (final event in session.agent.run(promptText)) {
        cancelToken.throwIfCanceled();

        switch (event) {
          case AgentTextDelta(:final delta):
            await _connection.notifySessionUpdate(
              request.sessionId,
              AgentMessageChunk(content: TextContent(text: delta)),
            );

          case AgentToolCallPending(:final id, :final name):
            await _connection.notifySessionUpdate(
              request.sessionId,
              ToolCallSessionUpdate(
                title: name,
                toolCallId: id,
                kind: _mapToolKind(name),
                status: 'pending',
              ),
            );

          case AgentToolCall(:final call):
            await _connection.notifySessionUpdate(
              request.sessionId,
              ToolCallDeltaSessionUpdate(
                toolCallId: call.id,
                status: 'in_progress',
                title: call.name,
                kind: _mapToolKind(call.name),
                rawInput: call.arguments,
              ),
            );

            final allowed = await _requestToolPermission(
              request.sessionId,
              call,
              cancelToken: cancelToken,
            );
            final result = allowed
                ? await session.agent.executeTool(call)
                : ToolResult.denied(call.id);
            session.agent.completeToolCall(result);

            await _connection.notifySessionUpdate(
              request.sessionId,
              ToolCallDeltaSessionUpdate(
                toolCallId: call.id,
                status: result.success ? 'completed' : 'failed',
                content: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'text',
                    'text': result.summary ?? result.content,
                  },
                ],
                rawOutput: <String, dynamic>{
                  'success': result.success,
                  'metadata': result.metadata,
                },
              ),
            );

          case AgentToolResult():
            break;
          case AgentDone():
            break;
          case AgentError(:final error):
            throw RpcErrorException.internalError('Glue agent error: $error');
        }
      }
    } on CanceledException {
      session.agent.ensureToolResultsComplete();
      return const PromptResponse(stopReason: StopReason.cancelled);
    }

    session.updatedAt = DateTime.now().toUtc();
    return const PromptResponse(stopReason: StopReason.endTurn);
  }

  @override
  Future<void> cancel(CancelNotification notification) async {
    final session = _sessions[notification.sessionId];
    session?.agent.ensureToolResultsComplete();
  }

  Future<bool> _requestToolPermission(
    String sessionId,
    ToolCall call, {
    required AcpCancellationToken cancelToken,
  }) async {
    if (!_requiresApproval(call.name)) return true;

    final response = await _connection.sendRequestPermission(
      sessionId: sessionId,
      toolCall: <String, dynamic>{
        'title': 'Approve ${call.name}',
        'kind': _mapToolKind(call.name),
        'rawInput': call.arguments,
      },
      options: const <Map<String, dynamic>>[
        <String, dynamic>{
          'optionId': 'allow_once',
          'name': 'Allow once',
          'kind': 'allow_once',
        },
        <String, dynamic>{
          'optionId': 'reject_once',
          'name': 'Reject',
          'kind': 'reject_once',
        },
      ],
      cancelToken: cancelToken,
    );

    final outcome = response.outcome;
    return outcome['outcome'] == 'selected' &&
        outcome['optionId'] == 'allow_once';
  }

  bool _requiresApproval(String toolName) {
    return switch (toolName) {
      'write_file' || 'edit_file' || 'bash' => true,
      _ => false,
    };
  }

  String _mapToolKind(String toolName) {
    return switch (toolName) {
      'read_file' || 'list_directory' => 'read',
      'write_file' || 'edit_file' => 'edit',
      'bash' => 'execute',
      'grep' => 'search',
      _ => 'other',
    };
  }

  String _promptToText(List<ContentBlock> prompt) {
    final lines = <String>[];
    for (final block in prompt) {
      switch (block) {
        case TextContent(:final text):
          lines.add(text);
        default:
          lines.add(jsonEncode(block.toJson()));
      }
    }
    return lines.join('\n');
  }
}
