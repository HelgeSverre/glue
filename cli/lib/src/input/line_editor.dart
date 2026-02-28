import 'package:glue/src/terminal/terminal.dart';

/// Actions that the line editor signals back to its owner.
enum InputAction {
  /// The buffer contents changed (re-render needed).
  changed,

  /// The user pressed Enter — submit the buffer.
  submit,

  /// Ctrl+C — interrupt / cancel.
  interrupt,

  /// Ctrl+D on an empty buffer — EOF.
  eof,

  /// Escape pressed.
  escape,

  /// Tab pressed — request auto-completion.
  requestCompletion,
}

/// A readline-style line editor with history, word-level movement, and
/// standard Emacs-like keybindings.
///
/// Sits at the bottom of the TUI and processes [TerminalEvent]s into
/// [InputAction]s. The owning widget uses [text] and [cursor] to render
/// the current state.
class LineEditor {
  String _buffer = '';
  int _cursor = 0;
  final List<String> _history = [];
  int _historyIndex = -1;
  String _savedBuffer = '';
  String _lastSubmitted = '';

  /// The current text content of the editor.
  String get text => _buffer;

  /// The cursor position (character offset into [text]).
  int get cursor => _cursor;

  /// Whether the editor is empty.
  bool get isEmpty => _buffer.isEmpty;

  /// The text from the most recent submit (available after [InputAction.submit]).
  String get lastSubmitted => _lastSubmitted;

  /// The input history (read-only).
  List<String> get history => List.unmodifiable(_history);

  /// Processes a [TerminalEvent] and returns the resulting action, or `null` if
  /// the event was not consumed.
  InputAction? handle(TerminalEvent event) {
    return switch (event) {
      CharEvent(alt: true) => null,
      CharEvent(:final char) => _insert(char),
      KeyEvent(:final key, :final alt) => switch (key) {
          Key.enter => _submit(),
          Key.backspace => alt ? _deleteWord() : _backspace(),
          Key.delete => _delete(),
          Key.left => alt ? _moveWordLeft() : _moveLeft(),
          Key.right => alt ? _moveWordRight() : _moveRight(),
          Key.home || Key.ctrlA => _moveHome(),
          Key.end || Key.ctrlE => _moveEnd(),
          Key.up => _historyPrev(),
          Key.down => _historyNext(),
          Key.ctrlU => _clearLine(),
          Key.ctrlW => _deleteWord(),
          Key.ctrlK => _killToEnd(),
          Key.ctrlC => InputAction.interrupt,
          Key.ctrlD => isEmpty ? InputAction.eof : null,
          Key.tab => InputAction.requestCompletion,
          Key.escape => InputAction.escape,
          _ => null,
        },
      _ => null,
    };
  }

  // ── Editing operations ────────────────────────────────────────────────

  InputAction _insert(String char) {
    _buffer = _buffer.substring(0, _cursor) + char + _buffer.substring(_cursor);
    _cursor += char.length;
    return InputAction.changed;
  }

  InputAction _submit() {
    _lastSubmitted = _buffer;
    if (_buffer.isNotEmpty) {
      _history.add(_buffer);
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

  InputAction? _delete() {
    if (_cursor < _buffer.length) {
      _buffer = _buffer.substring(0, _cursor) + _buffer.substring(_cursor + 1);
      return InputAction.changed;
    }
    return null;
  }

  // ── Cursor movement ───────────────────────────────────────────────────

  InputAction? _moveLeft() {
    if (_cursor > 0) {
      _cursor--;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveRight() {
    if (_cursor < _buffer.length) {
      _cursor++;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveWordLeft() {
    if (_cursor == 0) return null;
    var i = _cursor - 1;
    while (i > 0 && _buffer[i] == ' ') {
      i--;
    }
    while (i > 0 && _buffer[i - 1] != ' ') {
      i--;
    }
    _cursor = i;
    return InputAction.changed;
  }

  InputAction? _moveWordRight() {
    if (_cursor >= _buffer.length) return null;
    var i = _cursor;
    while (i < _buffer.length && _buffer[i] == ' ') {
      i++;
    }
    while (i < _buffer.length && _buffer[i] != ' ') {
      i++;
    }
    _cursor = i;
    return InputAction.changed;
  }

  InputAction _moveHome() {
    _cursor = 0;
    return InputAction.changed;
  }

  InputAction _moveEnd() {
    _cursor = _buffer.length;
    return InputAction.changed;
  }

  // ── Line editing ──────────────────────────────────────────────────────

  InputAction _clearLine() {
    _buffer = _buffer.substring(_cursor);
    _cursor = 0;
    return InputAction.changed;
  }

  InputAction _killToEnd() {
    _buffer = _buffer.substring(0, _cursor);
    return InputAction.changed;
  }

  InputAction? _deleteWord() {
    if (_cursor == 0) return null;
    var i = _cursor - 1;
    while (i > 0 && _buffer[i] == ' ') {
      i--;
    }
    while (i > 0 && _buffer[i - 1] != ' ') {
      i--;
    }
    _buffer = _buffer.substring(0, i) + _buffer.substring(_cursor);
    _cursor = i;
    return InputAction.changed;
  }

  // ── History navigation ────────────────────────────────────────────────

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

  /// Clears the buffer and resets the cursor position.
  void clear() {
    _buffer = '';
    _cursor = 0;
  }

  /// Programmatically sets the buffer text and cursor position.
  ///
  /// Used by autocomplete to accept a completion.
  void setText(String text, {int? cursor}) {
    _buffer = text;
    _cursor = cursor ?? text.length;
    _historyIndex = -1;
  }
}
