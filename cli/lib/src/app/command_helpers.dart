part of 'package:glue/src/app.dart';

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
      '  Mode:         ${app._interactionMode.label} (Shift+Tab to cycle)');
  buf.writeln('  Approval:     ${app._approvalMode.label}');
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

String _resumeSessionFromCommandImpl(App app, String query) {
  final normalized = query.trim();
  if (normalized.isEmpty) return 'Usage: /resume [session-id-or-query]';

  final sessions = app._sessionManager.listSessions();
  if (sessions.isEmpty) return 'No saved sessions found.';

  final exactId = sessions.where((s) => s.id == normalized).toList();
  if (exactId.length == 1) {
    return app._resumeSession(exactId.first);
  }

  final needle = normalized.toLowerCase();
  final matches = sessions.where((s) {
    final title = (s.title ?? '').toLowerCase();
    final cwd = s.cwd.toLowerCase();
    return s.id.toLowerCase().contains(needle) ||
        title.contains(needle) ||
        cwd.contains(needle);
  }).toList();

  if (matches.isEmpty) {
    final recent = sessions.take(5).map((s) => s.id).join(', ');
    return 'No session matches "$normalized". '
        'Try a session ID from: ${recent.isEmpty ? "(none)" : recent}';
  }

  if (matches.length > 1) {
    final preview = matches.take(5).map((s) {
      final title = (s.title ?? '').trim();
      return title.isEmpty ? '  - ${s.id}' : '  - ${s.id} ($title)';
    }).join('\n');
    return 'Multiple sessions match "$normalized":\n'
        '$preview\n'
        'Use a more specific session ID.';
  }

  return app._resumeSession(matches.first);
}

String _historyFromCommandImpl(App app, String query) {
  final normalized = query.trim();
  if (normalized.isEmpty) return 'Usage: /history [index-or-query]';

  final entries = <HistoryPanelEntry>[];
  var userIndex = 0;
  for (final block in app._blocks) {
    if (block.kind == _EntryKind.user) {
      entries.add(HistoryPanelEntry(
        userMessageIndex: userIndex,
        text: block.text,
      ));
      userIndex++;
    }
  }

  if (entries.isEmpty) return 'No conversation history.';

  final numeric = int.tryParse(normalized);
  if (numeric != null) {
    final position = numeric - 1; // UI is 1-based.
    if (position < 0 || position >= entries.length) {
      return 'History index out of range: $numeric (1-${entries.length}).';
    }
    final entry = entries[position];
    app._forkSession(entry.userMessageIndex, entry.text);
    return '';
  }

  final needle = normalized.toLowerCase();
  final matches = entries.where((entry) {
    return entry.text.toLowerCase().contains(needle);
  }).toList();

  if (matches.isEmpty) {
    final preview = entries.take(5).toList();
    final lines = preview.asMap().entries.map((e) {
      final idx = e.key + 1;
      final compact = e.value.text.replaceAll('\n', ' ').trim();
      final short =
          compact.length > 56 ? '${compact.substring(0, 56)}…' : compact;
      return '  #$idx $short';
    }).join('\n');
    return 'No history entry matches "$normalized".\n'
        'Recent entries:\n'
        '${lines.isEmpty ? "  (none)" : lines}';
  }

  if (matches.length > 1) {
    final preview = matches.take(5).map((entry) {
      final idx = entries.indexOf(entry) + 1;
      final compact = entry.text.replaceAll('\n', ' ').trim();
      final short =
          compact.length > 56 ? '${compact.substring(0, 56)}…' : compact;
      return '  #$idx $short';
    }).join('\n');
    return 'Multiple history entries match "$normalized":\n'
        '$preview\n'
        'Use /history <index> for an exact fork point.';
  }

  final entry = matches.first;
  app._forkSession(entry.userMessageIndex, entry.text);
  return '';
}

String _openPlanFromCommandImpl(App app, String query) {
  final normalized = query.trim();
  if (normalized.isEmpty) return 'Usage: /plans [name-or-path]';

  final plans = app._planStore.listPlans();
  if (plans.isEmpty) {
    return 'No plans found in workspace or ~/.glue/plans.';
  }

  final needle = normalized.toLowerCase();
  final exact = plans.where((p) {
    return p.title.toLowerCase() == needle || p.path.toLowerCase() == needle;
  }).toList();

  final matches = exact.isNotEmpty
      ? exact
      : plans.where((p) {
          return p.title.toLowerCase().contains(needle) ||
              p.path.toLowerCase().contains(needle);
        }).toList();

  if (matches.isEmpty) {
    final preview = plans
        .take(5)
        .map((p) => '  - ${p.title} (${app._shortenPath(p.path)})')
        .join('\n');
    return 'No plan matches "$normalized".\n'
        'Recent plans:\n'
        '${preview.isEmpty ? "  (none)" : preview}';
  }

  if (matches.length > 1) {
    final preview = matches
        .take(5)
        .map((p) => '  - ${p.title} (${app._shortenPath(p.path)})')
        .join('\n');
    return 'Multiple plans match "$normalized":\n'
        '$preview\n'
        'Use a more specific title or path.';
  }

  app._openPlanViewer(matches.first);
  return '';
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
