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
  final config = app._config;
  if (config == null) return 'Config not ready.';
  final row = _findCatalogRow(config, query);
  if (row == null) {
    final available = config.catalogData.providers.values
        .expand((p) => p.models.values.map((m) => '${p.id}/${m.id}'))
        .take(12)
        .join(', ');
    return 'Unknown model: $query\nTry one of: $available …';
  }
  return app._switchToModelRow(row);
}

CatalogRow? _findCatalogRow(GlueConfig config, String query) {
  final parsed = ModelRef.tryParse(query);
  if (parsed != null) {
    final provider = config.catalogData.providers[parsed.providerId];
    final model = provider?.models[parsed.modelId];
    if (provider != null && model != null) {
      return (
        providerId: provider.id,
        providerName: provider.name,
        model: model,
      );
    }
  }
  final needle = query.toLowerCase();
  for (final p in config.catalogData.providers.values) {
    for (final m in p.models.values) {
      if (m.id.toLowerCase() == needle || m.name.toLowerCase() == needle) {
        return (providerId: p.id, providerName: p.name, model: m);
      }
    }
  }
  for (final p in config.catalogData.providers.values) {
    for (final m in p.models.values) {
      if (m.id.toLowerCase().contains(needle) ||
          m.name.toLowerCase().contains(needle)) {
        return (providerId: p.id, providerName: p.name, model: m);
      }
    }
  }
  return null;
}

String _buildSessionInfoImpl(App app) {
  final shortCwd = app._shortenPath(app._cwd);
  final trustedList = app._autoApprovedTools.toList()..sort();
  final ref = app._config?.activeModel;
  final providerDef =
      ref != null ? app._config?.catalogData.providers[ref.providerId] : null;
  final modelDef = providerDef?.models[ref?.modelId];
  final displayModel = modelDef != null
      ? '${modelDef.name} (${ref!})'
      : ref?.toString() ?? app._modelId;
  final buf = StringBuffer();
  buf.writeln('Session Info');
  buf.writeln('  Model:        $displayModel');
  buf.writeln('  Directory:    $shortCwd');
  buf.writeln('  Tokens used:  ${app.agent.tokenCount}');
  buf.writeln('  Messages:     ${app.agent.conversation.length}');
  buf.writeln('  Tools:        ${app.agent.tools.length} registered');
  buf.writeln(
    '  Approval:     ${app._approvalMode.label} (Shift+Tab to toggle)',
  );
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

String _runProviderCommandImpl(App app, List<String> args) {
  final config = app._config;
  if (config == null) return 'Config not ready.';

  final subcommand = args.isEmpty ? 'list' : args.first.toLowerCase();
  final rest = args.length > 1 ? args.sublist(1) : const <String>[];

  switch (subcommand) {
    case 'list':
    case 'ls':
      return _formatProviderList(config);
    case 'add':
      unawaited(
        app._panels.openProviderAdd(
          config: config,
          providerId: rest.isEmpty ? null : rest.first,
          addSystemMessage: app._addSystemMessage,
        ),
      );
      return '';
    case 'remove':
    case 'rm':
      if (rest.isEmpty) return 'Usage: /provider remove <id>';
      return _providerRemove(config, rest.first);
    case 'test':
      if (rest.isEmpty) return 'Usage: /provider test <id>';
      return _providerTest(config, rest.first);
    default:
      return 'Usage: /provider [list|add|remove|test] [<id>]';
  }
}

String _formatProviderList(GlueConfig config) {
  final providers = config.catalogData.providers.values
      .where((p) => p.enabled)
      .toList();
  if (providers.isEmpty) return 'No providers configured.';

  final buf = StringBuffer('Providers\n');
  for (final p in providers) {
    final status = _providerStatus(p, config);
    final source = _providerSource(p, config);
    buf.writeln('  ${p.id.padRight(12)}  ${status.padRight(12)}  $source');
  }
  return buf.toString();
}

String _providerStatus(ProviderDef p, GlueConfig config) {
  if (p.auth.kind == AuthKind.none) return 'no auth';
  final adapter = config.adapters.lookup(p.adapter);
  if (adapter != null && adapter.isConnected(p, config.credentials)) {
    return 'connected';
  }
  return 'missing';
}

String _providerSource(ProviderDef p, GlueConfig config) {
  return switch (p.auth.kind) {
    AuthKind.none => 'local',
    AuthKind.oauth => config.credentials.getField(p.id, 'github_token') != null
        ? 'oauth (stored)'
        : '',
    AuthKind.apiKey => _apiKeySource(p, config),
  };
}

String _apiKeySource(ProviderDef p, GlueConfig config) {
  final envVar = p.auth.envVar;
  if (envVar != null && config.credentials.readEnv(envVar) != null) {
    return 'env (\$$envVar)';
  }
  if (config.credentials.getField(p.id, 'api_key') != null) {
    return 'stored';
  }
  return '';
}

String _providerRemove(GlueConfig config, String id) {
  final p = config.catalogData.providers[id];
  if (p == null) return 'Unknown provider "$id".';
  config.credentials.remove(id);
  final envVar = p.auth.envVar;
  if (envVar != null && config.credentials.readEnv(envVar) != null) {
    return 'Forgot stored credentials for ${p.name}. '
        'Note: \$$envVar is still set and will keep being used.';
  }
  return 'Forgot stored credentials for ${p.name}.';
}

String _providerTest(GlueConfig config, String id) {
  final p = config.catalogData.providers[id];
  if (p == null) return 'Unknown provider "$id".';
  final adapter = config.adapters.lookup(p.adapter);
  if (adapter == null) {
    return 'No adapter for wire protocol "${p.adapter}".';
  }
  final resolved = config.resolveProvider(
    ModelRef(providerId: p.id, modelId: p.models.keys.isEmpty ? '?' : p.models.keys.first),
  );
  final health = adapter.validate(resolved);
  switch (health) {
    case ProviderHealth.ok:
      return '${p.name}: ok.';
    case ProviderHealth.missingCredential:
      return '${p.name}: missing credential. Run /provider add ${p.id}.';
    case ProviderHealth.unknownAdapter:
      return '${p.name}: adapter "${p.adapter}" failed validation.';
  }
}

String _switchToModelRowImpl(App app, CatalogRow row) {
  final factory = app._llmFactory;
  final config = app._config;
  final prompt = app._systemPrompt;
  final ref = ModelRef(providerId: row.providerId, modelId: row.model.id);
  if (factory != null && config != null && prompt != null) {
    final llm = factory.createFor(ref, systemPrompt: prompt);
    app.agent.llm = llm;
    app._config = config.copyWith(activeModel: ref);
  }
  app._modelId = ref.modelId;
  app._sessionManager.updateSessionModel(modelRef: ref.toString());
  return 'Switched to ${row.model.name}';
}
