import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart' show Tool;
import 'package:glue/src/skills/skill_activation.dart';
import 'package:glue/src/skills/skill_runtime.dart';
import 'package:glue/src/skills/skill_tool.dart';

class _NoopLlm extends LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) =>
      const Stream<LlmChunk>.empty();
}

void main() {
  group('/skills activation integration', () {
    late Directory tempDir;
    late AgentCore agent;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('skills_activation_test_');
      final skillsDir = p.join(tempDir.path, '.glue', 'skills', 'code-review');
      Directory(skillsDir).createSync(recursive: true);
      File(p.join(skillsDir, 'SKILL.md')).writeAsStringSync(
        '---\nname: code-review\ndescription: Review code changes.\n---\n\n'
        '# Workflow\n\nCheck diff first.\n',
      );

      final runtime = SkillRuntime(
        cwd: tempDir.path,
        home: tempDir.path,
        extraPathsProvider: () => const [],
      );
      agent = AgentCore(llm: _NoopLlm(), tools: {'skill': SkillTool(runtime)});
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('injects tool_call + tool_result into agent conversation', () async {
      final activation = await activateSkillIntoConversation(
        agent: agent,
        skillName: 'code-review',
      );

      expect(activation.content, contains('# Skill: code-review'));
      expect(agent.conversation, hasLength(2));

      final assistant = agent.conversation[0];
      expect(assistant.role, Role.assistant);
      expect(assistant.toolCalls, hasLength(1));
      expect(assistant.toolCalls.first.id, activation.callId);
      expect(assistant.toolCalls.first.name, 'skill');
      expect(assistant.toolCalls.first.arguments, {'name': 'code-review'});

      final toolResult = agent.conversation[1];
      expect(toolResult.role, Role.toolResult);
      expect(toolResult.toolCallId, activation.callId);
      expect(toolResult.toolName, 'skill');
      expect(toolResult.text, contains('Check diff first.'));
    });

    test('fails cleanly for unknown skill without mutating conversation',
        () async {
      await expectLater(
        () => activateSkillIntoConversation(
          agent: agent,
          skillName: 'does-not-exist',
        ),
        throwsA(isA<SkillActivationError>()),
      );
      expect(agent.conversation, isEmpty);
    });
  });
}
