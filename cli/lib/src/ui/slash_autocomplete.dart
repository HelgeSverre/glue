import '../commands/slash_commands.dart';
import '../rendering/ansi_utils.dart';

/// A candidate in the autocomplete list.
class _Candidate {
  final String name;
  final String description;
  _Candidate(this.name, this.description);
}

/// Controls slash command autocomplete state.
///
/// Activates when the input buffer starts with `/` (no spaces),
/// filters commands by prefix, and tracks selection. The owning
/// widget (App) is responsible for intercepting keys and rendering.
class SlashAutocomplete {
  final SlashCommandRegistry _registry;

  bool _active = false;
  int _selected = 0;
  List<_Candidate> _matches = [];

  static const maxVisible = 8;

  SlashAutocomplete(this._registry);

  /// Whether the autocomplete popup is currently shown.
  bool get active => _active;

  /// The currently selected index.
  int get selected => _selected;

  /// The current matches.
  int get matchCount => _matches.length;

  /// Dismiss the autocomplete popup.
  void dismiss() {
    _active = false;
    _matches = [];
    _selected = 0;
  }

  /// Update autocomplete state based on the current editor buffer.
  ///
  /// Call this after every buffer change. Returns true if the popup
  /// should be shown (state changed).
  void update(String buffer, int cursor) {
    // Only activate when buffer starts with `/`, cursor is at end,
    // and there's no space (still typing the command name).
    if (buffer.isEmpty ||
        !buffer.startsWith('/') ||
        cursor != buffer.length ||
        buffer.contains(' ')) {
      dismiss();
      return;
    }

    final prefix = buffer.substring(1).toLowerCase();
    final candidates = <_Candidate>[];
    for (final cmd in _registry.commands) {
      if (cmd.name.startsWith(prefix)) {
        candidates.add(_Candidate(cmd.name, cmd.description));
      }
      for (final alias in cmd.aliases) {
        if (alias.startsWith(prefix) && alias != cmd.name) {
          candidates.add(_Candidate(alias, '${cmd.description} (→/${cmd.name})'));
        }
      }
    }

    if (candidates.isEmpty) {
      dismiss();
      return;
    }

    _active = true;
    _matches = candidates;
    _selected = _selected.clamp(0, _matches.length - 1);
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

  /// The full command text of the currently selected item (e.g. `/help`).
  String? get selectedText {
    if (!_active || _matches.isEmpty) return null;
    return '/${_matches[_selected].name}';
  }

  /// Accept the current selection. Returns the full command text
  /// (e.g. `/help`) to fill into the editor.
  String? accept() {
    if (!_active || _matches.isEmpty) return null;
    final name = _matches[_selected].name;
    dismiss();
    return '/$name';
  }

  /// Render the popup as lines to be painted in the overlay zone.
  ///
  /// Each line is padded to [width] with the appropriate background.
  List<String> render(int width) {
    if (!_active || _matches.isEmpty) return [];

    final visible = _matches.length > maxVisible
        ? _matches.sublist(0, maxVisible)
        : _matches;

    // Dark gray bg: \x1b[48;5;236m
    // Selected: dark blue bg + bright white: \x1b[48;5;24m\x1b[97m
    const bgDim = '\x1b[48;5;236m\x1b[37m';
    const bgSel = '\x1b[48;5;24m\x1b[97m';
    const rst = '\x1b[0m';

    final lines = <String>[];
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final bg = i == _selected ? bgSel : bgDim;
      final nameCol = '/${c.name}';
      final descCol = c.description;
      // Layout: "   /name         description"
      final namePadded = nameCol.padRight(16);
      final content = '   $namePadded $descCol';
      final truncated = visibleLength(content) > width
          ? ansiTruncate(content, width)
          : content;
      // Pad to full width with background
      final padCount = width - visibleLength(truncated);
      lines.add('$bg$truncated${' ' * (padCount > 0 ? padCount : 0)}$rst');
    }

    return lines;
  }

  /// How many rows the overlay needs.
  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }
}
