part of 'app.dart';

String _clearConversationImpl(App app) {
  app._blocks.clear();
  app._scrollOffset = 0;
  app._streamingText = '';
  app.terminal.clearScreen();
  app.layout.apply();
  return 'Cleared.';
}

String _switchModelByQueryImpl(App app, String query) {
  final entry = ModelRegistry.findByName(query);
  if (entry == null) {
    final suggestions = ModelRegistry.models.map((m) => m.modelId).join(', ');
    return 'Unknown model: $query\nAvailable: $suggestions';
  }
  return app._switchToModelEntry(entry);
}

String _buildSessionInfoImpl(App app) {
  final shortCwd = app._shortenPath(app._cwd);
  final trustedList = app._autoApprovedTools.toList()..sort();
  final entry = ModelRegistry.findById(app._modelId);
  final displayModel =
      entry != null ? '${entry.displayName} (${entry.modelId})' : app._modelId;
  final buf = StringBuffer();
  buf.writeln('Session Info');
  buf.writeln('  Model:        $displayModel');
  buf.writeln('  Provider:     ${app._config?.provider.name ?? "unknown"}');
  buf.writeln('  Directory:    $shortCwd');
  buf.writeln('  Tokens used:  ${app.agent.tokenCount}');
  buf.writeln('  Messages:     ${app.agent.conversation.length}');
  buf.writeln('  Tools:        ${app.agent.tools.length} registered');
  buf.writeln(
      '  Permissions:  ${app._permissionMode.label} (Shift+Tab to cycle)');
  buf.writeln('  Auto-approve: ${trustedList.join(", ")}');
  return buf.toString();
}

String _buildToolsOutputImpl(App app) {
  final buf = StringBuffer('Available tools:\n');
  for (final tool in app.agent.tools.values) {
    buf.writeln('  ${tool.name} — ${tool.description}');
  }
  return buf.toString();
}

String _openDevToolsImpl(App app) {
  unawaited(GlueDev.getDevToolsUrl().then((url) {
    if (url == null) {
      app._blocks.add(_ConversationEntry.system(
          'DevTools not available. Run with: just dev'));
      app._render();
      return;
    }
    Process.run('open', [url.toString()]);
  }));
  return 'Opening DevTools...';
}

String _toggleDebugModeImpl(App app) {
  if (app._debugController != null) {
    app._debugController.toggle();
    return 'Debug mode: ${app._debugController.enabled}';
  }
  return 'Debug mode: unavailable';
}

void _addSystemMessageImpl(App app, String message) {
  app._blocks.add(_ConversationEntry.system(message));
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

  app._blocks.clear();
  app._blocks.add(_ConversationEntry.system(result.message));
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

    app._blocks.add(_ConversationEntry.toolCall('skill', {'name': skillName}));
    app._blocks.add(_ConversationEntry.toolResult(activation.content));
  } on SkillActivationError catch (e) {
    app._blocks.add(_ConversationEntry.system(e.message));
  } catch (e) {
    app._blocks.add(
        _ConversationEntry.system('Error activating skill "$skillName": $e'));
  }
}

String _switchToModelEntryImpl(App app, ModelEntry entry) {
  final factory = app._llmFactory;
  final config = app._config;
  final prompt = app._systemPrompt;
  if (factory != null && config != null && prompt != null) {
    final llm = factory.createFromEntry(entry, config, systemPrompt: prompt);
    app.agent.llm = llm;
    app._config = config.copyWith(
      provider: entry.provider,
      model: entry.modelId,
    );
  }
  app._modelId = entry.modelId;
  app._sessionManager.updateSessionModel(
    model: app._modelId,
    provider: app._config?.provider.name ?? entry.provider.name,
  );
  return 'Switched to ${entry.displayName}';
}
