part of 'package:glue/src/app.dart';

String _statusModelLabel(App app) => formatStatusModelLabel(
      app._config?.activeModel,
      app._config?.catalogData,
      app._modelId,
    );

void _addSystemMessageImpl(App app, String message) {
  app._transcript.blocks.add(ConversationEntry.system(message));
}

Future<void> _activateSkillFromUiImpl(App app, String skillName) async {
  try {
    final activation = await activateSkillIntoConversation(
      agent: app.agent,
      skillName: skillName,
    );

    app._sessionService.ensureStore();
    app._sessionService.logEvent('tool_call', {
      'name': 'skill',
      'arguments': {'name': skillName},
    });
    app._sessionService.logEvent('tool_result', {
      'name': 'skill',
      'content': activation.content,
    });

    app._transcript.blocks
        .add(ConversationEntry.toolCall('skill', {'name': skillName}));
    app._transcript.blocks
        .add(ConversationEntry.toolResult(activation.content));
  } on SkillActivationError catch (e) {
    app._transcript.blocks.add(ConversationEntry.system(e.message));
  } catch (e) {
    app._transcript.blocks.add(
        ConversationEntry.system('Error activating skill "$skillName": $e'));
  }
}
