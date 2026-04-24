part of 'package:glue/src/app.dart';

String _resumeSessionImpl(App app, SessionMeta session) {
  final result =
      app._sessionManager.resumeSession(session: session, agent: app.agent);
  app._transcript.blocks.clear();
  app._transcript.toolUi.clear();
  app._transcript.streamingText = '';
  app._transcript.subagentGroups.clear();
  app._transcript.outputLineGroups.clear();
  app._titleState.applyResumedSession(session);

  app._transcript.blocks.add(ConversationEntry.system(
    'Resuming session ${session.id} '
    '(${session.modelRef}, ${App._timeAgo(session.startTime)})',
  ));

  if (!result.hasConversation) {
    return 'Session ${session.id} has no conversation data.';
  }

  app._appendSessionReplayEntries(result.replay.entries);

  // Backfill title for resumed sessions that lack one.
  final firstUserMessage = result.replay.firstUserMessage;
  if (app._titleState.shouldGenerateInitialTitle &&
      firstUserMessage != null &&
      firstUserMessage.isNotEmpty) {
    app._titleState.markInitialRequested();
    app._generateTitle(firstUserMessage);
  }

  return result.message;
}

void _generateTitleImpl(App app, String userMessage) {
  final llmClient = app._createTitleLlmClient();
  if (llmClient == null) return;

  final generator = TitleGenerator(llmClient: llmClient);
  unawaited(app._sessionManager.generateTitle(
    userMessage: userMessage,
    generate: generator.generate,
  ));
}

void _reevaluateTitleImpl(App app) {
  if (app._titleState.blocksReevaluation) return;
  final store = app._sessionManager.currentStore;
  final meta = store?.meta;
  if (meta == null ||
      meta.titleSource != SessionTitleSource.auto ||
      meta.titleState != SessionTitleState.provisional ||
      meta.titleGenerationCount >= 2) {
    return;
  }

  String? firstUserMessage;
  String? latestUserMessage;
  String? firstAssistantMessage;
  String? latestAssistantMessage;
  final toolNames = <String>[];
  for (final message in app.agent.conversation) {
    switch (message.role) {
      case Role.user:
        final text = message.text;
        if (text == null || text.isEmpty) continue;
        firstUserMessage ??= text;
        latestUserMessage = text;
      case Role.assistant:
        final text = message.text;
        if (text != null && text.isNotEmpty) {
          firstAssistantMessage ??= text;
          latestAssistantMessage = text;
        }
        for (final toolCall in message.toolCalls) {
          toolNames.add(toolCall.name);
        }
      case Role.toolResult:
        break;
    }
  }

  final hasEnoughContext = (firstAssistantMessage != null &&
          firstAssistantMessage.trim().length >= 40) ||
      toolNames.isNotEmpty ||
      firstUserMessage != null &&
          latestUserMessage != null &&
          firstUserMessage != latestUserMessage;
  if (!hasEnoughContext) return;

  final llmClient = app._createTitleLlmClient();
  if (llmClient == null) return;
  app._titleState.markReevaluationRequested();
  final generator = TitleGenerator(llmClient: llmClient);
  unawaited(app._sessionManager.reevaluateTitle(
    context: TitleContext(
      firstUserMessage: firstUserMessage,
      latestUserMessage: latestUserMessage,
      firstAssistantMessage: firstAssistantMessage,
      latestAssistantMessage: latestAssistantMessage,
      toolNames: toolNames,
      cwdBasename: app._cwd.split(Platform.pathSeparator).last,
    ),
    generate: generator.generateFromContext,
  ));
}

LlmClient? _createTitleLlmClientImpl(App app) {
  final config = app._config;
  final factory = app._llmFactory;
  if (config == null || factory == null) return null;

  if (!config.titleGenerationEnabled) {
    if (config.observability.debug) {
      stderr.writeln('[debug] title generation disabled; skipping');
    }
    return null;
  }

  final target = app._resolveTitleTarget(config);
  try {
    return factory.createFor(
      target.ref,
      systemPrompt: TitleGenerator.systemPrompt,
    );
  } on ConfigError {
    // No adapter or missing credentials for the small model — skip titling.
    return null;
  }
}

_TitleTarget _resolveTitleTargetImpl(GlueConfig config) {
  return _TitleTarget(ref: config.smallModel ?? config.activeModel);
}

void _ensureSessionStoreImpl(App app) {
  final config = app._config;
  app._sessionManager.ensureSessionStore(
    cwd: app._cwd,
    modelRef: config?.activeModel.toString() ?? app._modelId,
  );
}

void _appendSessionReplayEntriesImpl(
  App app,
  List<SessionReplayEntry> entries,
) {
  for (final entry in entries) {
    switch (entry.kind) {
      case SessionReplayKind.user:
        app._transcript.blocks.add(ConversationEntry.user(entry.text));
      case SessionReplayKind.assistant:
        app._transcript.blocks.add(ConversationEntry.assistant(entry.text));
      case SessionReplayKind.toolCall:
        app._transcript.blocks.add(ConversationEntry.toolCall(
          entry.toolName ?? entry.text,
          entry.toolArguments ?? const <String, dynamic>{},
        ));
      case SessionReplayKind.toolResult:
        app._transcript.blocks.add(ConversationEntry.toolResult(entry.text));
    }
  }
}
