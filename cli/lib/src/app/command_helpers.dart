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

  final outcome = resolveModelInput(query, config.catalogData);
  switch (outcome) {
    case ResolvedExact():
      final provider = config.catalogData.providers[outcome.ref.providerId]!;
      return app._switchToModelRow((
        providerId: provider.id,
        providerName: provider.name,
        model: outcome.def,
        availability: ModelAvailability.unknown,
      ));
    case ResolvedPassthrough():
      if (!outcome.providerKnown) {
        return 'Unknown provider "${outcome.ref.providerId}". '
            'Run `/models` to list available providers.';
      }
      final provider = config.catalogData.providers[outcome.ref.providerId]!;
      final synthetic = ModelDef(
        id: outcome.ref.modelId,
        name: outcome.ref.modelId,
      );
      return app._switchToModelRow((
        providerId: provider.id,
        providerName: provider.name,
        model: synthetic,
        availability: ModelAvailability.unknown,
      ));
    case AmbiguousBareInput():
      final options = outcome.candidates.map((c) => '  ${c.ref}').join('\n');
      return 'Model "$query" is ambiguous. Pick one:\n$options';
    case UnknownBareInput():
      final hint = config.catalogData.providers.values
          .expand((p) => p.models.values.map((m) => '${p.id}/${m.id}'))
          .take(12)
          .join(', ');
      return 'Unknown model: $query\n'
          'Use `<provider>/<id>` (e.g. `ollama/gemma4:latest`) or one of: '
          '$hint …';
  }
}

String _statusModelLabel(App app) => formatStatusModelLabel(
      app._config?.activeModel,
      app._config?.catalogData,
      app._modelId,
    );

String _buildSessionInfoImpl(App app) {
  final shortCwd = app._shortenPath(app._cwd);
  final trustedList = app._autoApprovedTools.toList()..sort();
  final displayModel = formatInfoModelLabel(
    app._config?.activeModel,
    app._config?.catalogData,
    app._modelId,
  );
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

String _sessionActionImpl(App app, List<String> args) {
  final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
  switch (subcommand) {
    case 'copy':
      final sessionId = app._sessionManager.currentSessionId;
      if (sessionId == null) {
        return 'No active session yet — nothing to copy.';
      }
      unawaited(
        copyToClipboard(sessionId).then((ok) {
          app._addSystemMessage(
            ok
                ? 'Session ID copied to clipboard.\n  $sessionId'
                : 'Could not access clipboard. Session ID:\n  $sessionId',
          );
          app._render();
        }),
      );
      return '';
    case '':
      return _buildSessionInfoImpl(app);
    default:
      return 'Unknown subcommand "$subcommand". Try: /session copy';
  }
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
      // Opens a SelectPanel over all providers with status; selection routes
      // into the action submenu (Connect / Disconnect / Test).
      unawaited(
        app._panels.openProviderPanel(
          config: config,
          addSystemMessage: app._addSystemMessage,
        ),
      );
      return '';
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
  final resolved = config.resolveProviderById(p.id);
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

const _openTargets = <String>[
  'home',
  'session',
  'sessions',
  'logs',
  'skills',
  'plans',
  'cache',
];

String _configActionImpl(App app, List<String> args) {
  final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
  switch (subcommand) {
    case '':
      return _openConfigInEditorImpl(app);
    case 'init':
      return _initUserConfigImpl(app, args.skip(1).toList());
    default:
      return 'Unknown subcommand "$subcommand". Try: /config or /config init';
  }
}

String _openConfigInEditorImpl(App app) {
  final editor = app._environment.vars['EDITOR']?.trim();
  if (editor == null || editor.isEmpty) {
    return r'EDITOR is not set. Set $EDITOR to use /config.';
  }

  final path = app._environment.configYamlPath;
  final file = File(path);
  if (!file.existsSync()) {
    try {
      initUserConfig(app._environment);
    } on FileSystemException catch (e) {
      return 'Failed to write config: ${e.message}';
    }
  }

  unawaited(Process.start(editor, [path], runInShell: true));
  return 'Opening $path in $editor';
}

String _initUserConfigImpl(App app, List<String> args) {
  final force = args.contains('--force');
  final unknown = args.where((arg) => arg != '--force').toList();
  if (unknown.isNotEmpty) {
    return 'Usage: /config init [--force]';
  }
  try {
    return initUserConfig(app._environment, force: force).message;
  } on FileSystemException catch (e) {
    return 'Failed to write config: ${e.message}';
  }
}

String _openGlueTargetImpl(App app, List<String> args) {
  if (args.isEmpty) {
    return 'Usage: /open <target>\n'
        'Targets: ${_openTargets.join(', ')}';
  }

  final target = args.first.toLowerCase();
  final env = app._environment;
  String path;
  switch (target) {
    case 'home':
      path = env.glueDir;
    case 'session':
      final id = app._sessionManager.currentSessionId;
      if (id == null) {
        return 'No active session yet — nothing to open.';
      }
      path = env.sessionDir(id);
    case 'sessions':
      path = env.sessionsDir;
    case 'logs':
      path = env.logsDir;
    case 'skills':
      path = env.skillsDir;
    case 'plans':
      path = env.plansDir;
    case 'cache':
      path = env.cacheDir;
    default:
      return 'Unknown target "$target". Try: ${_openTargets.join(', ')}';
  }

  if (!Directory(path).existsSync()) {
    return '$path\n(not yet created — open skipped)';
  }

  unawaited(openInFileManager(path));
  return 'Opening $path';
}

String _switchToModelRowImpl(App app, CatalogRow row) {
  // Ollama-specific: confirm and pull uninstalled tags before flipping
  // the active model. `installedOnly` rows came from `/api/tags`, so we
  // know they're present; `installed` rows were verified at picker-open
  // time. Everything else (notInstalled, or unknown from typed `/model`
  // input) runs through the confirmation flow, which is itself no-op
  // when discovery confirms the tag is already pulled.
  if (row.providerId == 'ollama' &&
      row.availability != ModelAvailability.installed &&
      row.availability != ModelAvailability.installedOnly) {
    final config = app._config;
    if (config != null) {
      final provider = config.catalogData.providers['ollama'];
      if (provider != null) {
        final discovery = OllamaDiscovery(
          baseUrl: Uri.parse(provider.baseUrl ?? 'http://localhost:11434'),
        );
        _confirmAndPullOllamaModelImpl(
          app,
          tag: row.model.id,
          discovery: discovery,
          onPull: () {
            final message = _applyModelSwitch(app, row);
            app._addSystemMessage(message);
            app._render();
          },
        );
        return '';
      }
    }
  }

  return _applyModelSwitch(app, row);
}

String _applyModelSwitch(App app, CatalogRow row) {
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

String _runMcpCommandImpl(App app, List<String> args) {
  final mcpManager = app._mcpManager;

  if (args.isEmpty) {
    if (mcpManager == null || mcpManager.servers.isEmpty) {
      return 'No MCP servers configured. '
          'Add servers to .glue/mcp.json or ~/.glue/mcp.json.\n'
          'Usage: /mcp [list|connect <id>|disconnect <id>]';
    }
    unawaited(
      app._panels.openMcpPanel(
        mcpManager: mcpManager,
        addSystemMessage: app._addSystemMessage,
      ),
    );
    return '';
  }

  final sub = args.first.toLowerCase();
  switch (sub) {
    case 'list':
      if (mcpManager == null || mcpManager.servers.isEmpty) {
        return 'No MCP servers configured.';
      }
      final buf = StringBuffer('MCP servers:\n');
      for (final state in mcpManager.servers.values) {
        final tools =
            state.tools.isNotEmpty ? '  (${state.tools.length} tools)' : '';
        buf.writeln(
            '  ${state.config.id}  [${_mcpStatusText(state.status)}]$tools');
      }
      return buf.toString().trimRight();

    case 'connect':
      if (mcpManager == null) return 'MCP not available.';
      if (args.length < 2) return 'Usage: /mcp connect <server-id>';
      final id = args[1];
      unawaited(
        mcpManager.connect(id).then((_) {
          final state = mcpManager.servers[id];
          app._addSystemMessage(
            'Connected to ${state?.config.name ?? id} '
            '(${state?.tools.length ?? 0} tools).',
          );
          app._render();
        }).catchError((Object e) {
          app._addSystemMessage('Failed to connect to $id: $e');
          app._render();
        }),
      );
      return 'Connecting to $id…';

    case 'disconnect':
      if (mcpManager == null) return 'MCP not available.';
      if (args.length < 2) return 'Usage: /mcp disconnect <server-id>';
      final id = args[1];
      unawaited(
        mcpManager.disconnect(id).then((_) {
          app._addSystemMessage('Disconnected from $id.');
          app._render();
        }),
      );
      return 'Disconnecting from $id…';

    default:
      return 'Unknown /mcp subcommand "$sub". '
          'Usage: /mcp [list|connect <id>|disconnect <id>]';
  }
}

String _mcpStatusText(McpServerStatus status) => switch (status) {
      McpServerStatus.disconnected => 'disconnected',
      McpServerStatus.connecting => 'connecting',
      McpServerStatus.initializing => 'initializing',
      McpServerStatus.ready => 'ready',
      McpServerStatus.error => 'error',
      McpServerStatus.shuttingDown => 'stopping',
    };
