import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';

class SkillActivationError implements Exception {
  final String message;
  SkillActivationError(this.message);

  @override
  String toString() => message;
}

class SkillActivationResult {
  final String callId;
  final String content;
  final String skillName;

  SkillActivationResult({
    required this.callId,
    required this.content,
    required this.skillName,
  });
}

/// Activates a skill through the `skill` tool and injects the resulting
/// tool_call + tool_result messages into the agent conversation.
Future<SkillActivationResult> activateSkillIntoConversation({
  required AgentCore agent,
  required String skillName,
  String callIdPrefix = 'manual-skill',
}) async {
  final tool = agent.tools['skill'];
  if (tool == null) {
    throw SkillActivationError('Error: skill tool is unavailable.');
  }

  final parts = await tool.execute({'name': skillName});
  final content = ContentPart.textOnly(parts);
  if (content.startsWith('Error')) {
    throw SkillActivationError(content);
  }

  final callId = '$callIdPrefix-${DateTime.now().microsecondsSinceEpoch}';
  final call = ToolCall(
    id: callId,
    name: 'skill',
    arguments: {'name': skillName},
  );

  // Inject synthetic tool_call + tool_result so the next model turn sees
  // activated skill content as normal tool result context.
  agent.addMessage(Message.assistant(toolCalls: [call]));
  agent.addMessage(Message.toolResult(
    callId: callId,
    content: content,
    toolName: 'skill',
  ));

  return SkillActivationResult(
    callId: callId,
    content: content,
    skillName: skillName,
  );
}
