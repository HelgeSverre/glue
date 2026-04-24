part of 'package:glue/src/app.dart';

String _statusModelLabel(App app) => formatStatusModelLabel(
      app._config?.activeModel,
      app._config?.catalogData,
      app._modelId,
    );

void _addSystemMessageImpl(App app, String message) {
  app._transcript.blocks.add(ConversationEntry.system(message));
}

String _timeAgoImpl(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return time.toIso8601String().substring(0, 10);
}

void _forkSessionImpl(App app, int userMessageIndex, String messageText) {
  final result = app._sessionManager.forkSession(
    userMessageIndex: userMessageIndex,
    messageText: messageText,
    agent: app.agent,
  );
  if (result == null) return;

  app._transcript.blocks.clear();
  app._transcript.blocks.add(ConversationEntry.system(result.message));
  app._appendSessionReplayEntries(result.replay.entries);
  app.editor.setText(result.draftText);
  app._render();
}

Future<void> _activateSkillFromUiImpl(App app, String skillName) async {
  try {
    final activation = await activateSkillIntoConversation(
      agent: app.agent,
      skillName: skillName,
    );

    app._ensureSessionStore();
    app._sessionManager.logEvent('tool_call', {
      'name': 'skill',
      'arguments': {'name': skillName},
    });
    app._sessionManager.logEvent('tool_result', {
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
