import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/tools.dart';

/// Minimal LLM that returns text only (no tool calls).
class _TextOnlyLlm implements LlmClient {
  final String response;
  _TextOnlyLlm(this.response);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    for (final word in response.split(' ')) {
      yield TextDelta('$word ');
    }
    yield UsageInfo(inputTokens: 10, outputTokens: 5);
  }
}

/// LLM that makes one tool call then responds.
class _ToolCallLlm implements LlmClient {
  int _callCount = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _callCount++;
    if (_callCount == 1) {
      yield TextDelta('Let me check. ');
      yield ToolCallDelta(ToolCall(
        id: 'tc1',
        name: 'list_directory',
        arguments: {'path': '.'},
      ));
      yield UsageInfo(inputTokens: 10, outputTokens: 10);
    } else {
      yield TextDelta('Found the files.');
      yield UsageInfo(inputTokens: 20, outputTokens: 10);
    }
  }
}

void main() {
  group('AgentRunner', () {
    test('runs text-only response to completion', () async {
      final core = AgentCore(
        llm: _TextOnlyLlm('Hello from the agent'),
        tools: {},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('Hi');
      expect(result, contains('Hello'));
    });

    test('auto-approves tool calls in headless mode', () async {
      final core = AgentCore(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('List files');
      expect(result, contains('Found the files'));
    });

    test('denies tool calls in denyAll mode', () async {
      final core = AgentCore(
        llm: _ToolCallLlm(),
        tools: {'list_directory': ListDirectoryTool()},
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.denyAll,
      );
      final result = await runner.runToCompletion('List files');
      // After denial, the LLM gets another turn and responds
      expect(result, contains('Found the files'));
    });
  });
}
