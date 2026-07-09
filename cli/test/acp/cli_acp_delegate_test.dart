import 'dart:async';

import 'package:glue/src/acp/cli_acp_delegate.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

/// Minimal LLM stub: pops one queued list of chunks per [stream] call.
class _MockLlmClient extends LlmClient {
  final List<List<LlmChunk>> responses = [];

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    if (responses.isEmpty) return;
    for (final chunk in responses.removeAt(0)) {
      yield chunk;
    }
  }
}

/// A mutating tool so the [PermissionGate] returns `ask` in confirm mode.
class _MutatingTool extends Tool {
  @override
  String get name => 'danger';

  @override
  String get description => 'A mutating tool that needs confirmation';

  @override
  List<ToolParameter> get parameters => const [];

  @override
  ToolTrust get trust => ToolTrust.command;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'ran');
}

void main() {
  test(
    'permission-request error maps to a denial and unblocks the agent (H8)',
    () async {
      final call = ToolCall(
        id: const ToolCallId('tc-1'),
        name: 'danger',
        arguments: const {},
      );
      final tools = <String, Tool>{'danger': _MutatingTool()};
      final llm = _MockLlmClient()
        // First turn: the model asks to run the mutating tool.
        ..responses.add([ToolCallComplete(call)])
        // Second turn (after the denied result feeds back): plain text.
        ..responses.add([TextDelta('ok')]);
      final agent = AgentCore(llm: llm, tools: tools);
      final gate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp',
      );

      final delegate = CliAcpDelegate.forTest()
        ..debugInstallSession('s1', agent: agent, gate: gate);

      // requestPermission throws — mirrors the server error-completing the
      // pending permission when the client sends an error reply or drops.
      final events = await delegate
          .prompt(
            sessionId: 's1',
            userMessage: 'go',
            requestPermission: (_) async =>
                throw StateError('client error reply'),
          )
          .toList()
          .timeout(const Duration(seconds: 5));

      // The prompt completed (no hang) with a denied tool result, then the
      // agent's next turn produced text and finished.
      final results = events.whereType<AgentToolResult>().toList();
      expect(results, isNotEmpty);
      expect(
        results.every((r) => !r.result.success),
        isTrue,
        reason: 'the thrown permission request must resolve to a denial',
      );
      expect(
        events.whereType<AgentTextDelta>().map((e) => e.delta).join(),
        'ok',
      );
      expect(events.last, isA<AgentDone>());
    },
  );
}
