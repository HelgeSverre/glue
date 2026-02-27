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
import 'config/glue_config.dart';
import 'llm/llm_factory.dart';
import 'rendering/block_renderer.dart';
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
  static const _maxBlocks = 200;

  final Terminal terminal;
  final Layout layout;
  final LineEditor editor;
  final AgentCore agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final List<_ConversationEntry> _blocks = [];
  int _scrollOffset = 0;
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
    'read_file', 'list_directory', 'grep',
    'spawn_subagent', 'spawn_parallel_subagents',
  };
  final AgentManager? _manager;
  final LlmClientFactory? _llmFactory;
  final GlueConfig? _config;
  final String? _systemPrompt;
  late final SlashAutocomplete _autocomplete;
  late final AtFileHint _atHint;
  SessionStore? _sessionStore;

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
  }) : _modelName = modelName,
       _manager = manager,
       _llmFactory = llmFactory,
       _config = config,
       _systemPrompt = systemPrompt,
       _sessionStore = sessionStore,
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
  factory App.create({String? provider, String? model}) {
    final config = GlueConfig.load(cliProvider: provider, cliModel: model);
    config.validate();

    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = LineEditor();

    final systemPrompt = Prompts.build(cwd: Directory.current.path);
    final llmFactory = LlmClientFactory();
    final llm = llmFactory.createFromConfig(config, systemPrompt: systemPrompt);

    final tools = <String, Tool>{
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'edit_file': EditFileTool(),
      'bash': BashTool(),
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

    final home = GlueHome();
    home.ensureDirectories();
    final configStore = ConfigStore(home.configPath);

    final sessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';
    final sessionStore = SessionStore(
      sessionDir: home.sessionDir(sessionId),
      meta: SessionMeta(
        id: sessionId,
        cwd: Directory.current.path,
        model: config.model,
        provider: config.provider.name,
        startTime: DateTime.now(),
      ),
    );

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

    _render();

    try {
      await _exitCompleter.future;
    } finally {
      // Stop all event sources before touching terminal state.
      await _sessionStore?.close();
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
      aliases: ['quit', 'q'],
      execute: (_) {
        requestExit();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'model',
      description: 'Show or set the model name',
      execute: (args) {
        if (args.isEmpty) return 'Current model: $_modelName';
        final newModel = args.join(' ');
        if (_llmFactory != null && _config != null && _systemPrompt != null) {
          final llm = _llmFactory.create(
            provider: _config.provider,
            model: newModel,
            apiKey: _config.apiKey,
            systemPrompt: _systemPrompt,
            ollamaBaseUrl: _config.ollamaBaseUrl,
          );
          agent.llm = llm;
        }
        _modelName = newModel;
        return 'Model switched to: $_modelName';
      },
    ));

    _commands.register(SlashCommand(
      name: 'info',
      description: 'Show session info',
      aliases: ['status'],
      execute: (_) {
        final shortCwd = _shortenPath(_cwd);
        final trustedList = _autoApprovedTools.toList()..sort();
        final buf = StringBuffer();
        buf.writeln('Session Info');
        buf.writeln('  Model:        $_modelName');
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
        final home = GlueHome();
        final sessions = SessionStore.listSessions(home.sessionsDir);
        if (sessions.isEmpty) return 'No saved sessions found.';

        final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 10 : 10;
        final shown = sessions.take(count).toList();

        if (args.isNotEmpty) {
          final idx = (int.tryParse(args[0]) ?? 0) - 1;
          if (idx >= 0 && idx < shown.length) {
            return _resumeSession(shown[idx]);
          }
        }

        final buf = StringBuffer('Recent sessions:\n');
        for (var i = 0; i < shown.length; i++) {
          final s = shown[i];
          final ago = _timeAgo(s.startTime);
          final shortCwd = _shortenPath(s.cwd);
          buf.writeln(
            '  ${i + 1}. ${s.id.substring(0, 8)}…  '
            '${s.model}  $shortCwd  $ago',
          );
        }
        buf.writeln('\nUsage: /resume <number> to load a session.');
        return buf.toString();
      },
    ));
  }

  String _resumeSession(SessionMeta session) {
    final home = GlueHome();
    final events = SessionStore.loadConversation(home.sessionDir(session.id));
    if (events.isEmpty) {
      return 'Session ${session.id} has no conversation data.';
    }

    var userCount = 0;
    var assistantCount = 0;
    for (final event in events) {
      final type = event['type'] as String?;
      final text = event['text'] as String? ?? '';
      if (text.isEmpty) continue;
      switch (type) {
        case 'user_message':
          agent.addMessage(Message.user(text));
          userCount++;
        case 'assistant_message':
          agent.addMessage(Message.assistant(text: text));
          assistantCount++;
        default:
          break;
      }
    }

    _blocks.add(_ConversationEntry.system(
      'Resumed session ${session.id.substring(0, 8)}… '
      '($userCount user + $assistantCount assistant messages, model: ${session.model})',
    ));

    return 'Resumed session from ${_timeAgo(session.startTime)}.';
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
      style: PanelStyle.tape,
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.5, 10),
    );
    _render();
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

        if (_mode == AppMode.streaming || _mode == AppMode.toolRunning) {
          // While the agent is working the user can still cancel.
          if (event case KeyEvent(key: Key.ctrlC) || KeyEvent(key: Key.escape)) {
            _cancelAgent();
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
            final accepted = _atHint.accept();
            if (accepted != null) {
              final buf = editor.text;
              final before = buf.substring(0, _atHint.tokenStart);
              final after = buf.substring(editor.cursor);
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
            requestExit();
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

      case MouseEvent(:final isScroll, :final isScrollUp):
        if (isScroll) {
          _events.add(UserScroll(isScrollUp ? 3 : -3));
        }
    }
  }

  // ── App event handling ──────────────────────────────────────────────────

  void _handleAppEvent(AppEvent event) {
    switch (event) {
      case UserSubmit(:final text):
        if (text.startsWith('/')) {
          final result = _commands.execute(text);
          if (result != null && result.isNotEmpty) {
            _blocks.add(_ConversationEntry.system(result));
          }
          _render();
        } else {
          final expanded = expandFileRefs(text);
          _sessionStore?.logEvent('user_message', {'text': expanded});
          _startAgent(text, expandedMessage: expanded != text ? expanded : null);
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
    _blocks.add(_ConversationEntry.user(displayMessage,
        expandedText: expandedMessage));
    _mode = AppMode.streaming;
    _streamingText = '';
    _render();

    final stream = agent.run(expandedMessage ?? displayMessage);
    _agentSub = stream.listen(
      _handleAgentEvent,
      onError: (Object e) {
        _blocks.add(_ConversationEntry.error(e.toString()));
        _mode = AppMode.idle;
        _render();
      },
      onDone: () {
        if (_streamingText.isNotEmpty) {
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
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

      case AgentToolCall(:final call):
        // Flush any accumulated assistant text before the tool call so
        // the ordering in _blocks matches the actual conversation flow.
        if (_streamingText.isNotEmpty) {
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _blocks.add(_ConversationEntry.toolCall(call.name, call.arguments));
        _sessionStore?.logEvent('tool_call', {
          'name': call.name,
          'arguments': call.arguments,
        });

        // Auto-approve safe tools.
        if (_autoApprovedTools.contains(call.name)) {
          _mode = AppMode.toolRunning;
          _render();
          unawaited(_executeAndCompleteTool(call));
          return;
        }

        // Show confirmation modal.
        _mode = AppMode.confirming;
        final bodyLines = call.arguments.entries
            .map((e) => '${e.key}: ${e.value}')
            .toList();
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
              _mode = AppMode.toolRunning;
              _render();
              unawaited(_executeAndCompleteTool(call));
            case 2: // Always
              _autoApprovedTools.add(call.name);
              try {
                final home = GlueHome();
                final store = ConfigStore(home.configPath);
                store.update((c) {
                  final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
                  if (!tools.contains(call.name)) {
                    tools.add(call.name);
                    c['trusted_tools'] = tools;
                  }
                });
              } catch (_) {}
              _mode = AppMode.toolRunning;
              _render();
              unawaited(_executeAndCompleteTool(call));
            default: // No
              _mode = AppMode.streaming;
              agent.completeToolCall(ToolResult.denied(call.id));
              _render();
          }
        });

      case AgentToolResult(:final result):
        _blocks.add(
          _ConversationEntry.toolResult(result.callId, result.content),
        );
        _mode = AppMode.streaming;
        _render();

      case AgentDone():
        if (_streamingText.isNotEmpty) {
          _sessionStore?.logEvent('assistant_message', {'text': _streamingText});
          _blocks.add(_ConversationEntry.assistant(_streamingText));
          _streamingText = '';
        }
        _mode = AppMode.idle;
        _render();

      case AgentError(:final error):
        _blocks.add(_ConversationEntry.error(error.toString()));
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
    _render();
  }

  // ── Subagent updates ──────────────────────────────────────────────────

  void _handleSubagentUpdate(SubagentUpdate update) {
    final prefix = update.index != null
        ? '↳ [${update.index! + 1}/${update.total}]'
        : '↳';

    switch (update.event) {
      case AgentToolCall(:final call):
        final argsPreview = call.arguments.entries
            .take(2)
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');
        _blocks.add(_ConversationEntry.subagent(
          '$prefix ▶ ${call.name}  $argsPreview',
        ));
        _render();
      case AgentToolResult(:final result):
        final preview = result.content.length > 80
            ? '${result.content.substring(0, 80)}…'
            : result.content;
        _blocks.add(_ConversationEntry.subagent(
          '$prefix ✓ ${preview.replaceAll('\n', ' ')}',
        ));
        _render();
      case AgentError(:final error):
        _blocks.add(_ConversationEntry.subagent(
          '$prefix ✗ Error: $error',
        ));
        _render();
      case AgentTextDelta():
        break; // Skip text streaming — too noisy.
      case AgentDone():
        break;
    }
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  DateTime _lastRender = DateTime(0);
  bool _renderScheduled = false;
  static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps

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

    if (_blocks.length > _maxBlocks) {
      _blocks.removeRange(0, _blocks.length - _maxBlocks);
    }
    terminal.hideCursor();
    final renderer = BlockRenderer(terminal.columns);

    // 1. Build all output lines from blocks.
    final outputLines = <String>[];
    for (final block in _blocks) {
      final text = switch (block.kind) {
        _EntryKind.user => renderer.renderUser(block.text),
        _EntryKind.assistant => renderer.renderAssistant(block.text),
        _EntryKind.toolCall => renderer.renderToolCall(block.text, block.args),
        _EntryKind.toolResult => renderer.renderToolResult(block.text),
        _EntryKind.error => renderer.renderError(block.text),
        _EntryKind.subagent => renderer.renderSubagent(block.text),
        _EntryKind.system => renderer.renderSystem(block.text),
      };
      outputLines.addAll(text.split('\n'));
      outputLines.add(''); // blank line between blocks
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

    final firstLine = (totalLines - viewportHeight - _scrollOffset).clamp(0, totalLines);
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
      AppMode.streaming => '● Generating',
      AppMode.toolRunning => '⚙ Tool',
      AppMode.confirming => '? Approve',
    };
    final shortCwd = _shortenPath(_cwd);
    final statusLeft = ' $modeIndicator  $_modelName  $shortCwd';

    final scrollIndicator = _scrollOffset > 0 ? '↑$_scrollOffset  ' : '';
    final statusRight = '${scrollIndicator}tok ${agent.tokenCount} ';
    layout.paintStatus(statusLeft, statusRight);

    // 6. Input area — MUST be last so cursor lands here.
    final prompt = switch (_mode) {
      AppMode.idle => '❯ ',
      _ => '  ',
    };
    final showCursor = !(_mode == AppMode.confirming && _activeModal != null);
    layout.paintInput(prompt, editor.text, editor.cursor, showCursor: showCursor);
  }
}

// ---------------------------------------------------------------------------
// Conversation entries (simple model for the output log)
// ---------------------------------------------------------------------------

enum _EntryKind { user, assistant, toolCall, toolResult, error, system, subagent }

class _ConversationEntry {
  final _EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;
  final String? expandedText;

  _ConversationEntry._(this.kind, this.text, {this.args, this.expandedText});

  factory _ConversationEntry.user(String text, {String? expandedText}) =>
      _ConversationEntry._(_EntryKind.user, text, expandedText: expandedText);

  factory _ConversationEntry.assistant(String text) =>
      _ConversationEntry._(_EntryKind.assistant, text);

  factory _ConversationEntry.toolCall(
    String name,
    Map<String, dynamic> args,
  ) =>
      _ConversationEntry._(_EntryKind.toolCall, name, args: args);

  factory _ConversationEntry.toolResult(String callId, String content) =>
      _ConversationEntry._(_EntryKind.toolResult, content);

  factory _ConversationEntry.error(String message) =>
      _ConversationEntry._(_EntryKind.error, message);

  factory _ConversationEntry.subagent(String text) =>
      _ConversationEntry._(_EntryKind.subagent, text);

  factory _ConversationEntry.system(String text) =>
      _ConversationEntry._(_EntryKind.system, text);
}


