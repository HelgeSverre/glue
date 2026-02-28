import 'dart:async';
import 'dart:io';

import 'terminal/terminal.dart';
import 'terminal/layout.dart';
import 'input/line_editor.dart';
import 'agent/agent_core.dart';
import 'agent/agent_manager.dart';
import 'agent/prompts.dart';
import 'agent/tools.dart';
import 'commands/slash_commands.dart';
import 'config/constants.dart';
import 'config/glue_config.dart';
import 'config/model_registry.dart';
import 'llm/llm_factory.dart';
import 'llm/model_lister.dart';
import 'rendering/block_renderer.dart';
import 'rendering/ansi_utils.dart';
import 'rendering/mascot.dart';
import 'shell/command_executor.dart';
import 'shell/executor_factory.dart';
import 'shell/host_executor.dart';
import 'shell/shell_config.dart';
import 'shell/shell_job_manager.dart';
import 'storage/session_state.dart';
import 'tools/subagent_tools.dart';
import 'ui/modal.dart';
import 'ui/panel_modal.dart';
import 'input/file_expander.dart';
import 'ui/at_file_hint.dart';
import 'ui/slash_autocomplete.dart';
import 'storage/glue_home.dart';
import 'storage/session_store.dart';
import 'storage/config_store.dart';

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

/// Top-level application mode.
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
class App {
  final Terminal terminal;
  final Layout layout;
  final LineEditor editor;
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
  PanelModal? _activePanel;
  bool _renderedPanelLastFrame = false;
  final Set<String> _autoApprovedTools = {
    'read_file',
    'list_directory',
    'grep',
    'spawn_subagent',
    'spawn_parallel_subagents',
  };
  final AgentManager? _manager;
  final LlmClientFactory? _llmFactory;
  GlueConfig? _config;
  final String? _systemPrompt;
  final CommandExecutor _executor;
  final ShellJobManager _jobManager;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  SessionStore? _sessionStore;
  bool _bashMode = false;
  Process? _bashRunProcess;
  DateTime? _lastCtrlC;

  final Map<String, _SubagentGroup> _subagentGroups = {};
  final List<_SubagentGroup?> _outputLineGroups = [];

  final bool _startupResume;
  final bool _startupContinue;

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
  })  : _modelName = modelName,
        _manager = manager,
        _llmFactory = llmFactory,
        _config = config,
        _systemPrompt = systemPrompt,
        _sessionStore = sessionStore,
        _executor = executor ?? HostExecutor(const ShellConfig()),
        _jobManager = jobManager ?? ShellJobManager(executor ?? HostExecutor(const ShellConfig())),
        _startupResume = startupResume,
        _startupContinue = startupContinue,
        _cwd = Directory.current.path {
    if (extraTrustedTools != null) {
      _autoApprovedTools.addAll(extraTrustedTools);
    }
    _initCommands();
    _autocomplete = SlashAutocomplete(_commands);
    _atHint = AtFileHint();
  }

  /// Convenience factory that creates a fully wired [App] with real
  /// LLM provider and subagent system.
  static Future<App> create({
    String? provider,
    String? model,
    bool startupResume = false,
    bool startupContinue = false,
  }) async {
    final config = GlueConfig.load(cliProvider: provider, cliModel: model);
    config.validate();

    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = LineEditor();

    final systemPrompt = Prompts.build(cwd: Directory.current.path);
    final llmFactory = LlmClientFactory();
    final llm = llmFactory.createFromConfig(config, systemPrompt: systemPrompt);

    final home = GlueHome();
    home.ensureDirectories();
    final configStore = ConfigStore(home.configPath);

    final sessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';
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

    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(executor),
      'grep': GrepTool(),
      'list_directory': ListDirectoryTool(),
    };

    final agent = AgentCore(llm: llm, tools: tools, modelName: config.model);

    // Create agent manager and register subagent tools.
    final manager = AgentManager(
      tools: tools,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
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
    );
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
      'Glue v0.1.0 — $_modelName\n'
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
          final suggestions = ModelRegistry.models
              .map((m) => m.modelId)
              .join(', ');
          return 'Unknown model: $query\nAvailable: $suggestions';
        }
        return _switchToModelEntry(entry);
      },
    ));

    _commands.register(SlashCommand(
      name: 'models',
      description: 'List available models from the current provider',
      execute: (_) {
        final config = _config;
        if (config == null) return 'No config available.';
        unawaited(_fetchModels(config));
        return 'Fetching ${config.provider.name} models\u2026';
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
      description: 'Show input history',
      execute: (args) {
        final n = args.isNotEmpty ? int.tryParse(args[0]) ?? 10 : 10;
        final hist = editor.history;
        if (hist.isEmpty) return 'No history.';
        final recent = hist.length > n ? hist.sublist(hist.length - n) : hist;
        final buf = StringBuffer('Recent inputs:\n');
        for (var i = 0; i < recent.length; i++) {
          buf.writeln('  ${i + 1}. ${recent[i]}');
        }
        return buf.toString();
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
  }

  Future<void> _fetchModels(GlueConfig config) async {
    try {
      final lister = ModelLister();
      final models = await lister.list(
        provider: config.provider,
        apiKey: config.provider == LlmProvider.ollama ? null : config.apiKey,
        ollamaBaseUrl: config.ollamaBaseUrl,
      );
      if (models.isEmpty) {
        _blocks.add(_ConversationEntry.system('No models found.'));
      } else {
        final buf = StringBuffer('${config.provider.name} models '
            '(${models.length}):\n');
        for (final m in models) {
          final current = m.id == _modelName ? ' ← current' : '';
          final size = m.size != null ? ' (${m.size})' : '';
          buf.writeln('  ${m.id}$size$current');
        }
        _blocks.add(_ConversationEntry.system(buf.toString()));
      }
    } catch (e) {
      _blocks.add(_ConversationEntry.system('Error fetching models: $e'));
    }
    _render();
  }

  String _resumeSession(SessionMeta session) {
    final home = GlueHome();
    final events = SessionStore.loadConversation(home.sessionDir(session.id));
    if (events.isEmpty) {
      return 'Session ${session.id} has no conversation data.';
    }

    _blocks.add(_ConversationEntry.system(
      'Resuming session ${session.id.substring(0, 8)}… '
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

    return 'Restored $userCount user + $assistantCount assistant messages.';
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
    const yellow = '\x1b[33m';
    const rst = '\x1b[0m';
    const dim = '\x1b[90m';

    final lines = <String>[];

    lines.add('$yellow■ COMMANDS$rst');
    lines.add('');
    for (final cmd in _commands.commands) {
      final aliases = cmd.aliases.isNotEmpty
          ? ' $dim(${cmd.aliases.map((a) => '/$a').join(', ')})$rst'
          : '';
      final name = '/${cmd.name}'.padRight(16);
      lines.add('  $yellow$name$rst${cmd.description}$aliases');
    }

    lines.add('');
    lines.add('$yellow■ KEYBINDINGS$rst');
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
    lines.add('$yellow■ FILE REFERENCES$rst');
    lines.add('');
    lines.add('  ${'@path/to/file'.padRight(16)}Attach file to message');
    lines.add('  ${'@dir/'.padRight(16)}Browse directory');

    _activePanel = PanelModal(
      title: 'HELP',
      lines: lines,
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
    );
    _render();
  }

  void _openResumePanel() {
    final home = GlueHome();
    final sessions = SessionStore.listSessions(home.sessionsDir);
    if (sessions.isEmpty) {
      _blocks.add(_ConversationEntry.system('No saved sessions found.'));
      _render();
      return;
    }

    final displayLines = <String>[];
    for (final s in sessions) {
      final ago = _timeAgo(s.startTime);
      final shortCwd = _shortenPath(s.cwd);
      final id = s.id.length > 8 ? s.id.substring(0, 8) : s.id;
      displayLines.add('$id…  ${s.model}  $shortCwd  $ago');
    }

    final panel = PanelModal(
      title: 'Resume Session',
      lines: displayLines,
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
      selectable: true,
    );
    _activePanel = panel;
    _render();

    panel.selection.then((idx) {
      _activePanel = null;
      if (idx == null) {
        _render();
        return;
      }
      final result = _resumeSession(sessions[idx]);
      if (result.isNotEmpty) {
        _blocks.add(_ConversationEntry.system(result));
      }
      _render();
    });
  }

  void _openModelPanel() {
    final config = _config;
    if (config == null) return;

    final entries = ModelRegistry.available(config);
    if (entries.isEmpty) {
      _blocks.add(_ConversationEntry.system('No models available (no API keys configured).'));
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
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 8),
      selectable: true,
    );
    // Scroll to initial selection.
    for (var i = 0; i < flatInitial; i++) {
      panel.handleEvent(KeyEvent(Key.down));
    }
    _activePanel = panel;
    _render();

    panel.selection.then((idx) {
      _activePanel = null;
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
        if (_activePanel != null && !_activePanel!.isComplete) {
          if (_activePanel!.handleEvent(event)) {
            if (_activePanel!.isComplete) _activePanel = null;
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
            _render();
            return;
          }
        }

        if (_mode == AppMode.streaming ||
            _mode == AppMode.toolRunning ||
            _mode == AppMode.bashRunning) {
          if (event
              case KeyEvent(key: Key.ctrlC) || KeyEvent(key: Key.escape)) {
            if (_mode == AppMode.bashRunning) {
              _cancelBash();
            } else {
              _cancelAgent();
            }
            return;
          }
          // Swallow Enter during streaming — keep buffer intact for when agent finishes.
          if (event case KeyEvent(key: Key.enter)) return;
          // Pre-typing: buffer other keystrokes.
          final action = editor.handle(event);
          if (action == InputAction.changed) _render();
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
            _autocomplete.update(editor.text, editor.cursor);
            if (!_autocomplete.active) {
              _atHint.update(editor.text, editor.cursor);
            } else {
              _atHint.dismiss();
            }
            _render();
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

  void _startAgent(String displayMessage, {String? expandedMessage}) {
    _blocks.add(
        _ConversationEntry.user(displayMessage, expandedText: expandedMessage));
    _mode = AppMode.streaming;
    _startSpinner();
    _streamingText = '';
    _subagentGroups.clear();
    _render();

    final stream = agent.run(expandedMessage ?? displayMessage);
    _agentSub = stream.listen(
      _handleAgentEvent,
      onError: (Object e) {
        _blocks.add(_ConversationEntry.error(e.toString()));
        _stopSpinner();
        _mode = AppMode.idle;
        _render();
      },
      onDone: () {
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

        // Auto-approve safe tools.
        if (_autoApprovedTools.contains(call.name)) {
          _toolUi[call.id]?.phase = _ToolPhase.running;
          _stopSpinner();
          _mode = AppMode.toolRunning;
          _render();
          unawaited(_executeAndCompleteTool(call));
          return;
        }

        // Show confirmation modal.
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
            ModalChoice('Yes', 'y'),
            ModalChoice('No', 'n'),
            ModalChoice('Always', 'a'),
          ],
        );
        _render();

        _activeModal!.result.then((choiceIndex) {
          _activeModal = null;
          switch (choiceIndex) {
            case 0: // Yes
              _toolUi[call.id]?.phase = _ToolPhase.running;
              _mode = AppMode.toolRunning;
              _render();
              unawaited(_executeAndCompleteTool(call));
            case 2: // Always
              _autoApprovedTools.add(call.name);
              try {
                final home = GlueHome();
                final store = ConfigStore(home.configPath);
                store.update((c) {
                  final tools =
                      (c['trusted_tools'] as List?)?.cast<String>() ?? [];
                  if (!tools.contains(call.name)) {
                    tools.add(call.name);
                    c['trusted_tools'] = tools;
                  }
                });
              } catch (_) {}
              _toolUi[call.id]?.phase = _ToolPhase.running;
              _mode = AppMode.toolRunning;
              _render();
              unawaited(_executeAndCompleteTool(call));
            default: // No
              _toolUi[call.id]?.phase = _ToolPhase.denied;
              _mode = AppMode.streaming;
              _startSpinner();
              agent.completeToolCall(ToolResult.denied(call.id));
              _render();
          }
        });

      case AgentToolResult(:final result):
        _toolUi[result.callId]?.phase = _ToolPhase.done;
        _blocks.add(
          _ConversationEntry.toolResult(result.callId, result.content),
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
    _render();
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

    final panelActive = _activePanel != null && !_activePanel!.isComplete;
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
        _EntryKind.toolCallRef => renderer.renderToolCallRef(
            _toolUi[block.text]?.toRenderState()),
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

    // Panel modal takes over the full viewport.
    if (panelActive) {
      _renderedPanelLastFrame = true;
      final panelGrid = _activePanel!.render(
        terminal.columns,
        terminal.rows,
        outputLines,
      );
      terminal.hideCursor();
      for (var i = 0; i < panelGrid.length && i < terminal.rows; i++) {
        terminal.moveTo(i + 1, 1);
        terminal.clearLine();
        terminal.write(panelGrid[i]);
      }
      return;
    }

    _renderedPanelLastFrame = false;

    // 2. Reserve overlay space for autocomplete (before computing viewport).
    final overlayHeight = _autocomplete.active
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

    // 4. Autocomplete / @file overlay.
    if (_autocomplete.active) {
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
    final statusLeft = ' $modeIndicator  $_modelName  $shortCwd';

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
    layout.paintInput(prompt, editor.text, editor.cursor,
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

  factory _ConversationEntry.toolResult(String callId, String content) =>
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
  _ToolCallUiState({required this.id, required this.name, this.phase = _ToolPhase.preparing});

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
