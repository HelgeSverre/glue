import '../rendering/ansi_utils.dart';
import '../terminal/terminal.dart';
import 'line_editor.dart' show InputAction;

/// Maximum number of logical lines before rejecting further input.
const _maxLines = 500;

/// A multiline text editor with history, word-level movement, and
/// standard Emacs-like keybindings.
///
/// Drop-in replacement for [LineEditor] — exposes the same public API
/// (text, cursor, isEmpty, lastSubmitted, history, handle(), clear(),
/// setText()) plus multiline getters (lines, cursorRow, cursorCol).
class TextAreaEditor {
  List<String> _lines = [''];
  int _row = 0;
  int _col = 0;
  final List<String> _history = [];
  int _historyIndex = -1;
  String _savedBuffer = '';
  String _lastSubmitted = '';

  // ── Public API (compatible with LineEditor) ─────────────────────────

  /// The current text as a flat string (lines joined by \n).
  String get text => _lines.join('\n');

  /// The cursor as a flat character offset (for autocomplete compatibility).
  int get cursor {
    var offset = 0;
    for (var r = 0; r < _row; r++) {
      offset += _lines[r].length + 1; // +1 for \n
    }
    return offset + _col;
  }

  /// Whether the editor is empty.
  bool get isEmpty => _lines.length == 1 && _lines[0].isEmpty;

  /// The text from the most recent submit.
  String get lastSubmitted => _lastSubmitted;

  /// The input history (read-only).
  List<String> get history => List.unmodifiable(_history);

  // ── Multiline getters ──────────────────────────────────────────────

  /// The logical lines of text.
  List<String> get lines => List.unmodifiable(_lines);

  /// The cursor's row (0-indexed into [lines]).
  int get cursorRow => _row;

  /// The cursor's column (0-indexed into the current line).
  int get cursorCol => _col;

  /// Whether the editor contains multiple lines.
  bool get isMultiline => _lines.length > 1;

  // ── Event handling ─────────────────────────────────────────────────

  /// Process a [TerminalEvent] and return the resulting action, or `null`
  /// if the event was not consumed.
  InputAction? handle(TerminalEvent event) {
    return switch (event) {
      PasteEvent(:final content) => _paste(content),
      CharEvent(alt: true) => null,
      CharEvent(:final char) => _insert(char),
      KeyEvent(:final key, :final alt, :final shift) => switch (key) {
          Key.enter => shift ? _insertNewline() : _handleEnter(),
          Key.backspace => alt ? _deleteWord() : _backspace(),
          Key.delete => _delete(),
          Key.left => alt ? _moveWordLeft() : _moveLeft(),
          Key.right => alt ? _moveWordRight() : _moveRight(),
          Key.home || Key.ctrlA => _moveHome(),
          Key.end || Key.ctrlE => _moveEnd(),
          Key.up => _row > 0 ? _moveCursorUp() : _historyPrev(),
          Key.down =>
            _row < _lines.length - 1 ? _moveCursorDown() : _historyNext(),
          Key.ctrlU => _clearToStart(),
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

  // ── Editing operations ─────────────────────────────────────────────

  InputAction _insert(String char) {
    final line = _lines[_row];
    _lines[_row] = line.substring(0, _col) + char + line.substring(_col);
    _col += char.length;
    return InputAction.changed;
  }

  InputAction _insertNewline() {
    if (_lines.length >= _maxLines) return InputAction.changed;
    final line = _lines[_row];
    final before = line.substring(0, _col);
    final after = line.substring(_col);
    _lines[_row] = before;
    _lines.insert(_row + 1, after);
    _row++;
    _col = 0;
    return InputAction.changed;
  }

  InputAction _handleEnter() {
    // Backslash-Enter fallback: if the current line ends with `\` and
    // cursor is at end, remove the backslash and insert a newline.
    final line = _lines[_row];
    if (line.endsWith(r'\') && _col == line.length) {
      _lines[_row] = line.substring(0, line.length - 1);
      _col = _lines[_row].length;
      return _insertNewline();
    }
    return _submit();
  }

  InputAction _submit() {
    _lastSubmitted = text;
    if (!isEmpty) {
      _history.add(_lastSubmitted);
    }
    _lines = [''];
    _row = 0;
    _col = 0;
    _historyIndex = -1;
    return InputAction.submit;
  }

  InputAction _paste(String content) {
    // Strip ANSI escape sequences from pasted content.
    final clean = stripAnsi(content);
    final pasteLines = clean.split('\n');

    // Check total line count cap.
    final totalLines = _lines.length + pasteLines.length - 1;
    if (totalLines > _maxLines) return InputAction.changed;

    final line = _lines[_row];
    final before = line.substring(0, _col);
    final after = line.substring(_col);

    if (pasteLines.length == 1) {
      // Single line paste — insert inline.
      _lines[_row] = before + pasteLines[0] + after;
      _col = before.length + pasteLines[0].length;
    } else {
      // Multiline paste — split across lines.
      _lines[_row] = before + pasteLines.first;
      for (var i = 1; i < pasteLines.length - 1; i++) {
        _lines.insert(_row + i, pasteLines[i]);
      }
      _lines.insert(_row + pasteLines.length - 1, pasteLines.last + after);
      _row += pasteLines.length - 1;
      _col = pasteLines.last.length;
    }
    return InputAction.changed;
  }

  InputAction? _backspace() {
    if (_col > 0) {
      final line = _lines[_row];
      _lines[_row] = line.substring(0, _col - 1) + line.substring(_col);
      _col--;
      return InputAction.changed;
    }
    // At column 0 — join with previous line.
    if (_row > 0) {
      final prevLen = _lines[_row - 1].length;
      _lines[_row - 1] += _lines[_row];
      _lines.removeAt(_row);
      _row--;
      _col = prevLen;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _delete() {
    final line = _lines[_row];
    if (_col < line.length) {
      _lines[_row] = line.substring(0, _col) + line.substring(_col + 1);
      return InputAction.changed;
    }
    // At end of line — join with next line.
    if (_row < _lines.length - 1) {
      _lines[_row] = line + _lines[_row + 1];
      _lines.removeAt(_row + 1);
      return InputAction.changed;
    }
    return null;
  }

  // ── Cursor movement ────────────────────────────────────────────────

  InputAction? _moveLeft() {
    if (_col > 0) {
      _col--;
      return InputAction.changed;
    }
    // Wrap to end of previous line.
    if (_row > 0) {
      _row--;
      _col = _lines[_row].length;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveRight() {
    if (_col < _lines[_row].length) {
      _col++;
      return InputAction.changed;
    }
    // Wrap to start of next line.
    if (_row < _lines.length - 1) {
      _row++;
      _col = 0;
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveCursorUp() {
    if (_row > 0) {
      _row--;
      _col = _col.clamp(0, _lines[_row].length);
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveCursorDown() {
    if (_row < _lines.length - 1) {
      _row++;
      _col = _col.clamp(0, _lines[_row].length);
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _moveWordLeft() {
    if (_col == 0 && _row == 0) return null;

    // If at start of line, wrap to end of previous line.
    if (_col == 0 && _row > 0) {
      _row--;
      _col = _lines[_row].length;
      return InputAction.changed;
    }

    final line = _lines[_row];
    var i = _col - 1;
    while (i > 0 && line[i] == ' ') {
      i--;
    }
    while (i > 0 && line[i - 1] != ' ') {
      i--;
    }
    _col = i;
    return InputAction.changed;
  }

  InputAction? _moveWordRight() {
    final line = _lines[_row];
    if (_col >= line.length && _row >= _lines.length - 1) return null;

    // If at end of line, wrap to start of next line.
    if (_col >= line.length && _row < _lines.length - 1) {
      _row++;
      _col = 0;
      return InputAction.changed;
    }

    var i = _col;
    while (i < line.length && line[i] == ' ') {
      i++;
    }
    while (i < line.length && line[i] != ' ') {
      i++;
    }
    _col = i;
    return InputAction.changed;
  }

  InputAction _moveHome() {
    _col = 0;
    return InputAction.changed;
  }

  InputAction _moveEnd() {
    _col = _lines[_row].length;
    return InputAction.changed;
  }

  // ── Line editing ───────────────────────────────────────────────────

  InputAction _clearToStart() {
    _lines[_row] = _lines[_row].substring(_col);
    _col = 0;
    return InputAction.changed;
  }

  InputAction _killToEnd() {
    _lines[_row] = _lines[_row].substring(0, _col);
    return InputAction.changed;
  }

  InputAction? _deleteWord() {
    if (_col == 0 && _row == 0) return null;

    // At start of line — join with previous line instead.
    if (_col == 0 && _row > 0) {
      return _backspace();
    }

    final line = _lines[_row];
    var i = _col - 1;
    while (i > 0 && line[i] == ' ') {
      i--;
    }
    while (i > 0 && line[i - 1] != ' ') {
      i--;
    }
    _lines[_row] = line.substring(0, i) + line.substring(_col);
    _col = i;
    return InputAction.changed;
  }

  // ── History navigation ─────────────────────────────────────────────

  InputAction? _historyPrev() {
    if (_history.isEmpty) return null;
    if (_historyIndex == -1) _savedBuffer = text;
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _setFromText(_history[_history.length - 1 - _historyIndex]);
      return InputAction.changed;
    }
    return null;
  }

  InputAction? _historyNext() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _setFromText(_history[_history.length - 1 - _historyIndex]);
      return InputAction.changed;
    } else if (_historyIndex == 0) {
      _historyIndex = -1;
      _setFromText(_savedBuffer);
      return InputAction.changed;
    }
    return null;
  }

  // ── Public helpers ─────────────────────────────────────────────────

  /// Clear the buffer and reset cursor position.
  void clear() {
    _lines = [''];
    _row = 0;
    _col = 0;
  }

  /// Programmatically set the buffer text and cursor position.
  ///
  /// Used by autocomplete to accept a completion. The [cursor] parameter
  /// is a flat offset (same convention as LineEditor).
  void setText(String text, {int? cursor}) {
    _setFromText(text);
    if (cursor != null) {
      _setCursorFromFlat(cursor);
    }
    _historyIndex = -1;
  }

  // ── Internal helpers ───────────────────────────────────────────────

  void _setFromText(String value) {
    _lines = value.split('\n');
    if (_lines.isEmpty) _lines = [''];
    _row = _lines.length - 1;
    _col = _lines.last.length;
  }

  void _setCursorFromFlat(int offset) {
    var remaining = offset;
    for (var r = 0; r < _lines.length; r++) {
      if (remaining <= _lines[r].length) {
        _row = r;
        _col = remaining;
        return;
      }
      remaining -= _lines[r].length + 1; // +1 for \n
    }
    // Clamp to end.
    _row = _lines.length - 1;
    _col = _lines.last.length;
  }
}
