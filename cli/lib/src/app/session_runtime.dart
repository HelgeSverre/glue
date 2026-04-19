part of 'package:glue/src/app.dart';

Future<void> _runPrintModeImpl(App app) async {
  // Optionally resume a previous session into the agent conversation.
  if (app._resumeSessionId != null) {
    final sessions = app._sessionManager.listSessions();
    final match = sessions.where((s) => s.id == app._resumeSessionId).toList();
    if (match.isEmpty) {
      stderr.writeln('Session ${app._resumeSessionId} not found.');
      return;
    }
    app._sessionManager.resumeSession(session: match.first, agent: app.agent);
  }

  // Read piped stdin if available (e.g. `cat file | glue -p "summarize"`).
  String? stdinContent;
  if (!stdin.hasTerminal) {
    try {
      final buf = StringBuffer();
      String? line;
      while ((line = stdin.readLineSync()) != null) {
        buf.writeln(line);
      }
      final content = buf.toString().trimRight();
      if (content.isNotEmpty) stdinContent = content;
    } catch (_) {
      // Ignore stdin read errors.
    }
  }

  final prompt = app._startupPrompt;
  if ((prompt == null || prompt.isEmpty) && stdinContent == null) {
    stderr.writeln('Error: --print requires a prompt.');
    return;
  }

  final fullPrompt =
      App.buildPrintPrompt(prompt: prompt, stdinContent: stdinContent);
  final expanded = expandFileRefs(fullPrompt);

  app._sessionManager.logEvent('user_message', {'text': expanded});

  final assistantText = StringBuffer();
  final conversationLog = <Map<String, dynamic>>[];

  try {
    final stream = app.agent.run(expanded);
    await for (final event in stream) {
      switch (event) {
        case AgentTextDelta(:final delta):
          assistantText.write(delta);
          if (!app._jsonMode) stdout.write(delta);

        case AgentToolCall(:final call):
          conversationLog.add({
            'type': 'tool_call',
            'name': call.name,
            'arguments': call.arguments,
          });
          try {
            final result = await app.agent.executeTool(call);
            app.agent.completeToolCall(result);
          } catch (e) {
            app.agent.completeToolCall(ToolResult(
              callId: call.id,
              content: 'Tool error: $e',
              success: false,
            ));
          }

        case AgentDone():
          break;

        case AgentError(:final error):
          stderr.writeln(error);
          return;

        default:
          break;
      }
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    return;
  } finally {
    for (final tool in app.agent.tools.values) {
      try {
        await tool.dispose();
      } catch (_) {}
    }
    await app._obs?.flush();
    await app._obs?.close();
    await app._sessionManager.closeCurrent();
  }

  final text = assistantText.toString();
  if (!app._jsonMode && !text.endsWith('\n')) stdout.writeln();

  app._sessionManager.logEvent('assistant_message', {'text': text});

  if (app._jsonMode) {
    final sessionId = app._sessionManager.currentSessionId;
    conversationLog.insert(0, {'type': 'user_message', 'text': expanded});
    conversationLog.add({'type': 'assistant_message', 'text': text});

    final output = {
      'session_id': sessionId,
      'model': app._modelId,
      'conversation': conversationLog,
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  }
}

String _resumeSessionImpl(App app, SessionMeta session) {
  final result =
      app._sessionManager.resumeSession(session: session, agent: app.agent);
  app._blocks.clear();
  app._toolUi.clear();
  app._streamingText = '';
  app._subagentGroups.clear();
  app._outputLineGroups.clear();
  app._titleGenerated = session.title != null;

  app._blocks.add(_ConversationEntry.system(
    'Resuming session ${session.id} '
    '(${session.modelRef}, ${App._timeAgo(session.startTime)})',
  ));

  if (!result.hasConversation) {
    return 'Session ${session.id} has no conversation data.';
  }

  app._appendSessionReplayEntries(result.replay.entries);

  // Backfill title for resumed sessions that lack one.
  final firstUserMessage = result.replay.firstUserMessage;
  if (!app._titleGenerated &&
      firstUserMessage != null &&
      firstUserMessage.isNotEmpty) {
    app._titleGenerated = true;
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
        app._blocks.add(_ConversationEntry.user(entry.text));
      case SessionReplayKind.assistant:
        app._blocks.add(_ConversationEntry.assistant(entry.text));
      case SessionReplayKind.toolCall:
        app._blocks.add(_ConversationEntry.toolCall(
          entry.toolName ?? entry.text,
          entry.toolArguments ?? const <String, dynamic>{},
        ));
      case SessionReplayKind.toolResult:
        app._blocks.add(_ConversationEntry.toolResult(entry.text));
    }
  }
}
