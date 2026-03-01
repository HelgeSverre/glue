import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/input/line_editor.dart' show InputAction;
import 'package:glue/src/input/text_area_editor.dart';
import 'package:glue/src/input/streaming_input_handler.dart';
import 'package:glue/src/input/file_expander.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/prompts.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/config/permission_mode.dart';
import 'package:glue/src/dev/devtools.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/title_generator.dart';
import 'package:glue/src/rendering/block_renderer.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/rendering/mascot.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/executor_factory.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/storage/glue_home.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:glue/src/storage/session_state.dart';
import 'package:glue/src/storage/config_store.dart';
import 'package:glue/src/tools/subagent_tools.dart';
import 'package:glue/src/tools/web_fetch_tool.dart';
import 'package:glue/src/tools/web_browser_tool.dart';
import 'package:glue/src/tools/web_search_tool.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:glue/src/web/browser/providers/docker_browser_provider.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';
import 'package:glue/src/web/search/search_router.dart';
import 'package:glue/src/web/search/providers/brave_provider.dart';
import 'package:glue/src/web/search/providers/tavily_provider.dart';
import 'package:glue/src/web/search/providers/firecrawl_provider.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/skills/skill_registry.dart';
import 'package:glue/src/skills/skill_tool.dart';
import 'package:glue/src/ui/modal.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/split_panel_modal.dart';
import 'package:glue/src/ui/at_file_hint.dart';
import 'package:glue/src/ui/shell_autocomplete.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/file_sink.dart';
import 'package:glue/src/observability/langfuse_sink.dart';
import 'package:glue/src/observability/otel_sink.dart';
import 'package:glue/src/observability/logging_http_client.dart';
import 'package:glue/src/observability/observed_llm_client.dart';
import 'package:glue/src/observability/devtools_sink.dart';
import 'package:glue/src/observability/observed_tool.dart';

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

/// Top-level application mode.
///
/// {@category Core}
enum AppMode {
  /// Waiting for user input.
  idle,

  /// The LLM is streaming a response.
  streaming,

  /// A tool is currently executing.
  toolRunning,

  /// Waiting for user to approve a tool invocation.
  confirming,

  /// A bash command is currently executing.
  bashRunning,
}

/// Outcome of the permission check for a tool call.
enum _Approval { allow, ask, deny }

// ---------------------------------------------------------------------------
// Application event bus
// ---------------------------------------------------------------------------

/// Events that flow through the application event bus.
sealed class AppEvent {}

// User-initiated events.
class UserSubmit extends AppEvent {
  final String text;
  UserSubmit(this.text);
}

class UserCancel extends AppEvent {}

class UserScroll extends AppEvent {
  final int delta;
  UserScroll(this.delta);
}

class UserResize extends AppEvent {
  final int cols;
  final int rows;
  UserResize(this.cols, this.rows);
}

// ---------------------------------------------------------------------------
// Main application controller
// ---------------------------------------------------------------------------

/// The main application controller.
///
/// Ties the terminal, layout, line editor, and agent together using an
/// event-driven architecture. Two independent streams (terminal input and
/// agent output) are merged into a single render cycle so the UI is never
/// blocked.
///
/// {@category Core}
class App {
  final Terminal terminal;
  final Layout layout;
  final TextAreaEditor editor;
  final AgentCore agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final List<_ConversationEntry> _blocks = [];
  final Map<String, _ToolCallUiState> _toolUi = {};
  int _scrollOffset = 0;

  static const _spinnerFrames = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏'
  ];
  int _spinnerFrame = 0;
  Timer? _spinnerTimer;
  String _streamingText = '';
  StreamSubscription<AgentEvent>? _agentSub;
  StreamSubscription<SubagentUpdate>? _subagentSub;
  final _exitCompleter = Completer<void>();

  late final SlashCommandRegistry _commands;
  String _modelName;
  final String _cwd;
  ConfirmModal? _activeModal;
  final List<PanelOverlay> _panelStack = [];
  bool _renderedPanelLastFrame = false;
  final Set<String> _autoApprovedTools = {
    'read_file',
    'list_directory',
    'grep',
    'spawn_subagent',
    'spawn_parallel_subagents',
    'web_fetch',
    'web_search',
    'web_browser',
    'skill',
  };
  final AgentManager? _manager;
  final LlmClientFactory? _llmFactory;
  GlueConfig? _config;
  final String? _systemPrompt;
  final CommandExecutor _executor;
  final ShellJobManager _jobManager;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  late final ShellAutocomplete _shellComplete;
  SessionStore? _sessionStore;
  bool _titleGenerated = false;
  bool _bashMode = false;
  Process? _bashRunProcess;
  DateTime? _lastCtrlC;

  final Map<String, _SubagentGroup> _subagentGroups = {};
  final List<_SubagentGroup?> _outputLineGroups = [];

  final bool _startupResume;
  final bool _startupContinue;
  final Observability? _obs;
  ObservabilitySpan? _turnSpan;
  final DebugController? _debugController;
  final SkillRegistry? _skillRegistry;
  PermissionMode _permissionMode;
  final Set<String> _earlyApprovedIds = {};

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelName,
    AgentManager? manager,
    LlmClientFactory? llmFactory,
    GlueConfig? config,
    String? systemPrompt,
    Set<String>? extraTrustedTools,
    SessionStore? sessionStore,
    CommandExecutor? executor,
    ShellJobManager? jobManager,
    bool startupResume = false,
    bool startupContinue = false,
    Observability? obs,
    DebugController? debugController,
    SkillRegistry? skillRegistry,
  })  : _modelName = modelName,
        _manager = manager,
        _llmFactory = llmFactory,
        _config = config,
        _systemPrompt = systemPrompt,
        _sessionStore = sessionStore,
        _executor = executor ?? HostExecutor(const ShellConfig()),
        _jobManager = jobManager ??
            ShellJobManager(executor ?? HostExecutor(const ShellConfig())),
        _startupResume = startupResume,
        _startupContinue = startupContinue,
        _obs = obs,
        _debugController = debugController,
        _skillRegistry = skillRegistry,
        _permissionMode = config?.permissionMode ?? PermissionMode.confirm,
        _cwd = Directory.current.path {
    if (extraTrustedTools != null) {
      _autoApprovedTools.addAll(extraTrustedTools);
    }
    _initCommands();
    _autocomplete = SlashAutocomplete(_commands);
    _atHint = AtFileHint();
    _shellComplete = ShellAutocomplete(ShellCompleter());
    _syncToolFilter();
  }

  /// Convenience factory that creates a fully wired [App] with real
  /// LLM provider and subagent system.
  static Future<App> create({
    String? provider,
    String? model,
    bool startupResume = false,
    bool startupContinue = false,
    bool debug = false,
  }) async {
    final config = GlueConfig.load(cliProvider: provider, cliModel: model);
    config.validate();

    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = TextAreaEditor();

    final skillRegistry = SkillRegistry.discover(
      cwd: Directory.current.path,
      extraPaths: config.skillPaths,
    );

    final systemPrompt = Prompts.build(
      cwd: Directory.current.path,
      skills: skillRegistry.list(),
    );

    final debugController = DebugController(
      enabled: debug || config.observability.debug,
    );
    final obs = Observability(debugController: debugController);

    final home = GlueHome();
    home.ensureDirectories();

    final sessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';

    final cwd = Directory.current.path;
    final resourceAttrs = <String, String>{
      'glue.session.id': sessionId,
      'glue.cwd': cwd,
      'gen_ai.system': config.provider.name,
      'gen_ai.request.model': config.model,
      'os.type': Platform.operatingSystem,
      'os.version': Platform.operatingSystemVersion,
      'host.arch': _hostArch(),
      'process.pid': '$pid',
      'deployment.environment.name': Platform.environment['GLUE_ENV'] ?? 'dev',
    };

    obs.addSink(DevToolsSink());
    obs.addSink(FileSink(logsDir: home.logsDir));
    if (config.observability.langfuse.isConfigured) {
      obs.addSink(LangfuseSink(
        config: config.observability.langfuse,
        resourceAttributes: resourceAttrs,
      ));
    }
    if (config.observability.otel.isConfigured) {
      obs.addSink(OtelSink(
        config: config.observability.otel,
        resourceAttributes: resourceAttrs,
      ));
    }

    if (config.observability.flushIntervalSeconds > 0) {
      obs.startAutoFlush(
        Duration(seconds: config.observability.flushIntervalSeconds),
      );
    }

    final httpClient = LoggingHttpClient(
      inner: http.Client(),
      obs: obs,
    );
    final llmFactory = LlmClientFactory(httpClient: httpClient);
    final rawLlm =
        llmFactory.createFromConfig(config, systemPrompt: systemPrompt);
    final llm = ObservedLlmClient(
      inner: rawLlm,
      obs: obs,
      provider: config.provider.name,
      model: config.model,
    );

    final configStore = ConfigStore(home.configPath);

    final sessionDir = home.sessionDir(sessionId);
    final sessionStore = SessionStore(
      sessionDir: sessionDir,
      meta: SessionMeta(
        id: sessionId,
        cwd: Directory.current.path,
        model: config.model,
        provider: config.provider.name,
        startTime: DateTime.now(),
      ),
    );

    final sessionState = SessionState.load(sessionDir);
    final executor = await ExecutorFactory.create(
      shellConfig: config.shellConfig,
      dockerConfig: config.dockerConfig,
      cwd: Directory.current.path,
      sessionMounts: sessionState.dockerMounts,
    );

    final searchRouter = SearchRouter([
      BraveSearchProvider(apiKey: config.webConfig.search.braveApiKey),
      TavilySearchProvider(apiKey: config.webConfig.search.tavilyApiKey),
      FirecrawlSearchProvider(
        apiKey: config.webConfig.search.firecrawlApiKey,
        baseUrl: config.webConfig.search.firecrawlBaseUrl ??
            'https://api.firecrawl.dev',
      ),
    ]);

    // Create browser provider based on config.
    final browserProvider = switch (config.webConfig.browser.backend) {
      BrowserBackend.local => LocalProvider(config.webConfig.browser),
      BrowserBackend.docker => DockerBrowserProvider(
          image: config.webConfig.browser.dockerImage,
          port: config.webConfig.browser.dockerPort,
          sessionId: sessionId,
        ),
      BrowserBackend.steel => SteelProvider(
          apiKey: config.webConfig.browser.steelApiKey,
        ),
      BrowserBackend.browserbase => BrowserbaseProvider(
          apiKey: config.webConfig.browser.browserbaseApiKey,
          projectId: config.webConfig.browser.browserbaseProjectId,
        ),
      BrowserBackend.browserless => BrowserlessProvider(
          apiKey: config.webConfig.browser.browserlessApiKey,
          baseUrl: config.webConfig.browser.browserlessBaseUrl ?? '',
        ),
    };
    final browserManager = BrowserManager(provider: browserProvider);

    final rawTools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
      'web_fetch':
          WebFetchTool(config.webConfig.fetch, pdfConfig: config.webConfig.pdf),
      'web_search': WebSearchTool(searchRouter),
      'web_browser': WebBrowserTool(browserManager),
      'skill': SkillTool(skillRegistry),
    };
    final tools = wrapToolsWithObservability(rawTools, obs);

    final agent = AgentCore(llm: llm, tools: tools, modelName: config.model);

    // Create agent manager and register subagent tools.
    final manager = AgentManager(
      tools: tools,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
      obs: obs,
    );
    tools['spawn_subagent'] = SpawnSubagentTool(manager);
    tools['spawn_parallel_subagents'] = SpawnParallelSubagentsTool(manager);

    return App(
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      modelName: config.model,
      manager: manager,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
      extraTrustedTools: configStore.trustedTools.toSet(),
      sessionStore: sessionStore,
      executor: executor,
      jobManager: ShellJobManager(executor),
      startupResume: startupResume,
      startupContinue: startupContinue,
      obs: obs,
      debugController: debugController,
      skillRegistry: skillRegistry,
    );
  }

  static String _hostArch() {
    // Dart doesn't expose arch directly; infer from OS version string.
    final ver = Platform.operatingSystemVersion.toLowerCase();
    if (ver.contains('arm64') || ver.contains('aarch64')) return 'arm64';
    if (ver.contains('x86_64') || ver.contains('amd64')) return 'x86_64';
    return 'unknown';
  }

  String _shortenPath(String path) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// Request a clean exit. Can be called from signal handlers.
  void requestExit() {
    _activeModal?.cancel();
    if (!_exitCompleter.isCompleted) _exitCompleter.complete();
  }

  /// Returns a JSON-serializable snapshot of internal state for DevTools.
  Map<String, dynamic> devtoolsState(String name) => switch (name) {
    'getAgentState' => {
      'mode': _mode.name,
      'tokenCount': agent.tokenCount,
      'model': _modelName,
      'conversationLength': agent.conversation.length,
      'pendingTools': _mode == AppMode.toolRunning ? 'active' : 'none',
    },
    'getConfig' => {
      'provider': _config?.provider.name ?? 'unknown',
      'model': _config?.model ?? 'unknown',
      'maxSubagentDepth': _config?.maxSubagentDepth ?? 0,
      'bashMaxLines': _config?.bashMaxLines ?? 0,
    },
    'getSessionInfo' => {
      'blockCount': _blocks.length,
      'scrollOffset': _scrollOffset,
    },
    'getToolHistory' => {
      'note': 'Tool history tracking not yet implemented',
    },
    _ => {'error': 'Unknown extension: $name'},
  };

  /// Run the application event loop.
  ///
  /// Enters raw / alt-screen mode and processes events until the user
  /// requests an exit.
  Future<void> run() async {
    terminal.enableRawMode();
    terminal.enableAltScreen();
    terminal.enableMouse();
    terminal.clearScreen();
    layout.apply();

    _blocks.add(_ConversationEntry.system(
      '\x1b[33m◆\x1b[0m Glue v${AppConstants.version} — $_modelName\n'
      'Working directory: ${_shortenPath(_cwd)}\n'
      'Type /help for commands.',
    ));

    final termSub = terminal.events.listen(_handleTerminalEvent);
    final appSub = _events.stream.listen(_handleAppEvent);
    _subagentSub = _manager?.updates.listen(_handleSubagentUpdate);
    final jobSub = _jobManager.events.listen(_handleJobEvent);

    _render();

    if (_startupResume) {
      _openResumePanel();
    } else if (_startupContinue) {
      final home = GlueHome();
      final sessions = SessionStore.listSessions(home.sessionsDir);
      if (sessions.isNotEmpty) {
        final result = _resumeSession(sessions.first);
        if (result.isNotEmpty) {
          _blocks.add(_ConversationEntry.system(result));
        }
        _render();
      } else {
        _blocks.add(_ConversationEntry.system('No sessions to continue.'));
        _render();
      }
    }

    try {
      await _exitCompleter.future;
    } finally {
      // Stop all event sources before touching terminal state.
      _stopSplashAnimation();
      _stopSpinner();
      // Dispose tools (closes browser sessions, containers, etc.).
      for (final tool in agent.tools.values) {
        try {
          await tool.dispose();
        } catch (_) {}
      }
      await _obs?.flush();
      await _obs?.close();
      await _sessionStore?.close();
      await jobSub.cancel();
      await _jobManager.shutdown();
      await termSub.cancel();
      await appSub.cancel();
      await _agentSub?.cancel();
      await _subagentSub?.cancel();
      await _events.close();
      terminal.disableMouse();
      terminal.resetScrollRegion();
      terminal.showCursor();
      terminal.write('\x1b[0m');
      terminal.disableAltScreen();
      terminal.disableRawMode();
      final sessionId = _sessionStore?.meta.id;
      if (sessionId != null) {
        stdout
            .writeln('\n\x1b[33m◆\x1b[0m Holding it together till next time.');
        stdout.writeln('  \x1b[90m\$ glue --resume $sessionId\x1b[0m');
      }
      terminal.dispose();
    }
  }

  /// Cleanly shut down the application.
  void shutdown() {
    requestExit();
  }

  // ── Slash commands ──────────────────────────────────────────────────────

  void _initCommands() {
    _commands = SlashCommandRegistry();

    _commands.register(SlashCommand(
      name: 'help',
      description: 'Show available commands and keybindings',
      execute: (_) {
        _openHelpPanel();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'clear',
      description: 'Clear conversation history',
      execute: (_) {
        _blocks.clear();
        _scrollOffset = 0;
        _streamingText = '';
        terminal.clearScreen();
        layout.apply();
        return 'Cleared.';
      },
    ));

    _commands.register(SlashCommand(
      name: 'exit',
      description: 'Exit Glue',
      aliases: ['quit'],
      hiddenAliases: ['q'],
      execute: (_) {
        requestExit();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'model',
      description: 'Switch model',
      execute: (args) {
        if (args.isEmpty) {
          _openModelPanel();
          return '';
        }
        final query = args.join(' ');
        final entry = ModelRegistry.findByName(query);
        if (entry == null) {
          final suggestions =
              ModelRegistry.models.map((m) => m.modelId).join(', ');
          return 'Unknown model: $query\nAvailable: $suggestions';
        }
        return _switchToModelEntry(entry);
      },
    ));

    _commands.register(SlashCommand(
      name: 'models',
      description: 'Browse and switch models across all providers',
      execute: (_) {
        _openModelPanel();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'info',
      description: 'Show session info',
      aliases: ['status'],
      execute: (_) {
        final shortCwd = _shortenPath(_cwd);
        final trustedList = _autoApprovedTools.toList()..sort();
        final entry = ModelRegistry.findById(_modelName);
        final displayModel = entry != null
            ? '${entry.displayName} (${entry.modelId})'
            : _modelName;
        final buf = StringBuffer();
        buf.writeln('Session Info');
        buf.writeln('  Model:        $displayModel');
        buf.writeln('  Provider:     ${_config?.provider.name ?? "unknown"}');
        buf.writeln('  Directory:    $shortCwd');
        buf.writeln('  Tokens used:  ${agent.tokenCount}');
        buf.writeln('  Messages:     ${agent.conversation.length}');
        buf.writeln('  Tools:        ${agent.tools.length} registered');
        buf.writeln(
            '  Permissions:  ${_permissionMode.label} (Shift+Tab to cycle)');
        buf.writeln('  Auto-approve: ${trustedList.join(", ")}');
        return buf.toString();
      },
    ));

    _commands.register(SlashCommand(
      name: 'tools',
      description: 'List available tools',
      execute: (_) {
        final buf = StringBuffer('Available tools:\n');
        for (final tool in agent.tools.values) {
          buf.writeln('  ${tool.name} — ${tool.description}');
        }
        return buf.toString();
      },
    ));

    _commands.register(SlashCommand(
      name: 'history',
      description: 'Browse conversation history',
      execute: (args) {
        _openHistoryPanel();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'resume',
      description: 'Resume a previous session',
      execute: (args) {
        _openResumePanel();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'devtools',
      description: 'Open Dart DevTools in browser',
      execute: (_) {
        unawaited(GlueDev.getDevToolsUrl().then((url) {
          if (url == null) {
            _blocks.add(_ConversationEntry.system(
                'DevTools not available. Run with: just dev'));
            _render();
            return;
          }
          Process.run('open', [url.toString()]);
        }));
        return 'Opening DevTools...';
      },
    ));

    _commands.register(SlashCommand(
      name: 'debug',
      description: 'Toggle debug mode (verbose logging)',
      execute: (args) {
        if (_debugController != null) {
          _debugController.toggle();
          return 'Debug mode: ${_debugController.enabled}';
        }
        return 'Debug mode: unavailable';
      },
    ));

    _commands.register(SlashCommand(
      name: 'skills',
      description: 'Browse available skills',
      execute: (_) {
        _openSkillsPanel();
        return '';
      },
    ));
  }

  String _resumeSession(SessionMeta session) {
    final home = GlueHome();
    final events = SessionStore.loadConversation(home.sessionDir(session.id));
    if (events.isEmpty) {
      return 'Session ${session.id} has no conversation data.';
    }

    _blocks.add(_ConversationEntry.system(
      'Resuming session ${session.id} '
      '(${session.model}, ${_timeAgo(session.startTime)})',
    ));

    var userCount = 0;
    var assistantCount = 0;
    for (final event in events) {
      final type = event['type'] as String?;
      final text = event['text'] as String? ?? '';
      switch (type) {
        case 'user_message':
          if (text.isEmpty) continue;
          agent.addMessage(Message.user(text));
          _blocks.add(_ConversationEntry.user(text));
          userCount++;
        case 'assistant_message':
          if (text.isEmpty) continue;
          agent.addMessage(Message.assistant(text: text));
          _blocks.add(_ConversationEntry.assistant(text));
          assistantCount++;
        case 'tool_call':
          final name = event['name'] as String? ?? '';
          final args = event['arguments'] as Map<String, dynamic>? ?? {};
          if (name.isNotEmpty) {
            _blocks.add(_ConversationEntry.toolCall(name, args));
          }
        default:
          break;
      }
    }

    // Backfill title for resumed sessions that lack one.
    if (!_titleGenerated) {
      if (session.title != null) {
        _titleGenerated = true;
      } else if (userCount > 0) {
        for (final e in events) {
          if (e['type'] == 'user_message' &&
              ((e['text'] as String?) ?? '').isNotEmpty) {
            _titleGenerated = true;
            _generateTitle(e['text'] as String);
            break;
          }
        }
      }
    }

    return 'Restored $userCount user + $assistantCount assistant messages.';
  }

  /// Fire-and-forget: generate a session title in the background.
  void _generateTitle(String userMessage) {
    final apiKey = _config?.anthropicApiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    final sessionStore = _sessionStore;
    if (sessionStore == null) return;

    final model = _config?.titleModel ?? AppConstants.defaultTitleModel;

    unawaited(() async {
      final client = http.Client();
      try {
        final generator = TitleGenerator(
          httpClient: client,
          apiKey: apiKey,
          model: model,
        );
        final title = await generator.generate(userMessage);
        if (title != null) {
          sessionStore.setTitle(title);
          sessionStore.logEvent('title_generated', {'title': title});
        }
      } finally {
        client.close();
      }
    }());
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return time.toIso8601String().substring(0, 10);
  }

  void _openHelpPanel() {
    final lines = <String>[];

    lines.add('${'■ COMMANDS'.styled.yellow}');
    lines.add('');
    for (final cmd in _commands.commands) {
      final aliases = cmd.aliases.isNotEmpty
          ? ' ${'(${cmd.aliases.map((a) => '/$a').join(', ')})'.styled.gray}'
          : '';
      final name = '/${cmd.name}'.padRight(16);
      lines.add('  ${name.styled.yellow}${cmd.description}$aliases');
    }

    lines.add('');
    lines.add('${'■ KEYBINDINGS'.styled.yellow}');
    lines.add('');
    lines.add('  ${'Ctrl+C'.padRight(16)}Cancel / Exit');
    lines.add('  ${'Escape'.padRight(16)}Cancel generation');
    lines.add('  ${'Up / Down'.padRight(16)}History navigation');
    lines.add('  ${'Ctrl+U'.padRight(16)}Clear line');
    lines.add('  ${'Ctrl+W'.padRight(16)}Delete word');
    lines.add('  ${'Ctrl+A / E'.padRight(16)}Start / End of line');
    lines.add('  ${'PageUp / Dn'.padRight(16)}Scroll output');
    lines.add('  ${'Tab'.padRight(16)}Accept completion');

    lines.add('');
    lines.add('${'■ FILE REFERENCES'.styled.yellow}');
    lines.add('');
    lines.add('  ${'@path/to/file'.padRight(16)}Attach file to message');
    lines.add('  ${'@dir/'.padRight(16)}Browse directory');

    final panel = PanelModal(
      title: 'HELP',
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
    );
    _panelStack.add(panel);
    _render();

    panel.result.then((_) {
      _panelStack.remove(panel);
      _render();
    });
  }

  void _openResumePanel() {
    final home = GlueHome();
    final sessions = SessionStore.listSessions(home.sessionsDir);
    if (sessions.isEmpty) {
      _blocks.add(_ConversationEntry.system('No saved sessions found.'));
      _render();
      return;
    }

    const dim = '\x1b[90m';
    const yellow = '\x1b[33m';
    const rst = '\x1b[0m';
    const idW = 12;
    const modelW = 20;
    const pathW = 30;
    const ageW = 10;
    const gap = '  ';

    final displayLines = <String>[];

    // Header
    displayLines.add(
      '$dim${'ID'.padRight(idW)}$gap'
      '${'MODEL'.padRight(modelW)}$gap'
      '${'DIRECTORY'.padRight(pathW)}$gap'
      '${'AGE'.padRight(ageW)}$rst',
    );
    // Separator
    displayLines.add(
      '$dim${'─' * (idW + 2 + modelW + 2 + pathW + 2 + ageW)}$rst',
    );

    for (final s in sessions) {
      final ago = _timeAgo(s.startTime);
      final shortCwd = _shortenPath(s.cwd);
      final displayId = s.title ??
          (s.id.length > idW
              ? '${s.id.substring(0, idW - 1)}…'
              : s.id.padRight(idW));
      final model = s.model.length > modelW
          ? '${s.model.substring(0, modelW - 1)}…'
          : s.model;
      final forkBadge =
          s.forkedFrom != null ? '${'[F]'.styled.fg256(208)} ' : '';

      displayLines.add(
        '$forkBadge$yellow${displayId.padRight(idW)}$rst$gap'
        '${model.padRight(modelW)}$gap'
        '$dim${shortCwd.padRight(pathW)}$rst$gap'
        '$dim${ago.padRight(ageW)}$rst',
      );
    }

    final panel = PanelModal(
      title: 'Resume Session',
      lines: displayLines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
      selectable: true,
      initialIndex: 2,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.remove(panel);
      if (idx == null || idx < 2) {
        _render();
        return;
      }
      final result = _resumeSession(sessions[idx - 2]);
      if (result.isNotEmpty) {
        _blocks.add(_ConversationEntry.system(result));
      }
      _render();
    });
  }

  void _openHistoryPanel() {
    final userBlocks = <(int, _ConversationEntry)>[];
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].kind == _EntryKind.user) {
        userBlocks.add((i, _blocks[i]));
      }
    }

    if (userBlocks.isEmpty) {
      _blocks.add(_ConversationEntry.system('No conversation history.'));
      _render();
      return;
    }

    final displayLines = <String>[];
    for (var i = 0; i < userBlocks.length; i++) {
      final text = userBlocks[i].$2.text.replaceAll('\n', ' ');
      displayLines.add('${(i + 1).toString().padLeft(3)}. $text');
    }

    final panel = PanelModal(
      title: 'History',
      lines: displayLines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
      selectable: true,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      if (idx == null) {
        _panelStack.remove(panel);
        _render();
        return;
      }
      // Keep history panel on stack so it's visible behind the action panel.
      _openHistoryActionPanel(
        userBlocks[idx].$2.text,
        idx, // user message index (0-based)
      );
    });
  }

  void _openHistoryActionPanel(String messageText, int userMessageIndex) {
    final panel = PanelModal(
      title: 'Action',
      lines: ['Fork conversation', 'Copy to clipboard'],
      barrier: BarrierStyle.dim,
      height: PanelFixed(4),
      width: PanelFixed(30),
      selectable: true,
    );
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.clear();
      if (idx == null) {
        _render();
        return;
      }
      switch (idx) {
        case 0:
          _forkSession(userMessageIndex, messageText);
        case 1:
          Process.start('pbcopy', []).then((proc) {
            proc.stdin.write(messageText);
            return proc.stdin.close();
          }).catchError((_) {});
          _blocks.add(_ConversationEntry.system('Copied to clipboard.'));
          _render();
      }
    });
  }

  void _forkSession(int userMessageIndex, String messageText) {
    final oldStore = _sessionStore;
    if (oldStore == null) return;

    final oldSessionId = oldStore.meta.id;
    final home = GlueHome();

    // Load events from current session and truncate at the selected user message.
    final allEvents = SessionStore.loadConversation(oldStore.sessionDir);
    var userCount = 0;
    final truncatedEvents = <Map<String, dynamic>>[];
    for (final event in allEvents) {
      truncatedEvents.add(event);
      if (event['type'] == 'user_message') {
        if (userCount == userMessageIndex) break;
        userCount++;
      }
    }

    // Close the old session.
    oldStore.close();

    // Create a new session.
    final newId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';
    final newStore = SessionStore(
      sessionDir: home.sessionDir(newId),
      meta: SessionMeta(
        id: newId,
        cwd: oldStore.meta.cwd,
        model: oldStore.meta.model,
        provider: oldStore.meta.provider,
        startTime: DateTime.now(),
        forkedFrom: oldSessionId,
      ),
    );

    // Write truncated events to new session.
    for (final event in truncatedEvents) {
      final type = event['type'] as String? ?? '';
      final data = Map<String, dynamic>.from(event)
        ..remove('type')
        ..remove('timestamp');
      newStore.logEvent(type, data);
    }

    // Clear UI and agent state.
    _blocks.clear();
    agent.clearConversation();

    // Replay truncated events into blocks and agent.
    final shortId =
        oldSessionId.length > 8 ? oldSessionId.substring(0, 8) : oldSessionId;
    _blocks.add(_ConversationEntry.system(
      'Forked from session $shortId…',
    ));

    for (final event in truncatedEvents) {
      final type = event['type'] as String?;
      final text = event['text'] as String? ?? '';
      switch (type) {
        case 'user_message':
          if (text.isEmpty) continue;
          agent.addMessage(Message.user(text));
          _blocks.add(_ConversationEntry.user(text));
        case 'assistant_message':
          if (text.isEmpty) continue;
          agent.addMessage(Message.assistant(text: text));
          _blocks.add(_ConversationEntry.assistant(text));
        case 'tool_call':
          final name = event['name'] as String? ?? '';
          final args = event['arguments'] as Map<String, dynamic>? ?? {};
          if (name.isNotEmpty) {
            _blocks.add(_ConversationEntry.toolCall(name, args));
          }
        default:
          break;
      }
    }

    // Swap session store and set editor buffer.
    _sessionStore = newStore;
    editor.setText(messageText);
    _render();
  }

  void _openModelPanel() {
    final config = _config;
    if (config == null) return;

    final entries = ModelRegistry.available(config);
    if (entries.isEmpty) {
      _blocks.add(_ConversationEntry.system(
          'No models available (no API keys configured).'));
      _render();
      return;
    }

    const dim = '\x1b[90m';
    const yellow = '\x1b[33m';
    const rst = '\x1b[0m';

    final flatLines = <String>[];
    final flatEntries = <ModelEntry>[];
    LlmProvider? lastProvider;
    int flatInitial = 0;

    for (final entry in entries) {
      final isCurrent = entry.modelId == _modelName;
      final providerHeader = entry.provider != lastProvider
          ? '$yellow${entry.provider.name}$rst  '
          : ' ' * (entry.provider.name.length + 2);
      lastProvider = entry.provider;

      final marker = isCurrent ? '\u25cf ' : '  ';
      final name = entry.displayName.padRight(22);
      final tag = entry.tagline.padRight(18);
      final cost = entry.costLabel.padRight(5);
      final speed = entry.speedLabel;

      if (isCurrent) flatInitial = flatEntries.length;
      flatLines.add('$providerHeader$marker$name $dim$tag$rst $cost $speed');
      flatEntries.add(entry);
    }

    final panel = PanelModal(
      title: 'Switch Model',
      lines: flatLines,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 8),
      selectable: true,
    );
    // Scroll to initial selection.
    for (var i = 0; i < flatInitial; i++) {
      panel.handleEvent(KeyEvent(Key.down));
    }
    _panelStack.add(panel);
    _render();

    panel.selection.then((idx) {
      _panelStack.remove(panel);
      if (idx == null) {
        _render();
        return;
      }
      final entry = flatEntries[idx];
      final result = _switchToModelEntry(entry);
      _blocks.add(_ConversationEntry.system(result));
      _render();
    });
  }

  void _openSkillsPanel() {
    final registry = _skillRegistry;
    if (registry == null || registry.isEmpty) {
      _blocks.add(_ConversationEntry.system('No skills found.\n\n'
          'To add skills, create directories with SKILL.md files in:\n'
          '  ~/.glue/skills/<skill-name>/SKILL.md (global)\n'
          '  .glue/skills/<skill-name>/SKILL.md (project-local)'));
      _render();
      return;
    }

    final skills = registry.list();

    const cyan = '\x1b[36m';
    const green = '\x1b[32m';
    const rst = '\x1b[0m';

    final maxNameLen =
        skills.fold<int>(0, (m, s) => s.name.length > m ? s.name.length : m);
    final leftItems = skills.map((s) {
      final tag = switch (s.source) {
        SkillSource.project => '${green}project$rst',
        SkillSource.global => '${cyan}global$rst',
        SkillSource.custom => '${cyan}custom$rst',
      };
      return '${s.name.padRight(maxNameLen)}  $tag';
    }).toList();

    List<String> buildDetail(int idx, int width) {
      if (idx < 0 || idx >= skills.length) return [];
      final s = skills[idx];
      final lines = <String>[];

      const bold = '\x1b[1m';
      const dim = '\x1b[2m';
      const lbl = '\x1b[32m';

      lines.add('$bold${s.name}$rst');
      lines.add('');

      final wrapped = _wrapText(s.description, width);
      lines.addAll(wrapped);
      lines.add('');

      final shortDir = _shortenPath(s.skillDir);
      lines.add('${lbl}Source$rst      $dim$shortDir$rst');
      if (s.license != null) {
        lines.add('${lbl}License$rst    $dim${s.license}$rst');
      }
      if (s.compatibility != null) {
        lines.add('${lbl}Requires$rst   $dim${s.compatibility}$rst');
      }
      for (final entry in s.metadata.entries) {
        final key = entry.key[0].toUpperCase() + entry.key.substring(1);
        final pad = ' ' * (11 - key.length);
        lines.add('$lbl$key$rst$pad$dim${entry.value}$rst');
      }

      return lines;
    }

    final panel = SplitPanelModal(
      title: 'SKILLS',
      leftItems: leftItems,
      buildRightLines: buildDetail,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.6, 12),
    );
    _panelStack.add(panel);
    _render();

    unawaited(panel.selection.then((idx) {
      _panelStack.remove(panel);
      if (idx == null) {
        _render();
        return;
      }
      final skill = skills[idx];
      try {
        final body = registry.loadBody(skill.name);
        _blocks
            .add(_ConversationEntry.system('# Skill: ${skill.name}\n\n$body'));
      } on SkillParseError catch (e) {
        _blocks.add(_ConversationEntry.system(
            'Error loading skill "${skill.name}": $e'));
      }
      _render();
    }));
  }

  static List<String> _wrapText(String text, int width) {
    final lines = <String>[];
    var line = '';
    for (final word in text.split(' ')) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= width) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines;
  }

  String _switchToModelEntry(ModelEntry entry) {
    final factory = _llmFactory;
    final config = _config;
    final prompt = _systemPrompt;
    if (factory != null && config != null && prompt != null) {
      final llm = factory.createFromEntry(entry, config, systemPrompt: prompt);
      agent.llm = llm;
      _config = config.copyWith(
        provider: entry.provider,
        model: entry.modelId,
      );
    }
    _modelName = entry.modelId;
    return 'Switched to ${entry.displayName}';
  }

  // ── Terminal event handling ─────────────────────────────────────────────

  void _handleTerminalEvent(TerminalEvent event) {
    switch (event) {
      case CharEvent() || KeyEvent():
        // Panel modal gets first crack at input.
        if (_panelStack.isNotEmpty && !_panelStack.last.isComplete) {
          if (_panelStack.last.handleEvent(event)) {
            _doRender();
            return;
          }
        }

        // Confirm modal gets next crack at input.
        if (_activeModal != null && !_activeModal!.isComplete) {
          if (_activeModal!.handleEvent(event)) {
            _render();
            return;
          }
        }

        // Permission mode cycling — works in all modes.
        if (event case KeyEvent(key: Key.shiftTab)) {
          _permissionMode = _permissionMode.next;
          _syncToolFilter();
          _render();
          return;
        }

        // Scroll handling — works in all modes.
        if (event case KeyEvent(key: Key.pageUp)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _events.add(UserScroll(viewportHeight ~/ 2));
          return;
        }
        if (event case KeyEvent(key: Key.pageDown)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _events.add(UserScroll(-(viewportHeight ~/ 2)));
          return;
        }

        // Bash mode switching — before passing to editor.
        if (_mode == AppMode.idle) {
          if (!_bashMode &&
              event is CharEvent &&
              event.char == '!' &&
              editor.cursor == 0) {
            _bashMode = true;
            _render();
            return;
          }
          if (_bashMode &&
              event is KeyEvent &&
              event.key == Key.backspace &&
              editor.cursor == 0) {
            _bashMode = false;
            _shellComplete.dismiss();
            _render();
            return;
          }
        }

        if (_mode == AppMode.streaming ||
            _mode == AppMode.toolRunning ||
            _mode == AppMode.bashRunning) {
          final result = handleStreamingInput(
            event: event,
            isBashRunning: _mode == AppMode.bashRunning,
            editor: editor,
            autocomplete: _autocomplete,
            commands: _commands,
          );
          if (result.commandOutput != null &&
              result.commandOutput!.isNotEmpty) {
            _blocks.add(_ConversationEntry.system(result.commandOutput!));
          }
          switch (result.action) {
            case StreamingAction.render:
              _render();
            case StreamingAction.swallowed:
              break;
            case StreamingAction.cancelAgent:
              _cancelAgent();
            case StreamingAction.cancelBash:
              _cancelBash();
          }
          return;
        }

        // Autocomplete intercepts keys when active.
        if (_autocomplete.active) {
          if (event case KeyEvent(key: Key.up)) {
            _autocomplete.moveUp();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.down)) {
            _autocomplete.moveDown();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.tab)) {
            final accepted = _autocomplete.accept();
            if (accepted != null) {
              editor.setText(accepted);
            }
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.enter)) {
            if (_autocomplete.selectedText == editor.text) {
              _autocomplete.dismiss();
              // Fall through to normal submit handling.
            } else {
              final accepted = _autocomplete.accept();
              if (accepted != null) {
                editor.setText(accepted);
              }
              _render();
              return;
            }
          }
          if (event case KeyEvent(key: Key.escape)) {
            _autocomplete.dismiss();
            _render();
            return;
          }
        }

        // Shell completion intercepts keys when active (bash mode).
        if (_shellComplete.active) {
          if (event case KeyEvent(key: Key.up)) {
            _shellComplete.moveUp();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.down)) {
            _shellComplete.moveDown();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.tab) || KeyEvent(key: Key.enter)) {
            final result = _shellComplete.accept();
            if (result != null) {
              editor.setText(result.text, cursor: result.cursor);
            }
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.escape)) {
            _shellComplete.dismiss();
            _render();
            return;
          }
        }

        // @file hint intercepts keys when active.
        if (_atHint.active) {
          if (event case KeyEvent(key: Key.up)) {
            _atHint.moveUp();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.down)) {
            _atHint.moveDown();
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.enter) || KeyEvent(key: Key.tab)) {
            final start = _atHint.tokenStart;
            final cursor = editor.cursor;
            final accepted = _atHint.accept();
            if (accepted != null) {
              final buf = editor.text;
              final before = buf.substring(0, start);
              final after = buf.substring(cursor);
              editor.setText('$before$accepted$after',
                  cursor: before.length + accepted.length);
            }
            _render();
            return;
          }
          if (event case KeyEvent(key: Key.escape)) {
            _atHint.dismiss();
            _render();
            return;
          }
        }

        // Normal idle mode — full input handling.
        final action = editor.handle(event);
        switch (action) {
          case InputAction.submit:
            _autocomplete.dismiss();
            _atHint.dismiss();
            _shellComplete.dismiss();
            final text = editor.lastSubmitted;
            if (text.isNotEmpty) {
              _events.add(UserSubmit(text));
            }
          case InputAction.interrupt:
            final now = DateTime.now();
            if (_lastCtrlC != null &&
                now.difference(_lastCtrlC!) <
                    AppConstants.ctrlCDoubleTapWindow) {
              _lastCtrlC = null;
              requestExit();
            } else {
              _lastCtrlC = now;
              _blocks.add(
                  _ConversationEntry.system('Press Ctrl+C again to exit.'));
              _render();
            }
          case InputAction.changed:
            if (_bashMode) {
              _shellComplete.dismiss();
            } else {
              _autocomplete.update(editor.text, editor.cursor);
              if (!_autocomplete.active) {
                _atHint.update(editor.text, editor.cursor);
              } else {
                _atHint.dismiss();
              }
            }
            _render();
          case InputAction.requestCompletion:
            if (_bashMode) {
              _shellComplete
                  .requestCompletions(editor.text, editor.cursor)
                  .then((_) => _render());
            }
          default:
            break;
        }

      case ResizeEvent(:final cols, :final rows):
        _events.add(UserResize(cols, rows));

      case MouseEvent(
          :final x,
          :final y,
          :final isScroll,
          :final isScrollUp,
          :final isDown
        ):
        if (isScroll) {
          _events.add(UserScroll(isScrollUp ? 3 : -3));
        } else if (isDown) {
          if (y >= layout.outputTop && y <= layout.outputBottom) {
            final viewportHeight = layout.outputBottom - layout.outputTop + 1;
            final totalLines = _outputLineGroups.length;
            final firstLine = (totalLines - viewportHeight - _scrollOffset)
                .clamp(0, totalLines);
            final outputLineIdx = firstLine + (y - layout.outputTop);
            if (outputLineIdx >= 0 &&
                outputLineIdx < _outputLineGroups.length) {
              final group = _outputLineGroups[outputLineIdx];
              if (group != null) {
                group.expanded = !group.expanded;
                _render();
                return;
              }
            }
          }
          if (_liquidSim != null) {
            _handleSplashClick(x, y);
          }
        }

      case PasteEvent():
        // Dismiss popups before inserting paste content.
        _autocomplete.dismiss();
        _atHint.dismiss();
        final action = editor.handle(event);
        if (action == InputAction.changed) {
          _autocomplete.update(editor.text, editor.cursor);
          if (!_autocomplete.active) {
            _atHint.update(editor.text, editor.cursor);
          }
          _render();
        }
    }
  }

  // ── App event handling ──────────────────────────────────────────────────

  void _handleAppEvent(AppEvent event) {
    switch (event) {
      case UserSubmit(:final text):
        if (_bashMode) {
          _handleBashSubmit(text);
        } else if (text.startsWith('/')) {
          final result = _commands.execute(text);
          if (result != null && result.isNotEmpty) {
            _blocks.add(_ConversationEntry.system(result));
          }
          _render();
        } else {
          final expanded = expandFileRefs(text);
          _sessionStore?.logEvent('user_message', {'text': expanded});
          if (!_titleGenerated) {
            _titleGenerated = true;
            _generateTitle(expanded);
          }
          _startAgent(text,
              expandedMessage: expanded != text ? expanded : null);
        }

      case UserCancel():
        _cancelAgent();

      case UserScroll(:final delta):
        _scrollOffset = (_scrollOffset + delta).clamp(0, 999999);
        _render();

      case UserResize():
        layout.apply();
        terminal.clearScreen();
        _scrollOffset = 0;
        _render();
    }
  }

  // ── Agent interaction ──────────────────────────────────────────────────

  void _endTurnSpan({Map<String, dynamic>? extra}) {
    final span = _turnSpan;
    final obs = _obs;
    if (span != null && obs != null) {
      obs.endSpan(span, extra: extra);
      if (obs.activeSpan == span) obs.activeSpan = null;
      _turnSpan = null;
    }
  }

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _blocks.add(
        _ConversationEntry.user(displayMessage, expandedText: expandedMessage));
    _mode = AppMode.streaming;
    _startSpinner();
    _streamingText = '';
    _subagentGroups.clear();
    _render();

    _turnSpan = _obs?.startSpan(
      'agent.turn',
      kind: 'internal',
      attributes: {'user.message_length': displayMessage.length},
    );
    if (_turnSpan != null) _obs!.activeSpan = _turnSpan;

    final stream = agent.run(expandedMessage ?? displayMessage);
    _agentSub = stream.listen(
      _handleAgentEvent,
      onError: (Object e) {
        _endTurnSpan(extra: {'error': e.toString()});
        _blocks.add(_ConversationEntry.error(e.toString()));
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
      },
      onDone: () {
        _endTurnSpan();
        if (_streamingText.isNotEmpty) {
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
      },
    );
  }

  void _handleAgentEvent(AgentEvent event) {
    switch (event) {
      case AgentTextDelta(:final delta):
        _streamingText += delta;
        _render();

      case AgentToolCallPending(:final id, :final name):
        // Flush any accumulated assistant text so the ordering in _blocks
        // matches the actual conversation flow.
        if (_streamingText.isNotEmpty) {
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _toolUi[id] = _ToolCallUiState(id: id, name: name);
        _blocks.add(_ConversationEntry.toolCallRef(id));

        // Early confirmation — ask before arguments finish streaming.
        if (_needsEarlyConfirmation(name)) {
          _toolUi[id]?.phase = _ToolPhase.awaitingApproval;
          _stopSpinner();
          _mode = AppMode.confirming;
          _activeModal = ConfirmModal(
            title: 'Allow $name?',
            bodyLines: ['(arguments still streaming\u2026)'],
            choices: [
              const ModalChoice('Yes', 'y'),
              const ModalChoice('No', 'n'),
              const ModalChoice('Always', 'a'),
            ],
          );
          _render();

          _activeModal!.result.then((choiceIndex) {
            _activeModal = null;
            switch (choiceIndex) {
              case 0: // Yes
                _earlyApprovedIds.add(id);
                _toolUi[id]?.phase = _ToolPhase.preparing;
                _mode = AppMode.streaming;
                _startSpinner();
                _render();
              case 2: // Always
                _persistTrustedTool(name);
                _earlyApprovedIds.add(id);
                _toolUi[id]?.phase = _ToolPhase.preparing;
                _mode = AppMode.streaming;
                _startSpinner();
                _render();
              default: // No
                _cancelAgent();
                agent.completeToolCall(ToolResult.denied(id));
            }
          });
          return;
        }

        _render();

      case AgentToolCall(:final call):
        final uiState = _toolUi[call.id];
        if (uiState != null) {
          uiState.args = call.arguments;
        } else {
          // Ollama path — no prior pending event, create the ref now.
          if (_streamingText.isNotEmpty) {
            _blocks.add(_ConversationEntry.assistant(_streamingText));
            _streamingText = '';
          }
          _toolUi[call.id] = _ToolCallUiState(
            id: call.id,
            name: call.name,
            phase: _ToolPhase.preparing,
          )..args = call.arguments;
          _blocks.add(_ConversationEntry.toolCallRef(call.id));
        }

        _sessionStore?.logEvent('tool_call', {
          'name': call.name,
          'arguments': call.arguments,
        });

        // Early-approved at ToolCallPending time — re-check with full args.
        if (_earlyApprovedIds.remove(call.id)) {
          final approval = _resolveApproval(call);
          if (approval == _Approval.allow) {
            _approveTool(call);
            return;
          }
          // Path outside CWD in acceptEdits → fall through to modal.
        }

        // Permission-based approval.
        switch (_resolveApproval(call)) {
          case _Approval.allow:
            _approveTool(call);
          case _Approval.deny:
            _denyTool(call);
          case _Approval.ask:
            _showToolConfirmModal(call);
        }

      case AgentToolResult(:final result):
        _toolUi[result.callId]?.phase = _ToolPhase.done;
        _blocks.add(
          _ConversationEntry.toolResult(result.content),
        );
        _mode = AppMode.streaming;
        _startSpinner();
        _render();

      case AgentDone():
        if (_streamingText.isNotEmpty) {
          _sessionStore
              ?.logEvent('assistant_message', {'text': _streamingText});
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _stopSpinner();
        _mode = AppMode.idle;
        _render();

      case AgentError(:final error):
        _blocks.add(_ConversationEntry.error(error.toString()));
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
    }
  }

  Future<void> _executeAndCompleteTool(ToolCall call) async {
    try {
      final result = await agent.executeTool(call);
      agent.completeToolCall(result);
    } catch (e) {
      agent.completeToolCall(ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      ));
    }
  }

  void _cancelAgent() {
    _agentSub?.cancel();
    _endTurnSpan(extra: {'cancelled': true});
    _mode = AppMode.idle;
    if (_streamingText.isNotEmpty) {
      _blocks.add(_ConversationEntry.assistant('$_streamingText\n[cancelled]'));
      _streamingText = '';
    }
    for (final state in _toolUi.values) {
      if (state.phase == _ToolPhase.preparing ||
          state.phase == _ToolPhase.running) {
        state.phase = _ToolPhase.error;
      }
    }
    agent.ensureToolResultsComplete();
    _render();
  }

  // ── Permission mode ──────────────────────────────────────────────────

  void _syncToolFilter() {
    switch (_permissionMode) {
      case PermissionMode.readOnly:
        agent.toolFilter = (tool) => !tool.isMutating;
      default:
        agent.toolFilter = null;
    }
  }

  _Approval _resolveApproval(ToolCall call) {
    final tool = agent.tools[call.name];

    switch (_permissionMode) {
      case PermissionMode.ignorePermissions:
        return _Approval.allow;

      case PermissionMode.readOnly:
        if (tool != null && tool.isMutating) return _Approval.deny;
        return _Approval.allow;

      case PermissionMode.acceptEdits:
        if (_isTrusted(call.name)) return _Approval.allow;
        if (tool != null && tool.trust == ToolTrust.fileEdit) {
          if (_targetsPathOutsideCwd(call)) return _Approval.ask;
          return _Approval.allow;
        }
        return _Approval.ask;

      case PermissionMode.confirm:
        if (_isTrusted(call.name)) return _Approval.allow;
        return _Approval.ask;
    }
  }

  bool _isTrusted(String toolName) => _autoApprovedTools.contains(toolName);

  bool _targetsPathOutsideCwd(ToolCall call) {
    final path = call.arguments['path'] as String? ??
        call.arguments['file_path'] as String?;
    if (path == null) return false;
    final resolved = File(path).absolute.path;
    return !p.isWithin(_cwd, resolved) && resolved != _cwd;
  }

  /// Whether this tool needs a confirmation prompt at ToolCallPending time
  /// (before arguments have streamed).
  bool _needsEarlyConfirmation(String toolName) {
    final tool = agent.tools[toolName];

    switch (_permissionMode) {
      case PermissionMode.ignorePermissions:
      case PermissionMode.readOnly:
        // ignorePermissions: everything allowed.
        // readOnly: mutating tools denied (not asked).
        return false;
      case PermissionMode.acceptEdits:
        if (_isTrusted(toolName)) return false;
        if (tool != null && tool.trust == ToolTrust.fileEdit) return false;
        return true;
      case PermissionMode.confirm:
        return !_isTrusted(toolName);
    }
  }

  void _persistTrustedTool(String name) {
    _autoApprovedTools.add(name);
    try {
      final home = GlueHome();
      final store = ConfigStore(home.configPath);
      store.update((c) {
        final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
        if (!tools.contains(name)) {
          tools.add(name);
          c['trusted_tools'] = tools;
        }
      });
    } catch (_) {}
  }

  void _approveTool(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.running;
    _stopSpinner();
    _mode = AppMode.toolRunning;
    _render();
    unawaited(_executeAndCompleteTool(call));
  }

  void _denyTool(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.denied;
    _mode = AppMode.streaming;
    _startSpinner();
    agent.completeToolCall(ToolResult.denied(call.id));
    _render();
  }

  void _showToolConfirmModal(ToolCall call) {
    _toolUi[call.id]?.phase = _ToolPhase.awaitingApproval;
    _stopSpinner();
    _mode = AppMode.confirming;
    final bodyLines =
        call.arguments.entries.map((e) => '${e.key}: ${e.value}').toList();
    if (bodyLines.isEmpty) bodyLines.add('(no arguments)');
    _activeModal = ConfirmModal(
      title: 'Approve tool: ${call.name}',
      bodyLines: bodyLines,
      choices: [
        const ModalChoice('Yes', 'y'),
        const ModalChoice('No', 'n'),
        const ModalChoice('Always', 'a'),
      ],
    );
    _render();

    _activeModal!.result.then((choiceIndex) {
      _activeModal = null;
      switch (choiceIndex) {
        case 0: // Yes
          _approveTool(call);
        case 2: // Always
          _persistTrustedTool(call.name);
          _approveTool(call);
        default: // No
          _denyTool(call);
      }
    });
  }

  // ── Bash mode ─────────────────────────────────────────────────────────

  void _handleBashSubmit(String text) {
    if (text.isEmpty) return;

    if (text.startsWith('& ') || text == '&') {
      final command = text.substring(1).trim();
      if (command.isEmpty) return;
      _startBackgroundJob(command);
      return;
    }

    _mode = AppMode.bashRunning;
    _render();
    unawaited(_runBlockingBash(text));
  }

  Future<void> _runBlockingBash(String command) async {
    try {
      final running = await _executor.startStreaming(command);
      _bashRunProcess = running.process;

      final stdoutFuture =
          running.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          running.stderr.transform(const SystemEncoding().decoder).join();

      final exitCode = await running.exitCode;
      _bashRunProcess = null;

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.write(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.write('\n');
        output.write(stderr);
      }

      final stripped = stripAnsi(output.toString().trimRight());
      _blocks.add(_ConversationEntry.bash(command, stripped));
      if (exitCode != 0) {
        _blocks.add(_ConversationEntry.system('Exit code: $exitCode'));
      }
    } catch (e) {
      _bashRunProcess = null;
      _blocks.add(_ConversationEntry.error('Bash error: $e'));
    }
    _mode = AppMode.idle;
    _render();
  }

  void _cancelBash() {
    _bashRunProcess?.kill(ProcessSignal.sigterm);
    _bashRunProcess = null;
    _mode = AppMode.idle;
    _blocks.add(_ConversationEntry.system('[bash command cancelled]'));
    _render();
  }

  void _startBackgroundJob(String command) {
    unawaited(() async {
      try {
        await _jobManager.start(command);
      } catch (e) {
        _blocks.add(_ConversationEntry.error('Failed to start job: $e'));
        _render();
      }
    }());
  }

  void _handleJobEvent(JobEvent event) {
    switch (event) {
      case JobStarted(:final id, :final command):
        _blocks.add(_ConversationEntry.system('↳ Started job #$id: $command'));
        _render();
      case JobExited(:final id, :final exitCode):
        final job = _jobManager.getJob(id);
        final cmd = job?.command ?? '?';
        final label = exitCode == 0 ? 'exited' : 'failed';
        _blocks.add(
            _ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'));
        _render();
      case JobError(:final id, :final error):
        _blocks.add(_ConversationEntry.system('↳ Job #$id error: $error'));
        _render();
    }
  }

  // ── Subagent updates ──────────────────────────────────────────────────

  void _handleSubagentUpdate(SubagentUpdate update) {
    final groupKey = '${update.task}:${update.index ?? 0}';
    final group = _subagentGroups.putIfAbsent(
      groupKey,
      () {
        final g = _SubagentGroup(
          task: update.task,
          index: update.index,
          total: update.total,
        );
        _blocks.add(_ConversationEntry.subagentGroup(g));
        return g;
      },
    );

    final prefix =
        update.index != null ? '↳ [${update.index! + 1}/${update.total}]' : '↳';

    switch (update.event) {
      case AgentToolCall(:final call):
        final argsPreview = call.arguments.entries
            .take(2)
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');
        group.entries.add('$prefix ▶ ${call.name}  $argsPreview');
        _render();
      case AgentToolResult(:final result):
        final preview = result.content.length > 80
            ? '${result.content.substring(0, 80)}…'
            : result.content;
        group.entries.add('$prefix ✓ ${preview.replaceAll('\n', ' ')}');
        _render();
      case AgentError(:final error):
        group.entries.add('$prefix ✗ Error: $error');
        _render();
      case AgentToolCallPending():
        break;
      case AgentTextDelta():
        break;
      case AgentDone():
        group.done = true;
        _render();
    }
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  DateTime _lastRender = DateTime(0);
  bool _renderScheduled = false;
  static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps

  // Splash liquid simulation state.
  LiquidSim? _liquidSim;
  Timer? _splashTimer;
  int _splashOriginCol = 0; // screen col of mascot left edge
  int _splashOriginRow = 0; // screen row of mascot top edge
  GooExplosion? _gooExplosion;

  void _startSplashAnimation() {
    _liquidSim ??= LiquidSim();
    if (_splashTimer != null) return;
    _splashTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_gooExplosion != null) {
        _gooExplosion!.step();
        if (_gooExplosion!.isDone) {
          _stopSplashAnimation();
        }
        _render();
        return;
      }
      _liquidSim!.step();
      if (_liquidSim!.isActive) _render();
    });
  }

  void _stopSplashAnimation() {
    _splashTimer?.cancel();
    _splashTimer = null;
    _liquidSim = null;
    _gooExplosion = null;
  }

  void _triggerExplosion() {
    final viewH = layout.outputBottom - layout.outputTop + 1;
    _gooExplosion = GooExplosion(
      viewportWidth: terminal.columns,
      viewportHeight: viewH,
      originX: _splashOriginCol,
      originY: _splashOriginRow - layout.outputTop,
    );
    _liquidSim = null;
  }

  void _handleSplashClick(int screenX, int screenY) {
    if (_gooExplosion != null) return;
    final sim = _liquidSim;
    if (sim == null) return;
    final localX = screenX - _splashOriginCol;
    final localY = screenY - _splashOriginRow;
    if (localX >= 0 &&
        localX < mascotRenderWidth &&
        localY >= 0 &&
        localY < mascotRenderHeight) {
      sim.impulse(localX, localY);
      if (sim.shouldExplode) {
        _triggerExplosion();
      }
      _render();
    }
  }

  void _startSpinner() {
    if (_spinnerTimer != null) return;
    _spinnerFrame = 0;
    _spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _spinnerFrame = (_spinnerFrame + 1) % _spinnerFrames.length;
      _render();
    });
  }

  void _stopSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
  }

  void _render() {
    final now = DateTime.now();
    if (now.difference(_lastRender) < _minRenderInterval) {
      if (!_renderScheduled) {
        _renderScheduled = true;
        Future.delayed(_minRenderInterval, () {
          _renderScheduled = false;
          if (DateTime.now().difference(_lastRender) >= _minRenderInterval) {
            _doRender();
          }
        });
      }
      return;
    }
    _doRender();
  }

  void _doRender() {
    _lastRender = DateTime.now();

    final panelActive = _panelStack.isNotEmpty;
    if (_renderedPanelLastFrame && !panelActive) {
      terminal.resetScrollRegion();
      terminal.clearScreen();
      layout.apply();
    }

    if (_blocks.length > AppConstants.maxConversationBlocks) {
      _blocks.removeRange(
          0, _blocks.length - AppConstants.maxConversationBlocks);
    }
    terminal.hideCursor();
    final renderer = BlockRenderer(terminal.columns);

    // 1. Build all output lines from blocks.
    final outputLines = <String>[];
    _outputLineGroups.clear();
    for (final block in _blocks) {
      final text = switch (block.kind) {
        _EntryKind.user => renderer.renderUser(block.text),
        _EntryKind.assistant => renderer.renderAssistant(block.text),
        _EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
        _EntryKind.toolCallRef =>
          renderer.renderToolCallRef(_toolUi[block.text]?.toRenderState()),
        _EntryKind.toolResult => renderer.renderToolResult(block.text),
        _EntryKind.error => renderer.renderError(block.text),
        _EntryKind.subagent => renderer.renderSubagent(block.text),
        _EntryKind.subagentGroup => renderer.renderSubagent(
            block.group!.expanded
                ? '${block.group!.summary}\n${block.group!.entries.join('\n')}'
                : block.group!.summary),
        _EntryKind.system => renderer.renderSystem(block.text),
        _EntryKind.bash => renderer.renderBash(
            block.expandedText ?? 'shell',
            block.text,
            maxLines: _config?.bashMaxLines ?? 50,
          ),
      };
      final lines = text.split('\n');
      final group = block.kind == _EntryKind.subagentGroup ? block.group : null;
      for (var j = 0; j < lines.length; j++) {
        _outputLineGroups.add(group);
      }
      _outputLineGroups.add(null);
      outputLines.addAll(lines);
      outputLines.add('');
    }

    // Splash screen: show animated mascot when only the initial system block.
    final isSplash = _blocks.length == 1 &&
        _blocks.first.kind == _EntryKind.system &&
        _streamingText.isEmpty;
    if (isSplash && _gooExplosion != null) {
      // Explosion takes over the entire output viewport.
      _startSplashAnimation();
      final explosionLines = _gooExplosion!.render();
      outputLines.clear();
      outputLines.addAll(explosionLines);
    } else if (isSplash) {
      _startSplashAnimation();
      final mascotLines = renderMascot(_liquidSim!);
      final viewH = layout.outputBottom - layout.outputTop + 1;
      final artH = mascotLines.length;
      final padTop =
          ((viewH - outputLines.length - artH) / 2).clamp(0, viewH).toInt();
      for (var i = 0; i < padTop; i++) {
        outputLines.add('');
      }
      final padLeft = ((terminal.columns - mascotRenderWidth) / 2)
          .clamp(0, terminal.columns)
          .toInt();
      _splashOriginCol = padLeft;
      _splashOriginRow = layout.outputTop + outputLines.length;
      for (final line in mascotLines) {
        outputLines.add('${' ' * padLeft}$line');
      }
    } else {
      _stopSplashAnimation();
    }

    // If streaming, add the partial text.
    if (_streamingText.isNotEmpty) {
      outputLines.addAll(renderer.renderAssistant(_streamingText).split('\n'));
    }

    // Inline modal (if active) — appended to the output flow.
    if (_activeModal != null && !_activeModal!.isComplete) {
      outputLines.add('');
      outputLines.addAll(_activeModal!.render(terminal.columns));
    }

    // Trailing blank line so content doesn't butt against the status bar.
    outputLines.add('');

    // Panel stack takes over the full viewport.
    if (panelActive) {
      _renderedPanelLastFrame = true;
      var grid = outputLines;
      for (final panel in _panelStack) {
        grid = panel.render(terminal.columns, terminal.rows, grid);
      }
      terminal.hideCursor();
      for (var i = 0; i < grid.length && i < terminal.rows; i++) {
        terminal.moveTo(i + 1, 1);
        terminal.clearLine();
        terminal.write(grid[i]);
      }
      return;
    }

    _renderedPanelLastFrame = false;

    // 2. Reserve overlay space for autocomplete (before computing viewport).
    final overlayHeight = _shellComplete.active
        ? _shellComplete.overlayHeight
        : _autocomplete.active
            ? _autocomplete.overlayHeight
            : _atHint.overlayHeight;
    layout.setOverlayHeight(overlayHeight);

    // 3. Compute visible window.
    final viewportHeight = layout.outputBottom - layout.outputTop + 1;
    final totalLines = outputLines.length;
    final maxScroll = (totalLines - viewportHeight).clamp(0, totalLines);
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);

    final firstLine =
        (totalLines - viewportHeight - _scrollOffset).clamp(0, totalLines);
    final endLine = (firstLine + viewportHeight).clamp(0, totalLines);
    final visibleLines = firstLine < endLine
        ? outputLines.sublist(firstLine, endLine)
        : <String>[];

    layout.paintOutputViewport(visibleLines);

    // 4. Autocomplete / @file / shell overlay.
    if (_shellComplete.active) {
      layout.paintOverlay(_shellComplete.render(terminal.columns));
    } else if (_autocomplete.active) {
      layout.paintOverlay(_autocomplete.render(terminal.columns));
    } else if (_atHint.active) {
      layout.paintOverlay(_atHint.render(terminal.columns));
    } else {
      layout.paintOverlay([]);
    }

    // 5. Status bar.
    final modeIndicator = switch (_mode) {
      AppMode.idle => 'Ready',
      AppMode.streaming => '${_spinnerFrames[_spinnerFrame]} Generating',
      AppMode.toolRunning => '⚙ Tool',
      AppMode.confirming => '? Approve',
      AppMode.bashRunning => '! Running',
    };
    final shortCwd = _shortenPath(_cwd);
    final permLabel = '[${_permissionMode.label}]';
    final statusLeft = ' $modeIndicator  $_modelName  $permLabel  $shortCwd';

    final scrollIndicator = _scrollOffset > 0 ? '↑$_scrollOffset  ' : '';
    final statusRight = '${scrollIndicator}tok ${agent.tokenCount} ';
    layout.paintStatus(statusLeft, statusRight);

    // 6. Input area — MUST be last so cursor lands here.
    final prompt = switch ((_mode, _bashMode)) {
      (AppMode.idle, true) => '! ',
      (AppMode.idle, false) => '❯ ',
      _ => '  ',
    };
    final promptStyle = switch ((_mode, _bashMode)) {
      (AppMode.idle, true) => AnsiStyle.red,
      (AppMode.idle, false) => AnsiStyle.yellow,
      _ => AnsiStyle.dim,
    };
    final showCursor = !(_mode == AppMode.confirming && _activeModal != null);
    layout.paintInput(prompt, editor.lines, editor.cursorRow, editor.cursorCol,
        showCursor: showCursor, promptStyle: promptStyle);
  }
}

// ---------------------------------------------------------------------------
// Conversation entries (simple model for the output log)
// ---------------------------------------------------------------------------

enum _EntryKind {
  user,
  assistant,
  toolCall,
  toolCallRef,
  toolResult,
  error,
  system,
  subagent,
  subagentGroup,
  bash
}

class _ConversationEntry {
  final _EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;
  final String? expandedText;
  final _SubagentGroup? group;

  _ConversationEntry._(this.kind, this.text,
      {this.args, this.expandedText, this.group});

  factory _ConversationEntry.user(String text, {String? expandedText}) =>
      _ConversationEntry._(_EntryKind.user, text, expandedText: expandedText);

  factory _ConversationEntry.assistant(String text) =>
      _ConversationEntry._(_EntryKind.assistant, text);

  factory _ConversationEntry.toolCall(
    String name,
    Map<String, dynamic> args,
  ) =>
      _ConversationEntry._(_EntryKind.toolCall, name, args: args);

  factory _ConversationEntry.toolCallRef(String callId) =>
      _ConversationEntry._(_EntryKind.toolCallRef, callId);

  factory _ConversationEntry.toolResult(String content) =>
      _ConversationEntry._(_EntryKind.toolResult, content);

  factory _ConversationEntry.error(String message) =>
      _ConversationEntry._(_EntryKind.error, message);

  factory _ConversationEntry.subagentGroup(_SubagentGroup group) =>
      _ConversationEntry._(_EntryKind.subagentGroup, '', group: group);

  factory _ConversationEntry.system(String text) =>
      _ConversationEntry._(_EntryKind.system, text);

  factory _ConversationEntry.bash(String command, String output) =>
      _ConversationEntry._(_EntryKind.bash, output, expandedText: command);
}

class _SubagentGroup {
  final String task;
  final int? index;
  final int? total;
  final List<String> entries = [];
  bool expanded = false;
  bool done = false;

  _SubagentGroup({required this.task, this.index, this.total});

  String get summary {
    final prefix = index != null ? '[${index! + 1}/$total]' : '';
    final status = done ? '✓' : '${entries.length} steps…';
    final taskPreview = task.length > 50 ? '${task.substring(0, 50)}…' : task;
    return '↳ $prefix $taskPreview ($status)';
  }
}

enum _ToolPhase { preparing, awaitingApproval, running, done, denied, error }

class _ToolCallUiState {
  final String id;
  final String name;
  Map<String, dynamic>? args;
  _ToolPhase phase;
  _ToolCallUiState(
      {required this.id,
      required this.name,
      this.phase = _ToolPhase.preparing});

  ToolCallRenderState toRenderState() => ToolCallRenderState(
        name: name,
        args: args,
        phase: switch (phase) {
          _ToolPhase.preparing => ToolCallPhase.preparing,
          _ToolPhase.awaitingApproval => ToolCallPhase.awaitingApproval,
          _ToolPhase.running => ToolCallPhase.running,
          _ToolPhase.done => ToolCallPhase.done,
          _ToolPhase.denied => ToolCallPhase.denied,
          _ToolPhase.error => ToolCallPhase.error,
        },
      );
}
