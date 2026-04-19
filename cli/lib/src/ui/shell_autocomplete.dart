import 'package:glue/src/config/constants.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/ui/autocomplete_overlay.dart';

/// Controls shell mode tab-completion overlay state.
///
/// Implements [AutocompleteOverlay]. Unlike slash/@-file overlays, this
/// one activates only on explicit Tab press via [requestCompletions]
/// (async, because it shells out to `fish complete -C` / `compgen`).
class ShellAutocomplete implements AutocompleteOverlay {
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

  @override
  bool get active => _active;

  @override
  int get selected => _selected;

  @override
  int get matchCount => _matches.length;

  /// The start position of the completable token in the buffer.
  int get tokenStart => _tokenStart;

  @override
  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }

  @override
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

  @override
  void moveUp() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected - 1) % _matches.length;
  }

  @override
  void moveDown() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected + 1) % _matches.length;
  }

  /// Accept the current selection. The shell overlay has cached the
  /// triggering buffer/cursor at `requestCompletions` time, so the
  /// passed-in [buffer] and [cursor] are ignored.
  @override
  AcceptResult? accept(String buffer, int cursor) {
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
    return AcceptResult(newText, newCursor);
  }

  /// Render the popup as lines to be painted in the overlay zone.
  @override
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
