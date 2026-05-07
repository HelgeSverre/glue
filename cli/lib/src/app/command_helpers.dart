part of 'package:glue/src/app.dart';

String _statusModelLabel(App app) => formatStatusModelLabel(
      app._config?.activeModel,
      app._config?.catalogData,
      app._modelId,
    );

void _addSystemMessageImpl(App app, String message) {
  app._blocks.add(ConversationEntry.system(message));
}

void _forkSessionImpl(App app, int userMessageIndex, String messageText) {
  final result = app._sessionManager.forkSession(
    userMessageIndex: userMessageIndex,
    messageText: messageText,
    agent: app.agent,
  );
  if (result == null) return;

  app._blocks.clear();
  app._blocks.add(ConversationEntry.system(result.message));
  app._appendSessionReplayEntries(result.replay.entries);
  app.editor.setText(result.draftText);
  app._render();
}

