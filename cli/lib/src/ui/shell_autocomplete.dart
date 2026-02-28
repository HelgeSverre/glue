import 'package:glue/src/config/constants.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/shell/shell_completer.dart';

/// Controls shell mode tab-completion overlay state.
///
/// Follows the same API contract as [SlashAutocomplete] and [AtFileHint]:
/// the owning widget (App) calls [requestCompletions] on Tab press,
/// intercepts keys when [active], and renders the overlay.
class ShellAutocomplete {
  final ShellCompleter _completer;

  bool _active = false;
  int _selected = 0;
  int _tokenStart = 0;
  String _buffer = '';
  int _cursor = 0;
  List<ShellCandidate> _matches = [];
  int _requestId = 0;

  static const maxVisible = AppConstants.maxVisibleDropdownItems;

  ShellAutocomplete(this._completer);

  /// Whether the autocomplete popup is currently shown.
  bool get active => _active;

  /// The currently selected index.
  int get selected => _selected;

  /// The current number of matches.
  int get matchCount => _matches.length;

  /// The start position of the completable token in the buffer.
  int get tokenStart => _tokenStart;

  /// How many rows the overlay needs.
  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }

  /// Dismiss the autocomplete popup.
  void dismiss() {
    _active = false;
    _matches = [];
    _selected = 0;
    _tokenStart = 0;
    _buffer = '';
    _cursor = 0;
  }

  /// Request completions for the current buffer. Called on Tab press.
  ///
  /// Returns a Future that resolves when completions are ready.
  /// The caller should re-render after awaiting this.
  Future<void> requestCompletions(String buffer, int cursor) async {
    if (buffer.isEmpty) {
      dismiss();
      return;
    }

    final line = buffer.substring(0, cursor);
    final id = ++_requestId;
    final candidates = await _completer.complete(line);

    // Stale check: discard if another request was made while we waited.
    if (id != _requestId) return;

    if (candidates.isEmpty) {
      dismiss();
      return;
    }

    _active = true;
    _buffer = buffer;
    _cursor = cursor;
    _tokenStart = _completer.tokenStart(line);
    _matches = candidates;
    _selected = 0;
  }

  /// Move selection up.
  void moveUp() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected - 1) % _matches.length;
  }

  /// Move selection down.
  void moveDown() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected + 1) % _matches.length;
  }

  /// Accept the current selection.
  ///
  /// Returns a record of (buffer, cursorPosition) to set into the editor,
  /// or null if nothing to accept.
  ({String text, int cursor})? accept() {
    if (!_active || _matches.isEmpty) return null;
    final candidate = _matches[_selected];

    final before = _buffer.substring(0, _tokenStart);
    final after = _cursor < _buffer.length ? _buffer.substring(_cursor) : '';

    // Add trailing space unless it's a directory.
    final suffix = candidate.isDirectory ? '/' : ' ';
    final completion = candidate.text + suffix;
    final newText = '$before$completion$after';
    final newCursor = before.length + completion.length;

    dismiss();
    return (text: newText, cursor: newCursor);
  }

  /// Render the popup as lines to be painted in the overlay zone.
  List<String> render(int width) {
    if (!_active || _matches.isEmpty) return [];

    final visible = _matches.length > maxVisible
        ? _matches.sublist(0, maxVisible)
        : _matches;

    const bgDim = '\x1b[48;5;236m\x1b[37m';
    const bgSel = '\x1b[48;5;24m\x1b[97m';
    const rst = '\x1b[0m';

    final lines = <String>[];
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final bg = i == _selected ? bgSel : bgDim;
      final icon = c.isDirectory ? '📁 ' : '   ';
      final descPart = c.description != null ? '  ${c.description}' : '';
      final content = '   $icon${c.text}$descPart';
      final truncated = visibleLength(content) > width
          ? ansiTruncate(content, width)
          : content;
      final padCount = width - visibleLength(truncated);
      lines.add('$bg$truncated${' ' * (padCount > 0 ? padCount : 0)}$rst');
    }

    return lines;
  }
}
