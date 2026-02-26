import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'terminal/terminal.dart';
import 'terminal/layout.dart';
import 'input/line_editor.dart';
import 'agent/agent_core.dart';
import 'agent/tools.dart';
import 'commands/slash_commands.dart';
import 'rendering/block_renderer.dart';
import 'ui/modal.dart';

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
  final _exitCompleter = Completer<void>();

  late final SlashCommandRegistry _commands;
  String _modelName;
  final String _cwd;
  ConfirmModal? _activeModal;
  final Set<String> _autoApprovedTools = {'read_file', 'list_directory', 'grep'};

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelName,
  }) : _modelName = modelName,
       _cwd = Directory.current.path {
    _initCommands();
  }

  /// Convenience factory that creates a fully wired [App] with default
  /// tools and terminal.
  factory App.create({required String model}) {
    final terminal = Terminal();
    final layout = Layout(terminal);
    final editor = LineEditor();

    // TODO: Replace with a real LlmClient implementation.
    final agent = AgentCore(
      llm: _FakeLlmClient(),
      modelName: model,
      tools: {
        'read_file': ReadFileTool(),
        'write_file': WriteFileTool(),
        'bash': BashTool(),
        'grep': GrepTool(),
        'list_directory': ListDirectoryTool(),
      },
    );

    return App(
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      modelName: model,
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

    _render();

    try {
      await _exitCompleter.future;
    } finally {
      // Stop all event sources before touching terminal state.
      await termSub.cancel();
      await appSub.cancel();
      await _agentSub?.cancel();
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
        final buf = StringBuffer('Available commands:\n');
        for (final cmd in _commands.commands) {
          final aliases = cmd.aliases.isNotEmpty
              ? ' (${cmd.aliases.map((a) => '/$a').join(', ')})'
              : '';
          buf.writeln('  /${cmd.name}$aliases — ${cmd.description}');
        }
        buf.writeln('\nKeybindings:');
        buf.writeln('  Ctrl+C     Cancel / Exit');
        buf.writeln('  Up/Down    History navigation');
        buf.writeln('  Ctrl+U     Clear line');
        buf.writeln('  Ctrl+W     Delete word');
        buf.writeln('  Ctrl+K     Kill to end of line');
        buf.writeln('  Ctrl+A     Move to start');
        buf.writeln('  Ctrl+E     Move to end');
        buf.writeln('  PageUp/Dn  Scroll output');
        return buf.toString();
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
        _modelName = args.join(' ');
        return 'Model set to: $_modelName';
      },
    ));

    _commands.register(SlashCommand(
      name: 'tokens',
      description: 'Show token usage',
      execute: (_) => 'Total tokens used: ${agent.tokenCount}',
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
  }

  // ── Terminal event handling ─────────────────────────────────────────────

  void _handleTerminalEvent(TerminalEvent event) {
    switch (event) {
      case CharEvent() || KeyEvent():
        // Modal gets first crack at input.
        if (_activeModal != null && !_activeModal!.isComplete) {
          if (_activeModal!.handleEvent(event)) {
            _render();
            return;
          }
        }

        // Scroll handling — works in all modes.
        if (event case KeyEvent(key: Key.pageUp)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _scrollOffset += viewportHeight ~/ 2;
          _render();
          return;
        }
        if (event case KeyEvent(key: Key.pageDown)) {
          final viewportHeight = layout.outputBottom - layout.outputTop + 1;
          _scrollOffset = (_scrollOffset - viewportHeight ~/ 2).clamp(0, _scrollOffset);
          _render();
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

        // Normal idle mode — full input handling.
        final action = editor.handle(event);
        switch (action) {
          case InputAction.submit:
            final text = editor.lastSubmitted;
            if (text.isNotEmpty) {
              _events.add(UserSubmit(text));
            }
          case InputAction.interrupt:
            requestExit();
          case InputAction.changed:
            _render();
          default:
            break;
        }

      case ResizeEvent():
        layout.apply();
        _render();

      case MouseEvent(:final isScroll, :final isScrollUp):
        if (isScroll) {
          if (isScrollUp) {
            _scrollOffset += 3;
          } else {
            _scrollOffset = (_scrollOffset - 3).clamp(0, _scrollOffset);
          }
          _render();
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
          _startAgent(text);
        }

      case UserCancel():
        _cancelAgent();

      case UserScroll():
        // TODO: Implement viewport scrolling.
        break;

      case UserResize():
        layout.apply();
        _render();
    }
  }

  // ── Agent interaction ──────────────────────────────────────────────────

  void _startAgent(String userMessage) {
    _blocks.add(_ConversationEntry.user(userMessage));
    _mode = AppMode.streaming;
    _streamingText = '';
    _render();

    final stream = agent.run(userMessage);
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
        _blocks.add(_ConversationEntry.toolCall(call.name, call.arguments));

        // Auto-approve safe tools.
        if (_autoApprovedTools.contains(call.name)) {
          _mode = AppMode.toolRunning;
          _render();
          agent.executeTool(call).then((result) {
            agent.completeToolCall(result);
          });
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
              agent.executeTool(call).then((result) {
                agent.completeToolCall(result);
              });
            case 2: // Always
              _autoApprovedTools.add(call.name);
              _mode = AppMode.toolRunning;
              _render();
              agent.executeTool(call).then((result) {
                agent.completeToolCall(result);
              });
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

  void _cancelAgent() {
    _agentSub?.cancel();
    _mode = AppMode.idle;
    if (_streamingText.isNotEmpty) {
      _blocks.add(_ConversationEntry.assistant('$_streamingText\n[cancelled]'));
      _streamingText = '';
    }
    _render();
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  void _render() {
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
        _EntryKind.system => renderer.renderSystem(block.text),
      };
      outputLines.addAll(text.split('\n'));
      outputLines.add(''); // blank line between blocks
    }

    // If streaming, add the partial text.
    if (_streamingText.isNotEmpty) {
      outputLines.addAll(renderer.renderAssistant(_streamingText).split('\n'));
    }

    // Trailing blank line so content doesn't butt against the status bar.
    outputLines.add('');

    // 2. Compute visible window.
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

    // Modal overlay (if active).
    if (_activeModal != null && !_activeModal!.isComplete) {
      final modalLines = _activeModal!.render(terminal.columns);
      final outputHeight = layout.outputBottom - layout.outputTop + 1;
      final startRow = layout.outputTop +
          ((outputHeight - modalLines.length) ~/ 2).clamp(0, outputHeight);
      for (var i = 0; i < modalLines.length && startRow + i <= layout.outputBottom; i++) {
        terminal.moveTo(startRow + i, 1);
        terminal.clearLine();
        terminal.write(modalLines[i]);
      }
    }

    // 3. Status bar.
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

    // 4. Input area — MUST be last so cursor lands here.
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

enum _EntryKind { user, assistant, toolCall, toolResult, error, system }

class _ConversationEntry {
  final _EntryKind kind;
  final String text;
  final Map<String, dynamic>? args;

  _ConversationEntry._(this.kind, this.text, {this.args});

  factory _ConversationEntry.user(String text) =>
      _ConversationEntry._(_EntryKind.user, text);

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

  factory _ConversationEntry.system(String text) =>
      _ConversationEntry._(_EntryKind.system, text);
}

// ---------------------------------------------------------------------------
// Fake LLM client for TUI development
// ---------------------------------------------------------------------------

class _FakeLlmClient extends LlmClient {
  final _random = Random();
  int _callCount = 0;

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    _callCount++;
    final lastMsg = messages.lastWhere((m) => m.role == Role.user,
        orElse: () => Message.user(''));

    // After a tool result, emit a follow-up response about it.
    final lastIsToolResult =
        messages.isNotEmpty && messages.last.role == Role.toolResult;
    if (lastIsToolResult) {
      yield* _streamText(
          'Got the tool result. Let me analyze that...\n\n'
          'Looks like everything worked as expected. '
          'The output shows **${_random.nextInt(42) + 1} items** processed.\n\n'
          '> Tool execution complete.');
      yield _usage(80, 60);
      return;
    }

    // Pick a scenario based on the user's message and some randomness.
    final text = (lastMsg.text ?? '').toLowerCase();
    final scenario = _pickScenario(text, tools);

    switch (scenario) {
      case _Scenario.greeting:
        yield* _streamText(
            'Hello! I\'m **Glue**, your coding agent.\n'
            '\n'
            '## What I can do\n'
            '\n'
            '- Read and write files\n'
            '- Run shell commands\n'
            '- Search through code with `grep`\n'
            '\n'
            'How can I help you today?');
        yield _usage(30, 50);

      case _Scenario.codeAnswer:
        yield* _streamText(
            'Sure, here\'s how you\'d do that:\n'
            '\n'
            '```dart\n'
            'import \'dart:io\';\n'
            '\n'
            'Future<void> main() async {\n'
            '  final file = File(\'data.json\');\n'
            '  final contents = await file.readAsString();\n'
            '  print(\'Read \${contents.length} bytes\');\n'
            '}\n'
            '```\n'
            '\n'
            'This reads a file asynchronously and prints its size. '
            'You could also use `File.readAsLines()` for line-by-line processing.');
        yield _usage(50, 90);

      case _Scenario.readFile:
        yield* _streamText('Let me take a look at that file.');
        yield ToolCallDelta(ToolCall(
          id: 'call_${_callCount}_1',
          name: 'read_file',
          arguments: {'path': 'pubspec.yaml'},
          description: 'Reading pubspec.yaml',
        ));
        yield _usage(40, 30);

      case _Scenario.bashCommand:
        yield* _streamText(
            'I\'ll run that command for you.\n');
        yield ToolCallDelta(ToolCall(
          id: 'call_${_callCount}_1',
          name: 'bash',
          arguments: {'command': 'echo "Hello from Glue!" && date'},
          description: 'Running shell command',
        ));
        yield _usage(35, 25);

      case _Scenario.multiTool:
        yield* _streamText(
            'Let me check the project structure first.');
        yield ToolCallDelta(ToolCall(
          id: 'call_${_callCount}_1',
          name: 'list_directory',
          arguments: {'path': '.'},
          description: 'Listing current directory',
        ));
        yield _usage(60, 40);

      case _Scenario.grepSearch:
        yield* _streamText(
            'I\'ll search for that pattern in the codebase.');
        yield ToolCallDelta(ToolCall(
          id: 'call_${_callCount}_1',
          name: 'grep',
          arguments: {'pattern': 'TODO', 'path': '.'},
          description: 'Searching for TODOs',
        ));
        yield _usage(45, 30);

      case _Scenario.writeFile:
        yield* _streamText(
            'I\'ll create that file for you.\n');
        yield ToolCallDelta(ToolCall(
          id: 'call_${_callCount}_1',
          name: 'write_file',
          arguments: {
            'path': '/tmp/glue-test.txt',
            'content': 'Hello from Glue!\nGenerated at: ${DateTime.now()}\n',
          },
          description: 'Writing test file',
        ));
        yield _usage(40, 35);

      case _Scenario.markdownShowcase:
        yield* _streamText(
            '# Markdown Showcase\n'
            '\n'
            'Here\'s what I can render:\n'
            '\n'
            '## Text Styles\n'
            '\n'
            'This is **bold**, this is *italic*, and this is `inline code`.\n'
            '\n'
            '## Lists\n'
            '\n'
            '- First item\n'
            '- Second item with **emphasis**\n'
            '- Third item with `code`\n'
            '\n'
            '1. Ordered one\n'
            '2. Ordered two\n'
            '3. Ordered three\n'
            '\n'
            '## Code Block\n'
            '\n'
            '```python\n'
            'def fibonacci(n):\n'
            '    if n <= 1:\n'
            '        return n\n'
            '    return fibonacci(n-1) + fibonacci(n-2)\n'
            '\n'
            'print(fibonacci(10))  # 55\n'
            '```\n'
            '\n'
            '## Blockquote\n'
            '\n'
            '> The best way to predict the future\n'
            '> is to *invent* it. — **Alan Kay**\n'
            '\n'
            'That\'s most of the markdown I support!');
        yield _usage(30, 200);

      case _Scenario.longResponse:
        final buf = StringBuffer('Here\'s a detailed analysis:\n\n');
        for (var i = 1; i <= 30; i++) {
          buf.writeln('$i. Item number $i — '
              '${_randomPhrase()} with some additional detail '
              'that makes this line longer for wrapping purposes.');
        }
        buf.write(
            '\n> This was a long response to test scrolling behavior.');
        yield* _streamText(buf.toString());
        yield _usage(50, 300);

      case _Scenario.error:
        yield* _streamText('I encountered an issue trying to process that.');
        yield _usage(20, 15);
        throw Exception(
            'Simulated LLM error: rate limit exceeded (fake)');
    }
  }

  _Scenario _pickScenario(String text, List<Tool>? tools) {
    // Keyword matching for deterministic-ish behavior.
    if (text.contains('hello') || text.contains('hi') || text.isEmpty) {
      return _Scenario.greeting;
    }
    if (text.contains('markdown') || text.contains('render')) {
      return _Scenario.markdownShowcase;
    }
    if (text.contains('read') || text.contains('show') || text.contains('cat')) {
      return _Scenario.readFile;
    }
    if (text.contains('run') || text.contains('exec') || text.contains('bash')) {
      return _Scenario.bashCommand;
    }
    if (text.contains('list') || text.contains('ls') || text.contains('dir')) {
      return _Scenario.multiTool;
    }
    if (text.contains('search') || text.contains('find') || text.contains('grep')) {
      return _Scenario.grepSearch;
    }
    if (text.contains('write') || text.contains('create') || text.contains('save')) {
      return _Scenario.writeFile;
    }
    if (text.contains('long') || text.contains('scroll') || text.contains('many')) {
      return _Scenario.longResponse;
    }
    if (text.contains('error') || text.contains('fail') || text.contains('crash')) {
      return _Scenario.error;
    }
    if (text.contains('code') || text.contains('how') || text.contains('example')) {
      return _Scenario.codeAnswer;
    }

    // Random pick for anything else.
    const scenarios = _Scenario.values;
    return scenarios[_random.nextInt(scenarios.length)];
  }

  Stream<LlmChunk> _streamText(String text) async* {
    // Stream in small chunks with varying speed for realism.
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final word = i == 0 ? words[i] : ' ${words[i]}';
      yield TextDelta(word);
      await Future.delayed(Duration(
          milliseconds: 15 + _random.nextInt(35)));
    }
  }

  UsageInfo _usage(int input, int output) =>
      UsageInfo(inputTokens: input, outputTokens: output);

  String _randomPhrase() {
    const phrases = [
      'analyzed the dependency graph',
      'checked for potential issues',
      'verified the implementation',
      'found an interesting pattern',
      'noted a possible optimization',
      'reviewed the test coverage',
      'examined the error handling',
      'validated the API contract',
    ];
    return phrases[_random.nextInt(phrases.length)];
  }
}

enum _Scenario {
  greeting,
  codeAnswer,
  readFile,
  bashCommand,
  multiTool,
  grepSearch,
  writeFile,
  markdownShowcase,
  longResponse,
  error,
}
