part of 'package:glue/src/app.dart';

Future<void> _runPrintModeImpl(App app) async {
  // Optionally resume a previous session into the agent conversation.
  if (app._resumeSessionId != null) {
    if (app._resumeSessionId.isEmpty) {
      stderr.writeln(
          'Error: --print does not support bare --resume; pass a session ID.');
      return;
    }
    final sessions = app._sessionManager.listSessions();
    final match =
        sessions.where((s) => s.id.value == app._resumeSessionId).toList();
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
  final turnSpan = app._obs?.startSpan(
    'agent.turn',
    kind: 'agent',
    attributes: {
      'openinference.span.kind': 'AGENT',
      'session.id': app._sessionManager.currentSessionId ?? '',
      'llm.model_name': app._modelId,
      'process.command': 'print',
      'user.message_length': expanded.length,
      'input.value': redactBody(expanded),
    },
  );
  if (turnSpan != null) app._obs!.activeSpan = turnSpan;

  // Two-press SIGINT: first press cancels the in-flight agent stream so we
  // can emit a clean JSON envelope (or a [cancelled] marker) and exit 130;
  // a second press during teardown hard-exits with 130. See
  // docs/reference/sigint-handling.md for the design.
  var cancelled = false;
  var sigintCount = 0;
  StreamSubscription<AgentEvent>? agentSub;
  StreamSubscription<ProcessSignal>? sigintSub;
  final loopDone = Completer<void>();
  Object? loopError;

  sigintSub = ProcessSignal.sigint.watch().listen((_) {
    sigintCount++;
    if (sigintCount == 1) {
      stderr.writeln('\nCancelling… press Ctrl+C again to force quit.');
      cancelled = true;
      agentSub?.cancel();
      if (!loopDone.isCompleted) loopDone.complete();
    } else {
      sigintSub?.cancel();
      exit(130);
    }
  });

  try {
    agentSub = app.agent.run(expanded).listen(
      (event) async {
        if (cancelled) return;
        switch (event) {
          case AgentTextDelta(:final delta):
            assistantText.write(delta);
            if (!app._jsonMode) stdout.write(delta);

          case AgentUsage(:final usage):
            // Print mode also persists, so attribute the usage.
            app._sessionManager.recordUsage(
              UsageStats()..record(usage),
              role: 'main',
            );

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
            if (turnSpan != null && turnSpan.endTime == null) {
              app._obs!.endSpan(turnSpan, extra: {
                'error': true,
                'error.type': error.runtimeType.toString(),
                'error.message': error.toString(),
              });
            }
            stderr.writeln(error);
            if (!loopDone.isCompleted) loopDone.complete();

          default:
            break;
        }
      },
      onError: (Object e) {
        loopError = e;
        if (!loopDone.isCompleted) loopDone.complete();
      },
      onDone: () {
        if (!loopDone.isCompleted) loopDone.complete();
      },
    );

    await loopDone.future;
    if (loopError != null) throw loopError!;
  } catch (e) {
    if (turnSpan != null) {
      app._obs!.endSpan(turnSpan, extra: {
        'error': true,
        'error.type': e.runtimeType.toString(),
        'error.message': e.toString(),
      });
    }
    stderr.writeln('Error: $e');
    return;
  } finally {
    await agentSub?.cancel();
    await sigintSub.cancel();
    if (turnSpan != null) {
      final obs = app._obs!;
      if (turnSpan.endTime == null) {
        obs.endSpan(turnSpan, extra: {
          'output.value': redactBody(assistantText.toString()),
          'output.length': assistantText.length,
          if (cancelled) 'cancelled': true,
        });
      }
      if (obs.activeSpan == turnSpan) obs.activeSpan = null;
    }
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
      if (cancelled) 'cancelled': true,
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  }

  if (cancelled) exitCode = 130;
}

String _resumeSessionImpl(App app, SessionMeta session) {
  final result =
      app._sessionManager.resumeSession(session: session, agent: app.agent);
  app._blocks.clear();
  app._toolUi.clear();
  app._streamingText = '';
  app._streamingThinking = '';
  app._subagentGroups.clear();
  app._outputLineGroups.clear();
  app._titleInitialRequested = session.title != null;
  app._titleReevaluationRequested =
      session.titleState == SessionTitleState.stable ||
          (session.titleGenerationCount >= 2);
  app._titleManuallyOverridden = session.titleSource == SessionTitleSource.user;

  app._blocks.add(_ConversationEntry.system(
    'Resuming session ${session.id} '
    '(${session.modelRef}, ${App._timeAgo(session.startTime)})',
  ));

  if (!result.hasConversation) {
    return 'Session ${session.id} has no conversation data.';
  }

  // Show a one-line token-usage summary for this session so resume
  // surfaces cost continuity instead of pretending the counter restarts
  // at zero. Skipped on Ollama / pre-recordUsage sessions where no
  // usage rows were ever persisted.
  final usage = result.replay.totalUsage;
  if (usage.totalCalls > 0) {
    final summary =
        StringBuffer('Carry-over: ${_formatTokens(usage.totalTokens)} tokens '
            'over ${usage.totalCalls} call${usage.totalCalls == 1 ? '' : 's'}');
    final hit = usage.cacheHitRate;
    if (hit != null &&
        (usage.totalCacheRead > 0 || usage.totalCacheWrite > 0)) {
      summary.write(' · ${(hit * 100).toStringAsFixed(0)}% cached');
    }
    summary.write('. Run /usage for the per-role breakdown.');
    app._blocks.add(_ConversationEntry.system(summary.toString()));
  }

  app._appendSessionReplayEntries(result.replay.entries);

  // Backfill title for resumed sessions that lack one.
  final firstUserMessage = result.replay.firstUserMessage;
  if (!app._titleInitialRequested &&
      !app._titleManuallyOverridden &&
      firstUserMessage != null &&
      firstUserMessage.isNotEmpty) {
    app._titleInitialRequested = true;
    app._generateTitle(firstUserMessage);
  }

  return result.message;
}

void _generateTitleImpl(App app, String userMessage) {
  final llmClient = app._createTitleLlmClient();
  if (llmClient == null) return;

  final generator = TitleGenerator(
    llmClient: llmClient,
    onUsage: (usage) => app._sessionManager.recordUsage(
      UsageStats()..record(usage),
      role: 'title',
    ),
  );
  unawaited(app._sessionManager.generateTitle(
    userMessage: userMessage,
    generate: generator.generate,
  ));
}

void _reevaluateTitleImpl(App app) {
  if (app._titleReevaluationRequested || app._titleManuallyOverridden) return;
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
  app._titleReevaluationRequested = true;
  final generator = TitleGenerator(
    llmClient: llmClient,
    onUsage: (usage) => app._sessionManager.recordUsage(
      UsageStats()..record(usage),
      role: 'title',
    ),
  );
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
  // Subagent groups are reconstructed on the fly: spawn opens a group keyed
  // by subagent_id; subsequent events append to that group; completion just
  // marks it done. Activity that arrives without a matching open group is
  // skipped to avoid silent shape drift.
  final openGroups = <String, _SubagentGroup>{};

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

      case SessionReplayKind.subagentSpawned:
        final id = entry.subagentId!;
        final group = _SubagentGroup(
          task: entry.text,
          index: entry.subagentIndex,
          total: entry.subagentTotal,
        );
        openGroups[id] = group;
        app._subagentGroups['${entry.text}:${entry.subagentIndex ?? 0}'] =
            group;
        app._blocks.add(_ConversationEntry.subagentGroup(group));

      case SessionReplayKind.subagentEvent:
        final id = entry.subagentId;
        final group = id == null ? null : openGroups[id];
        if (group == null) continue;
        final inner = entry.subagentInner;
        if (inner == null) continue;
        final prefix = group.index != null
            ? '↳ [${group.index! + 1}/${group.total}]'
            : '↳';
        switch (inner.kind) {
          case SessionReplayKind.toolCall:
            final argsPreview =
                (inner.toolArguments ?? const <String, dynamic>{})
                    .entries
                    .take(2)
                    .map((e) => '${e.key}: ${e.value}')
                    .join(', ');
            group.entries.add(_SubagentEntry(
              '$prefix ▶ ${inner.toolName ?? inner.text}  $argsPreview',
            ));
          case SessionReplayKind.toolResult:
            final display = inner.text.length > 80
                ? '${inner.text.substring(0, 80)}…'
                : inner.text;
            group.entries.add(_SubagentEntry(
              '$prefix ✓ ${display.replaceAll('\n', ' ')}',
              rawContent: inner.text.length > 80 ? inner.text : null,
            ));
          default:
            // Assistant text and other inner kinds render as plain lines.
            final display = inner.text.length > 80
                ? '${inner.text.substring(0, 80)}…'
                : inner.text;
            group.entries.add(
                _SubagentEntry('$prefix · ${display.replaceAll('\n', ' ')}'));
        }

      case SessionReplayKind.subagentCompleted:
        final id = entry.subagentId;
        final group = id == null ? null : openGroups.remove(id);
        if (group == null) continue;
        group.done = true;
        if (entry.subagentError != null) {
          final prefix = group.index != null
              ? '↳ [${group.index! + 1}/${group.total}]'
              : '↳';
          group.entries
              .add(_SubagentEntry('$prefix ✗ Error: ${entry.subagentError}'));
        }
    }
  }
}
