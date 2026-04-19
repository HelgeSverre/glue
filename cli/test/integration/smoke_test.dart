import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/agent_runner.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

/// Fake LLM that exercises the full stack without network calls.
class _MockLlm implements LlmClient {
  int _calls = 0;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _calls++;
    final last = messages.lastWhere((m) => m.role == Role.user);
    final text = last.text ?? '';

    if (_calls == 1 && text.contains('read')) {
      yield TextDelta('I\'ll read that file. ');
      yield ToolCallComplete(
        ToolCall(
          id: 'tc_$_calls',
          name: 'read_file',
          arguments: {'path': 'pubspec.yaml'},
        ),
      );
      yield UsageInfo(inputTokens: 20, outputTokens: 10);
    } else {
      yield TextDelta('Done with the task.');
      yield UsageInfo(inputTokens: 10, outputTokens: 5);
    }
  }
}

class _MockFactory implements LlmClientFactory {
  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) =>
      _MockLlm();

  @override
  LlmClient createFromConfig({required String systemPrompt}) => _MockLlm();
}

void main() {
  group('End-to-end smoke', () {
    test('AgentRunner completes a tool-using conversation', () async {
      final core = AgentCore(
        llm: _MockLlm(),
        tools: {'read_file': ReadFileTool()},
        modelId: 'test-model',
      );
      final runner = AgentRunner(
        core: core,
        policy: ToolApprovalPolicy.autoApproveAll,
      );
      final result = await runner.runToCompletion('Please read pubspec.yaml');
      expect(result, contains('Done with the task'));
      expect(core.tokenCount, greaterThan(0));
    });

    test('AgentManager spawns parallel subagents', () async {
      final manager = AgentManager(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _MockFactory(),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'test',
      );

      final results = await manager.spawnParallel(
        tasks: ['Task 1', 'Task 2', 'Task 3'],
      );
      expect(results, hasLength(3));
      for (final r in results) {
        expect(r, contains('Done'));
      }
    });
  });
}
