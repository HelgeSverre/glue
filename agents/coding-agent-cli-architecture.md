# Coding Agent CLI Architecture in Dart

## The Big Picture

Every coding agent CLI (Claude Code, OpenCode, Codex, Gemini CLI, etc.) shares the same fundamental architecture. Strip away the branding and you find:

```
┌─────────────────────────────────────────────────────┐
│                    TUI Shell                         │
│  ┌──────────────────────────────────────────────┐   │
│  │  Output Viewport (scrollable, streaming)      │   │
│  │  - Markdown rendered blocks                   │   │
│  │  - Tool call/result cards                     │   │
│  │  - Diff views                                 │   │
│  │  - Streaming LLM text                         │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │  Status Bar (spinner, model, token count)     │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │  Input Area (multi-line editor, completions)  │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │  Modal Layer (confirmations, file pickers)    │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
         │                           ▲
         ▼                           │
┌─────────────────────────────────────────────────────┐
│                 Agent Core                           │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │  LLM    │  │  Tool    │  │  Conversation    │   │
│  │ Client  │◄─┤ Executor ├──┤  Manager         │   │
│  │(stream) │  │          │  │  (history+state)  │   │
│  └─────────┘  └──────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────┘
```

The critical insight: **the TUI and Agent Core run on separate async "tracks"**. The UI is always responsive because it's event-driven, while the agent loop runs as a background stream that pushes state updates the UI subscribes to.

---

## 1. Raw Terminal Control — The Foundation

Everything starts with taking over the terminal. You need raw mode to intercept every keypress before the terminal processes it.

```dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';

/// Low-level terminal controller.
/// This is the absolute bottom of the stack — everything else builds on this.
class Terminal {
  final _inputController = StreamController<TerminalEvent>.broadcast();
  late final int _originalLineMode;
  bool _isRaw = false;

  Stream<TerminalEvent> get events => _inputController.stream;

  int get columns => stdout.terminalColumns;
  int get rows => stdout.terminalLines;

  /// Enter raw mode — we now own every byte from stdin
  void enableRawMode() {
    stdin.echoMode = false;
    stdin.lineMode = false;
    _isRaw = true;

    // Listen to raw bytes and parse them into semantic events
    stdin.listen(_parseInput);

    // Also listen for terminal resize (SIGWINCH)
    ProcessSignal.sigwinch.watch().listen((_) {
      _inputController.add(ResizeEvent(columns, rows));
    });
  }

  void disableRawMode() {
    stdin.echoMode = true;
    stdin.lineMode = true;
    _isRaw = false;
  }

  /// Parse raw byte sequences into semantic key events.
  /// This is where you handle escape sequences (arrows, ctrl combos, etc.)
  void _parseInput(List<int> bytes) {
    var i = 0;
    while (i < bytes.length) {
      if (bytes[i] == 0x1b) {
        // Escape sequence
        if (i + 1 < bytes.length && bytes[i + 1] == 0x5b) {
          // CSI sequence: ESC [
          final parsed = _parseCsi(bytes, i + 2);
          _inputController.add(parsed.event);
          i = parsed.nextIndex;
          continue;
        }
        _inputController.add(KeyEvent(Key.escape));
        i++;
      } else if (bytes[i] < 32) {
        // Control characters
        _inputController.add(_controlChar(bytes[i]));
        i++;
      } else {
        // Regular UTF-8 text — could be multi-byte
        final (char, len) = _decodeUtf8Char(bytes, i);
        _inputController.add(CharEvent(char));
        i += len;
      }
    }
  }

  KeyEvent _controlChar(int byte) => switch (byte) {
    0x01 => KeyEvent(Key.home),    // Ctrl+A
    0x03 => KeyEvent(Key.ctrlC),   // Ctrl+C — interrupt
    0x04 => KeyEvent(Key.ctrlD),   // Ctrl+D — EOF
    0x05 => KeyEvent(Key.end),     // Ctrl+E
    0x0d => KeyEvent(Key.enter),   // Enter
    0x7f => KeyEvent(Key.backspace),
    0x09 => KeyEvent(Key.tab),
    _    => KeyEvent(Key.unknown, ctrl: true, charCode: byte),
  };

  // ANSI output helpers
  void write(String s) => stdout.write(s);
  void moveTo(int row, int col) => write('\x1b[${row};${col}H');
  void clearScreen() => write('\x1b[2J');
  void clearLine() => write('\x1b[2K');
  void hideCursor() => write('\x1b[?25l');
  void showCursor() => write('\x1b[?25h');
  void saveCursor() => write('\x1b7');
  void restoreCursor() => write('\x1b8');
  void enableAltScreen() => write('\x1b[?1049h');
  void disableAltScreen() => write('\x1b[?1049l');
  void enableMouse() => write('\x1b[?1000h\x1b[?1006h');
  void disableMouse() => write('\x1b[?1000l\x1b[?1006l');
  void setScrollRegion(int top, int bottom) => write('\x1b[$top;${bottom}r');

  // Styled output
  void writeStyled(String text, {AnsiStyle? style}) {
    if (style != null) {
      write('${style.open}$text${style.close}');
    } else {
      write(text);
    }
  }

  // ... CSI parser, UTF-8 decoder omitted for brevity
}

// Event types
enum Key { escape, enter, backspace, tab, up, down, left, right,
           home, end, pageUp, pageDown, ctrlC, ctrlD, ctrlL,
           ctrlK, ctrlU, ctrlW, unknown }

sealed class TerminalEvent {}
class KeyEvent extends TerminalEvent { final Key key; final bool ctrl; final int? charCode; KeyEvent(this.key, {this.ctrl = false, this.charCode}); }
class CharEvent extends TerminalEvent { final String char; CharEvent(this.char); }
class ResizeEvent extends TerminalEvent { final int cols; final int rows; ResizeEvent(this.cols, this.rows); }
class MouseEvent extends TerminalEvent { final int x, y, button; MouseEvent(this.x, this.y, this.button); }

class AnsiStyle {
  final String open;
  final String close;
  const AnsiStyle(this.open, this.close);
  static const bold = AnsiStyle('\x1b[1m', '\x1b[22m');
  static const dim = AnsiStyle('\x1b[2m', '\x1b[22m');
  static const italic = AnsiStyle('\x1b[3m', '\x1b[23m');
  static const underline = AnsiStyle('\x1b[4m', '\x1b[24m');
  static const red = AnsiStyle('\x1b[31m', '\x1b[39m');
  static const green = AnsiStyle('\x1b[32m', '\x1b[39m');
  static const yellow = AnsiStyle('\x1b[33m', '\x1b[39m');
  static const blue = AnsiStyle('\x1b[34m', '\x1b[39m');
  static const cyan = AnsiStyle('\x1b[36m', '\x1b[39m');
  static const gray = AnsiStyle('\x1b[90m', '\x1b[39m');
}
```

**Key insight**: Dart's `stdin` in raw mode gives you a `Stream<List<int>>` — raw bytes. You must parse ANSI escape sequences yourself (or use a library). This is the same across all these tools — they all drop into raw mode and take over input.

---

## 2. The Rendering Model — Virtual Terminal Buffer

The tools don't just `print()` to the screen. They maintain a **virtual buffer** and diff it against the previous frame, only writing the changes. This prevents flicker and is essential for smooth streaming output.

```dart
/// A cell in the terminal grid
class Cell {
  String char;
  AnsiStyle? style;
  Cell(this.char, {this.style});

  @override
  bool operator ==(Object other) =>
    other is Cell && other.char == char && other.style == style;

  @override
  int get hashCode => Object.hash(char, style);
}

/// Virtual terminal buffer with diff-based rendering.
/// Think of this like a virtual DOM but for terminal cells.
class ScreenBuffer {
  final Terminal _terminal;
  late List<List<Cell>> _current;
  late List<List<Cell>> _previous;
  int _width;
  int _height;

  ScreenBuffer(this._terminal)
    : _width = _terminal.columns,
      _height = _terminal.rows {
    _current = _makeGrid(_width, _height);
    _previous = _makeGrid(_width, _height);
  }

  List<List<Cell>> _makeGrid(int w, int h) =>
    List.generate(h, (_) => List.generate(w, (_) => Cell(' ')));

  /// Write text into the buffer at a position (doesn't touch the real terminal yet)
  void writeAt(int row, int col, String text, {AnsiStyle? style}) {
    if (row < 0 || row >= _height) return;
    for (var i = 0; i < text.length && col + i < _width; i++) {
      _current[row][col + i] = Cell(text[i], style: style);
    }
  }

  /// Fill an entire row
  void fillRow(int row, String text, {AnsiStyle? style, int startCol = 0}) {
    writeAt(row, startCol, text.padRight(_width - startCol), style: style);
  }

  /// Clear the buffer for next frame
  void clear() {
    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        _current[r][c] = Cell(' ');
      }
    }
  }

  /// Flush only the changed cells to the real terminal.
  /// This is the key to flicker-free rendering.
  void flush() {
    _terminal.hideCursor();
    final buf = StringBuffer();

    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        if (_current[r][c] != _previous[r][c]) {
          buf.write('\x1b[${r + 1};${c + 1}H'); // move cursor
          final cell = _current[r][c];
          if (cell.style != null) {
            buf.write('${cell.style!.open}${cell.char}${cell.style!.close}');
          } else {
            buf.write(cell.char);
          }
        }
      }
    }

    if (buf.isNotEmpty) {
      _terminal.write(buf.toString());
    }

    _terminal.showCursor();

    // Swap buffers
    final temp = _previous;
    _previous = _current;
    _current = temp;
    // Clear current for next frame
    for (var r = 0; r < _height; r++) {
      for (var c = 0; c < _width; c++) {
        _current[r][c] = Cell(' ');
      }
    }
  }

  void resize(int width, int height) {
    _width = width;
    _height = height;
    _current = _makeGrid(width, height);
    _previous = _makeGrid(width, height);
  }
}
```

**However** — most of these tools actually use a simpler approach for the main output: **region-based rendering** rather than full cell-grid buffering. The output area scrolls naturally using the terminal's own scroll buffer, while fixed UI elements (status bar, input area) are painted at fixed positions using ANSI escape codes. This hybrid approach is what makes them feel snappy.

---

## 3. The Layout System — Regions & Zones

```dart
/// The screen is divided into zones. Each zone owns a vertical region.
/// This is the layout engine that all coding agent CLIs use.
///
/// ┌──────────────────────────────┐
/// │  Output Zone (scrollable)    │ ← uses terminal's native scroll
/// │  ...                         │
/// │  ...                         │
/// ├──────────────────────────────┤
/// │  Status Bar (1 line, fixed)  │ ← painted at fixed row
/// ├──────────────────────────────┤
/// │  Input Zone (1-N lines)      │ ← painted at bottom
/// └──────────────────────────────┘
///
/// The trick: set a scroll region (ANSI `CSI top;bottom r`) so that
/// output scrolls without disturbing the status bar and input area.

class Layout {
  final Terminal terminal;

  int get outputTop => 1;
  int get outputBottom => terminal.rows - _statusHeight - _inputHeight;
  int get statusRow => terminal.rows - _inputHeight;
  int get inputTop => terminal.rows - _inputHeight + 1;
  int get inputBottom => terminal.rows;

  int _statusHeight = 1;
  int _inputHeight = 1; // grows with multi-line input

  Layout(this.terminal);

  /// Configure the terminal's hardware scroll region.
  /// Text printed inside this region scrolls; text outside stays put.
  void apply() {
    terminal.setScrollRegion(outputTop, outputBottom);
  }

  /// Update input height (for multi-line editing)
  void setInputHeight(int lines) {
    _inputHeight = lines.clamp(1, terminal.rows ~/ 3);
    apply();
  }

  /// Write to the output zone (scrolls naturally)
  void writeOutput(String text) {
    terminal.saveCursor();
    terminal.moveTo(outputBottom, 1);
    terminal.write('\n$text'); // Scrolls within the region
    terminal.restoreCursor();
  }

  /// Paint the status bar (fixed position, repainted on every update)
  void paintStatus(String left, String right) {
    terminal.saveCursor();
    terminal.moveTo(statusRow, 1);
    terminal.clearLine();

    final padding = terminal.columns - left.length - right.length;
    terminal.writeStyled(
      '$left${' ' * padding.clamp(0, 999)}$right',
      style: const AnsiStyle('\x1b[7m', '\x1b[27m'), // inverse video
    );

    terminal.restoreCursor();
  }

  /// Paint the input area
  void paintInput(String prompt, String text, int cursorPos) {
    terminal.saveCursor();
    terminal.moveTo(inputTop, 1);
    terminal.clearLine();
    terminal.writeStyled(prompt, style: AnsiStyle.cyan);
    terminal.write(text);

    // Position cursor
    final cursorCol = prompt.length + cursorPos + 1;
    terminal.moveTo(inputTop, cursorCol);
    terminal.restoreCursor();
  }
}
```

**This scroll region trick is the core UX magic.** It's what lets the LLM stream output that scrolls up naturally while the input area stays pinned at the bottom. Every coding agent CLI does this (or approximates it with full-screen redraws).

---

## 4. The Input Editor — Line Editing with History

```dart
/// A readline-style line editor with history, word movement, etc.
/// This is the input box at the bottom of the TUI.
class LineEditor {
  String _buffer = '';
  int _cursor = 0;
  final List<String> _history = [];
  int _historyIndex = -1;
  String _savedBuffer = '';

  String get text => _buffer;
  int get cursor => _cursor;
  bool get isEmpty => _buffer.isEmpty;

  /// Process a terminal event. Returns an action or null.
  InputAction? handle(TerminalEvent event) {
    return switch (event) {
      CharEvent(:final char) => _insert(char),
      KeyEvent(:final key) => switch (key) {
        Key.enter     => _submit(),
        Key.backspace => _backspace(),
        Key.left      => _moveLeft(),
        Key.right     => _moveRight(),
        Key.home      => _moveHome(),
        Key.end       => _moveEnd(),
        Key.up        => _historyPrev(),
        Key.down      => _historyNext(),
        Key.ctrlU     => _clearLine(),
        Key.ctrlW     => _deleteWord(),
        Key.ctrlC     => InputAction.interrupt,
        Key.ctrlD     => isEmpty ? InputAction.eof : null,
        Key.tab       => InputAction.requestCompletion,
        Key.escape    => InputAction.escape,
        _             => null,
      },
      _ => null,
    };
  }

  InputAction? _insert(String char) {
    _buffer = _buffer.substring(0, _cursor) + char + _buffer.substring(_cursor);
    _cursor += char.length;
    return InputAction.changed;
  }

  InputAction? _submit() {
    final text = _buffer;
    if (text.isNotEmpty) {
      _history.add(text);
    }
    _buffer = '';
    _cursor = 0;
    _historyIndex = -1;
    return InputAction.submit;
  }

  InputAction? _backspace() {
    if (_cursor > 0) {
      _buffer = _buffer.substring(0, _cursor - 1) + _buffer.substring(_cursor);
      _cursor--;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveLeft() { if (_cursor > 0) { _cursor--; return InputAction.changed; } return null; }
  InputAction? _moveRight() { if (_cursor < _buffer.length) { _cursor++; return InputAction.changed; } return null; }
  InputAction? _moveHome() { _cursor = 0; return InputAction.changed; }
  InputAction? _moveEnd() { _cursor = _buffer.length; return InputAction.changed; }

  InputAction? _clearLine() {
    _buffer = _buffer.substring(_cursor);
    _cursor = 0;
    return InputAction.changed;
  }

  InputAction? _deleteWord() {
    if (_cursor == 0) return null;
    var i = _cursor - 1;
    while (i > 0 && _buffer[i] == ' ') i--;
    while (i > 0 && _buffer[i - 1] != ' ') i--;
    _buffer = _buffer.substring(0, i) + _buffer.substring(_cursor);
    _cursor = i;
    return InputAction.changed;
  }

  InputAction? _historyPrev() {
    if (_history.isEmpty) return null;
    if (_historyIndex == -1) _savedBuffer = _buffer;
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _buffer = _history[_history.length - 1 - _historyIndex];
      _cursor = _buffer.length;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _historyNext() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _buffer = _history[_history.length - 1 - _historyIndex];
      _cursor = _buffer.length;
      return InputAction.changed;
    } else if (_historyIndex == 0) {
      _historyIndex = -1;
      _buffer = _savedBuffer;
      _cursor = _buffer.length;
      return InputAction.changed;
    }
    return null;
  }

  void clear() {
    _buffer = '';
    _cursor = 0;
  }
}

enum InputAction {
  changed,
  submit,
  interrupt,
  eof,
  escape,
  requestCompletion,
}
```

---

## 5. The Modal System — Layered UI State

This is how confirmations ("Allow file write?"), tool approval, and picker UIs work. A modal captures input focus temporarily.

```dart
/// Modal system — a stack of UI layers that intercept input.
/// When a modal is active, it gets first crack at all input events.
///
/// Think of it like a Stack<Widget> in Flutter but for terminal UI.
class ModalStack {
  final List<Modal> _stack = [];

  bool get hasModals => _stack.isNotEmpty;
  Modal? get active => _stack.lastOrNull;

  void push(Modal modal) => _stack.add(modal);

  void pop() {
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  /// Returns true if the modal consumed the event
  bool handleEvent(TerminalEvent event) {
    if (_stack.isEmpty) return false;
    return _stack.last.handleEvent(event);
  }

  /// Render all modals (bottom to top)
  void render(ScreenBuffer buffer) {
    for (final modal in _stack) {
      modal.render(buffer);
    }
  }
}

/// Base class for modals
abstract class Modal {
  bool handleEvent(TerminalEvent event);
  void render(ScreenBuffer buffer);
}

/// Confirmation modal — "Allow tool X? [Y/n/always]"
/// This is what every coding agent shows when the model wants to run a tool.
class ConfirmModal extends Modal {
  final String title;
  final String message;
  final List<ConfirmOption> options;
  final Completer<ConfirmOption> _completer = Completer();
  int _selected = 0;

  ConfirmModal({
    required this.title,
    required this.message,
    required this.options,
  });

  Future<ConfirmOption> get result => _completer.future;

  @override
  bool handleEvent(TerminalEvent event) {
    switch (event) {
      case KeyEvent(key: Key.left):
        _selected = (_selected - 1).clamp(0, options.length - 1);
        return true;
      case KeyEvent(key: Key.right):
        _selected = (_selected + 1).clamp(0, options.length - 1);
        return true;
      case KeyEvent(key: Key.enter):
        _completer.complete(options[_selected]);
        return true;
      case CharEvent(char: final c):
        // Hotkey matching — 'y', 'n', 'a' etc.
        final idx = options.indexWhere(
          (o) => o.hotkey.toLowerCase() == c.toLowerCase(),
        );
        if (idx != -1) {
          _completer.complete(options[idx]);
          return true;
        }
        return true; // Consume all input while modal is open
      default:
        return true; // Swallow everything
    }
  }

  @override
  void render(ScreenBuffer buffer) {
    // Draw a box in the center of the screen
    // ... box drawing, title, message, option buttons ...
    // The selected option is highlighted
  }
}

class ConfirmOption {
  final String label;
  final String hotkey;
  final dynamic value;
  const ConfirmOption(this.label, this.hotkey, this.value);

  static const yes = ConfirmOption('Yes', 'y', true);
  static const no = ConfirmOption('No', 'n', false);
  static const always = ConfirmOption('Always', 'a', 'always');
}
```

---

## 6. The Async Architecture — The Heart of "Interact While Working"

**This is the most important architectural piece.** The reason you can type while the LLM is streaming is because of a careful async event architecture.

```dart
/// The application state machine.
/// This is the central coordinator — it's an event loop, not a call stack.
///
/// Key insight: we NEVER block. Everything is streams and futures.
/// The UI renders based on state snapshots, not by waiting for operations.

enum AppMode {
  idle,          // Waiting for user input
  streaming,     // LLM is generating (user can still type, scroll, cancel)
  toolRunning,   // A tool is executing
  confirming,    // Waiting for user to approve something
}

/// Events that flow through the system
sealed class AppEvent {}

// User events
class UserSubmit extends AppEvent { final String text; UserSubmit(this.text); }
class UserCancel extends AppEvent {}
class UserScroll extends AppEvent { final int delta; UserScroll(this.delta); }
class UserResize extends AppEvent { final int cols, rows; UserResize(this.cols, this.rows); }

// Agent events
class AgentTextDelta extends AppEvent { final String delta; AgentTextDelta(this.delta); }
class AgentToolCall extends AppEvent { final ToolCall call; AgentToolCall(this.call); }
class AgentToolResult extends AppEvent { final ToolResult result; AgentToolResult(this.result); }
class AgentDone extends AppEvent {}
class AgentError extends AppEvent { final Object error; AgentError(this.error); }

/// The main application controller
class App {
  final Terminal terminal;
  final Layout layout;
  final LineEditor editor;
  final ModalStack modals;
  final AgentCore agent;
  final _events = StreamController<AppEvent>.broadcast();

  AppMode _mode = AppMode.idle;
  final List<ConversationBlock> _blocks = [];
  String _streamingText = '';
  StreamSubscription? _agentSub;

  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.modals,
    required this.agent,
  });

  Future<void> run() async {
    terminal.enableRawMode();
    terminal.enableAltScreen();
    layout.apply();

    // THE MAGIC: Two independent streams merged into one event loop.
    // Input events and agent events are processed identically.
    terminal.events.listen(_handleTerminalEvent);
    _events.stream.listen(_handleAppEvent);

    _render(); // Initial render

    // Wait for exit signal
    await _exitCompleter.future;

    terminal.disableAltScreen();
    terminal.disableRawMode();
  }

  final _exitCompleter = Completer<void>();

  void _handleTerminalEvent(TerminalEvent event) {
    // Modal gets first crack
    if (modals.handleEvent(event)) {
      _render();
      return;
    }

    switch (event) {
      case CharEvent() || KeyEvent():
        if (_mode == AppMode.streaming || _mode == AppMode.toolRunning) {
          // WHILE THE AGENT IS WORKING, input still works!
          // Special keys like Ctrl+C cancel the operation
          if (event case KeyEvent(key: Key.ctrlC)) {
            _cancelAgent();
            return;
          }
          if (event case KeyEvent(key: Key.escape)) {
            _cancelAgent();
            return;
          }
          // Other input goes to the editor (pre-typing next message)
          final action = editor.handle(event);
          if (action == InputAction.changed) _render();
          return;
        }

        // Normal idle mode — full input handling
        final action = editor.handle(event);
        switch (action) {
          case InputAction.submit:
            _events.add(UserSubmit(editor.text));
          case InputAction.interrupt:
            _exitCompleter.complete();
          case InputAction.changed:
            _render();
          default:
            break;
        }

      case ResizeEvent(:final cols, :final rows):
        layout.apply();
        _render();

      case MouseEvent(:final y):
        // Scroll events
        break;
    }
  }

  void _handleAppEvent(AppEvent event) {
    switch (event) {
      case UserSubmit(:final text):
        _startAgent(text);

      case AgentTextDelta(:final delta):
        _streamingText += delta;
        _render(); // Re-render with new streaming text

      case AgentToolCall(:final call):
        _mode = AppMode.confirming;
        _showToolConfirmation(call);

      case AgentDone():
        if (_streamingText.isNotEmpty) {
          _blocks.add(AssistantBlock(_streamingText));
          _streamingText = '';
        }
        _mode = AppMode.idle;
        _render();

      case AgentError(:final error):
        _blocks.add(ErrorBlock(error.toString()));
        _mode = AppMode.idle;
        _render();

      case UserCancel():
        _cancelAgent();

      default:
        break;
    }
  }

  void _startAgent(String userMessage) {
    _blocks.add(UserBlock(userMessage));
    _mode = AppMode.streaming;
    _streamingText = '';
    _render();

    // Start the agent as a background stream
    final stream = agent.run(userMessage);
    _agentSub = stream.listen(
      (event) => _events.add(event),
      onError: (e) => _events.add(AgentError(e)),
      onDone: () => _events.add(AgentDone()),
    );
  }

  void _cancelAgent() {
    _agentSub?.cancel();
    _mode = AppMode.idle;
    if (_streamingText.isNotEmpty) {
      _blocks.add(AssistantBlock('$_streamingText\n[cancelled]'));
      _streamingText = '';
    }
    _render();
  }

  Future<void> _showToolConfirmation(ToolCall call) async {
    final modal = ConfirmModal(
      title: 'Tool: ${call.name}',
      message: call.description,
      options: [ConfirmOption.yes, ConfirmOption.no, ConfirmOption.always],
    );
    modals.push(modal);
    _render();

    final result = await modal.result;
    modals.pop();

    if (result == ConfirmOption.yes || result == ConfirmOption.always) {
      _mode = AppMode.toolRunning;
      _render();
      // Execute the tool and feed result back to agent
      final toolResult = await agent.executeTool(call);
      _events.add(AgentToolResult(toolResult));
      // Agent continues with the result...
    } else {
      _events.add(AgentToolResult(ToolResult.denied(call.id)));
    }
  }

  /// Render the entire UI. Called on every state change.
  /// This is fast because we only update what changed.
  void _render() {
    // 1. Render conversation blocks to the output zone
    for (final block in _blocks) {
      // In reality you'd track what's already been rendered
      layout.writeOutput(block.render(terminal.columns));
    }

    // 2. If streaming, render the partial text
    if (_streamingText.isNotEmpty) {
      layout.writeOutput(_streamingText);
    }

    // 3. Status bar
    final statusLeft = switch (_mode) {
      AppMode.idle => ' Ready',
      AppMode.streaming => ' ● Generating...',
      AppMode.toolRunning => ' ⚙ Running tool...',
      AppMode.confirming => ' ? Waiting for approval',
    };
    final statusRight = 'tokens: ${agent.tokenCount} ';
    layout.paintStatus(statusLeft, statusRight);

    // 4. Input area
    final prompt = switch (_mode) {
      AppMode.idle => '❯ ',
      _ => '  ',  // Dimmed prompt while agent is working
    };
    layout.paintInput(prompt, editor.text, editor.cursor);

    // 5. Modals on top
    // modals.render(screenBuffer);
  }
}
```

**The async architecture in a nutshell:**

```
Terminal stdin ──stream──► Terminal.events ──► App._handleTerminalEvent()
                                                      │
                                                      ▼
                                              _events (StreamController)
                                                      │
Agent.run() ──stream──────────────────────────────────►│
                                                      │
                                                      ▼
                                            App._handleAppEvent()
                                                      │
                                                      ▼
                                                  _render()
```

Both input and agent output flow into the same event stream. Rendering happens after every event. There's **never** a blocking wait — Dart's event loop handles the concurrency.

---

## 7. The Agent Core — LLM + Tool Loop

```dart
/// The agent core handles the LLM interaction loop.
/// This runs independently from the UI — it just emits events.
class AgentCore {
  final LlmClient llm;
  final Map<String, Tool> tools;
  final List<Message> _conversation = [];
  int tokenCount = 0;

  AgentCore({required this.llm, required this.tools});

  /// Run a user message through the agent loop.
  /// Returns a stream of events that the UI subscribes to.
  ///
  /// The agentic loop:
  /// 1. Send messages to LLM
  /// 2. Stream back text and/or tool calls
  /// 3. If tool calls: execute them, add results, go to 1
  /// 4. If no tool calls: done
  Stream<AppEvent> run(String userMessage) async* {
    _conversation.add(Message.user(userMessage));

    while (true) {
      final assistantText = StringBuffer();
      final toolCalls = <ToolCall>[];

      // Stream the LLM response
      await for (final chunk in llm.stream(_conversation, tools: tools.values.toList())) {
        switch (chunk) {
          case TextDelta(:final text):
            assistantText.write(text);
            yield AgentTextDelta(text);

          case ToolCallDelta(:final toolCall):
            toolCalls.add(toolCall);
            yield AgentToolCall(toolCall);

          case UsageInfo(:final tokens):
            tokenCount += tokens;
        }
      }

      // Add the assistant's response to conversation history
      _conversation.add(Message.assistant(
        text: assistantText.toString(),
        toolCalls: toolCalls,
      ));

      // If no tool calls, the turn is done
      if (toolCalls.isEmpty) break;

      // Otherwise, execute tools and loop back to LLM.
      // Tool execution is managed by the App (which may show confirmations),
      // but the results flow back here via the conversation history.
      for (final call in toolCalls) {
        final result = await _waitForToolResult(call);
        _conversation.add(Message.toolResult(
          callId: call.id,
          content: result.content,
        ));
      }

      // Loop: send tool results back to LLM for the next turn
    }
  }
}

/// Abstract LLM client — wraps any provider (Anthropic, OpenAI, Google, etc.)
abstract class LlmClient {
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools});
}

sealed class LlmChunk {}
class TextDelta extends LlmChunk { final String text; TextDelta(this.text); }
class ToolCallDelta extends LlmChunk { final ToolCall toolCall; ToolCallDelta(this.toolCall); }
class UsageInfo extends LlmChunk { final int tokens; UsageInfo(this.tokens); }

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String description;
  ToolCall({required this.id, required this.name, required this.arguments, this.description = ''});
}

class ToolResult {
  final String callId;
  final String content;
  final bool success;
  ToolResult({required this.callId, required this.content, this.success = true});
  factory ToolResult.denied(String callId) =>
    ToolResult(callId: callId, content: 'User denied tool execution', success: false);
}
```

---

## 8. Streaming Output Rendering — Markdown + Syntax Highlighting

The output zone needs to render markdown-like content as it streams in. This is where it gets tricky — you're parsing incomplete markdown.

```dart
/// Incremental markdown renderer for terminal output.
/// Handles the "text is still streaming in" case gracefully.
class StreamingMarkdownRenderer {
  final int width;
  final _buffer = StringBuffer();
  bool _inCodeBlock = false;
  String? _codeLanguage;
  bool _inBold = false;

  StreamingMarkdownRenderer(this.width);

  /// Append new text from the stream and return rendered ANSI lines
  List<String> append(String delta) {
    _buffer.write(delta);
    final lines = _buffer.toString().split('\n');

    // Keep the last (possibly incomplete) line in the buffer
    _buffer.clear();
    _buffer.write(lines.removeLast());

    return lines.map(_renderLine).toList();
  }

  /// Flush remaining buffer (call when stream ends)
  List<String> flush() {
    if (_buffer.isEmpty) return [];
    final line = _renderLine(_buffer.toString());
    _buffer.clear();
    return [line];
  }

  String _renderLine(String line) {
    // Code block fences
    if (line.startsWith('```')) {
      _inCodeBlock = !_inCodeBlock;
      if (_inCodeBlock) {
        _codeLanguage = line.substring(3).trim();
        return '\x1b[90m${'─' * width}\x1b[0m'; // Horizontal rule
      } else {
        _codeLanguage = null;
        return '\x1b[90m${'─' * width}\x1b[0m';
      }
    }

    if (_inCodeBlock) {
      // Inside code block — apply syntax highlighting
      return '  \x1b[38;5;252m$line\x1b[0m'; // Light text, indented
    }

    // Headers
    if (line.startsWith('### ')) return '\x1b[1m${line.substring(4)}\x1b[0m';
    if (line.startsWith('## ')) return '\x1b[1;4m${line.substring(3)}\x1b[0m';
    if (line.startsWith('# ')) return '\x1b[1;4m${line.substring(2)}\x1b[0m';

    // Inline formatting
    line = line.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => '\x1b[1m${m[1]}\x1b[22m',
    );
    line = line.replaceAllMapped(
      RegExp(r'`(.+?)`'),
      (m) => '\x1b[36m${m[1]}\x1b[0m', // Cyan for inline code
    );

    // Word wrap
    return _wordWrap(line, width);
  }

  String _wordWrap(String text, int maxWidth) {
    // Simple word wrap (ANSI-aware version would be more complex)
    if (text.length <= maxWidth) return text;
    // ... proper implementation would track visible width vs ANSI escape width
    return text;
  }
}
```

---

## 9. Conversation Blocks — The Content Model

```dart
/// Content blocks that make up the conversation history in the UI.
/// Each block knows how to render itself for the terminal.
sealed class ConversationBlock {
  String render(int width);
}

class UserBlock extends ConversationBlock {
  final String text;
  UserBlock(this.text);

  @override
  String render(int width) {
    return '\x1b[1;36m❯\x1b[0m $text';
  }
}

class AssistantBlock extends ConversationBlock {
  final String text;
  AssistantBlock(this.text);

  @override
  String render(int width) {
    final renderer = StreamingMarkdownRenderer(width);
    final lines = renderer.append(text);
    lines.addAll(renderer.flush());
    return lines.join('\n');
  }
}

class ToolCallBlock extends ConversationBlock {
  final String toolName;
  final Map<String, dynamic> args;
  final String? result;
  final Duration? duration;

  ToolCallBlock({
    required this.toolName,
    required this.args,
    this.result,
    this.duration,
  });

  @override
  String render(int width) {
    final buf = StringBuffer();
    final dur = duration != null ? ' (${duration!.inMilliseconds}ms)' : '';

    buf.writeln('\x1b[90m┌─ ⚙ $toolName$dur ─────\x1b[0m');

    // Render args compactly
    for (final entry in args.entries) {
      final value = entry.value.toString();
      final truncated = value.length > width - 10
          ? '${value.substring(0, width - 13)}...'
          : value;
      buf.writeln('\x1b[90m│\x1b[0m  ${entry.key}: \x1b[33m$truncated\x1b[0m');
    }

    if (result != null) {
      buf.writeln('\x1b[90m├─ result ─────\x1b[0m');
      for (final line in result!.split('\n').take(10)) {
        buf.writeln('\x1b[90m│\x1b[0m  $line');
      }
    }

    buf.write('\x1b[90m└${'─' * (width - 1)}\x1b[0m');
    return buf.toString();
  }
}

class ErrorBlock extends ConversationBlock {
  final String message;
  ErrorBlock(this.message);

  @override
  String render(int width) =>
    '\x1b[31m✗ Error:\x1b[0m $message';
}

/// Diff block for file changes — shows unified diff with colors
class DiffBlock extends ConversationBlock {
  final String filename;
  final List<DiffLine> lines;

  DiffBlock({required this.filename, required this.lines});

  @override
  String render(int width) {
    final buf = StringBuffer();
    buf.writeln('\x1b[1m  $filename\x1b[0m');

    for (final line in lines) {
      switch (line.type) {
        case DiffLineType.context:
          buf.writeln('\x1b[90m  ${line.text}\x1b[0m');
        case DiffLineType.addition:
          buf.writeln('\x1b[32m+ ${line.text}\x1b[0m');
        case DiffLineType.deletion:
          buf.writeln('\x1b[31m- ${line.text}\x1b[0m');
        case DiffLineType.header:
          buf.writeln('\x1b[36m${line.text}\x1b[0m');
      }
    }

    return buf.toString();
  }
}

enum DiffLineType { context, addition, deletion, header }
class DiffLine { final DiffLineType type; final String text; DiffLine(this.type, this.text); }
```

---

## 10. Spinner / Progress Animation

```dart
/// Async spinner that runs independently of everything else.
/// Updates a single character/string at a fixed position on a timer.
class Spinner {
  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  Timer? _timer;
  int _frame = 0;
  String? _message;
  final void Function(String frame, String? message) _onTick;

  Spinner(this._onTick);

  void start([String? message]) {
    _message = message;
    _frame = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _frame = (_frame + 1) % _frames.length;
      _onTick(_frames[_frame], _message);
    });
  }

  void update(String message) => _message = message;

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

---

## 11. Putting It All Together — The Entry Point

```dart
Future<void> main(List<String> args) async {
  final terminal = Terminal();
  final layout = Layout(terminal);
  final editor = LineEditor();
  final modals = ModalStack();

  final llm = AnthropicClient(
    apiKey: Platform.environment['ANTHROPIC_API_KEY']!,
    model: 'claude-sonnet-4-20250514',
  );

  final agent = AgentCore(
    llm: llm,
    tools: {
      'read_file': ReadFileTool(),
      'write_file': WriteFileTool(),
      'run_command': RunCommandTool(),
      'search_files': SearchFilesTool(),
      'list_directory': ListDirectoryTool(),
    },
  );

  final app = App(
    terminal: terminal,
    layout: layout,
    editor: editor,
    modals: modals,
    agent: agent,
  );

  // Handle clean exit
  ProcessSignal.sigint.watch().listen((_) {
    terminal.disableAltScreen();
    terminal.disableRawMode();
    exit(0);
  });

  await app.run();
}
```

---

## Architecture Summary

| Layer | Responsibility | Async Pattern |
|-------|---------------|---------------|
| **Terminal** | Raw I/O, escape sequences, cursor control | `Stream<TerminalEvent>` |
| **Layout** | Screen zones, scroll regions | Stateless (recomputed on resize) |
| **ScreenBuffer** | Virtual cells, diff-based flush | Double buffer, sync render |
| **LineEditor** | Input editing, history | Synchronous state machine |
| **ModalStack** | Layered UI for confirmations | `Future<T>` per modal result |
| **App** | Event routing, state machine, render loop | `StreamController` event bus |
| **AgentCore** | LLM streaming, tool loop | `Stream<AppEvent>` (async generator) |
| **Renderer** | Markdown → ANSI, diffs, tool cards | Stateful incremental parser |

**The single most important principle**: the UI event loop and the agent loop are **decoupled streams** that merge into a single render cycle. Input is never blocked. The agent emits events. The app processes events and re-renders. That's the entire architecture.

### Dart-Specific Advantages

- `Stream` and `async*` generators are first-class — perfect for the streaming LLM + event architecture
- `dart:io` gives you raw `stdin`/`stdout` access without FFI
- Isolates can offload heavy parsing (syntax highlighting, large diffs) without blocking the event loop
- AOT compilation (`dart compile exe`) gives you a single fast binary — same deployment story as Go-based tools

### What Real Tools Use (for reference)

| Tool | Language | TUI Framework |
|------|----------|---------------|
| Claude Code | TypeScript | Ink (React for terminals) |
| OpenCode | Go | Bubble Tea (Elm architecture) |
| Codex CLI | TypeScript | Ink |
| Gemini CLI | TypeScript | Ink |
| Aider | Python | prompt_toolkit |
| Roo Code | TypeScript | VS Code extension API |

The Dart equivalent ecosystem is thinner — you'd build most of this from scratch (or port concepts from Bubble Tea, which is the cleanest architecture match since it's Elm-inspired and your Token editor already uses Elm Architecture).
