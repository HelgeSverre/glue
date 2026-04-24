import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/components/overlays.dart';

/// Internal candidate, used for both name-mode and arg-mode dropdowns.
class _Candidate {
  final String display;
  final String description;
  final String acceptValue;
  final bool acceptContinues;
  _Candidate({
    required this.display,
    required this.description,
    required this.acceptValue,
    required this.acceptContinues,
  });
}

enum _Mode { name, arg }

/// Controls slash command autocomplete state.
///
/// Two modes:
/// - **Name mode**: buffer is `/prefix` with no space — filters registry by
///   command name / alias.
/// - **Arg mode**: buffer is `/<knownCmd> <partial>` and the resolved
///   command has an [ArgCompleter] attached — filters that command's
///   argument candidates.
///
/// The overlay itself only renders — the owning widget (App) intercepts
/// keys and calls [update]/[accept]. [ShellAutocomplete] is the only other
/// overlay with a similar mid-buffer splice pattern, but it only activates
/// in bash mode, so there is no collision risk with slash commands.
class SlashAutocomplete implements AutocompleteOverlay {
  final SlashCommandRegistry _registry;

  bool _active = false;
  int _selected = 0;
  int _scrollOffset = 0;
  List<_Candidate> _matches = [];
  _Mode _mode = _Mode.name;
  String _buffer = '';

  static const maxVisible = AppConstants.maxVisibleDropdownItems;

  SlashAutocomplete(this._registry);

  @override
  bool get active => _active;

  @override
  int get selected => _selected;

  @override
  int get matchCount => _matches.length;

  @override
  void dismiss() {
    _active = false;
    _matches = [];
    _selected = 0;
    _scrollOffset = 0;
    _buffer = '';
    _mode = _Mode.name;
  }

  /// Update autocomplete state based on the current editor buffer.
  void update(String buffer, int cursor) {
    if (buffer.isEmpty ||
        !buffer.startsWith('/') ||
        cursor != buffer.length ||
        buffer.contains('\n')) {
      dismiss();
      return;
    }
    // Predictable whitespace: reject tabs and runs of multiple spaces.
    if (buffer.contains('\t') || buffer.contains('  ')) {
      dismiss();
      return;
    }

    final body = buffer.substring(1);
    final parts = body.split(' ');
    final cmdName = parts[0].toLowerCase();

    if (parts.length == 1) {
      _updateNameMode(cmdName, buffer);
    } else {
      _updateArgMode(cmdName, parts, buffer);
    }
  }

  void _updateNameMode(String prefix, String buffer) {
    final candidates = <_Candidate>[];
    for (final cmd in _registry.commands) {
      if (cmd.name.startsWith(prefix)) {
        candidates.add(_candidateForCommand(cmd, cmd.name));
      }
      for (final alias in cmd.aliases) {
        if (alias.startsWith(prefix) && alias != cmd.name) {
          candidates.add(_candidateForCommand(
            cmd,
            alias,
            descriptionOverride: '${cmd.description} (→/${cmd.name})',
          ));
        }
      }
    }

    if (candidates.isEmpty) {
      dismiss();
      return;
    }

    _active = true;
    _mode = _Mode.name;
    _matches = candidates;
    _buffer = buffer;
    _selected = _selected.clamp(0, _matches.length - 1);
    _scrollOffset = 0;
    _clampScroll();
  }

  _Candidate _candidateForCommand(
    SlashCommand cmd,
    String displayName, {
    String? descriptionOverride,
  }) {
    // Trailing space only when the command expects args — preserves the
    // Enter-on-exact-match submit behavior for arg-less commands.
    final continues = cmd.completeArg != null;
    return _Candidate(
      display: '/$displayName',
      description: descriptionOverride ?? cmd.description,
      acceptValue: '/$displayName',
      acceptContinues: continues,
    );
  }

  void _updateArgMode(String cmdName, List<String> parts, String buffer) {
    final cmd = _registry.findByName(cmdName);
    final completer = cmd?.completeArg;
    if (completer == null) {
      dismiss();
      return;
    }

    final priorArgs = parts.sublist(1, parts.length - 1);
    final partial = parts.last.toLowerCase();
    final List<SlashArgCandidate> results;
    try {
      results = completer(priorArgs, partial);
    } catch (_) {
      dismiss();
      return;
    }
    if (results.isEmpty) {
      dismiss();
      return;
    }

    _matches = results
        .map((c) => _Candidate(
              display: c.value,
              description: c.description,
              acceptValue: c.value,
              acceptContinues: c.continues,
            ))
        .toList();
    _active = true;
    _mode = _Mode.arg;
    _buffer = buffer;
    _selected = _selected.clamp(0, _matches.length - 1);
    _scrollOffset = 0;
    _clampScroll();
  }

  @override
  void moveUp() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected - 1) % _matches.length;
    if (_selected < 0) _selected += _matches.length;
    _clampScroll();
  }

  @override
  void moveDown() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected + 1) % _matches.length;
    _clampScroll();
  }

  void _clampScroll() {
    if (_selected < _scrollOffset) {
      _scrollOffset = _selected;
    } else if (_selected >= _scrollOffset + maxVisible) {
      _scrollOffset = _selected - maxVisible + 1;
    }
    final maxStart = (_matches.length - maxVisible).clamp(0, _matches.length);
    _scrollOffset = _scrollOffset.clamp(0, maxStart);
  }

  /// The full command text the current selection would set. Used by the
  /// router to detect "Enter on an already-accepted selection" and submit
  /// instead of re-accepting.
  String? get selectedText {
    if (!_active || _matches.isEmpty) return null;
    final match = _matches[_selected];
    if (_mode == _Mode.name) {
      return match.acceptValue + (match.acceptContinues ? ' ' : '');
    }
    // Arg mode: reconstruct what `accept` would produce.
    final tokenStart = _buffer.lastIndexOf(' ') + 1;
    final before = _buffer.substring(0, tokenStart);
    final suffix = match.acceptContinues ? ' ' : '';
    return '$before${match.acceptValue}$suffix';
  }

  /// Accept the current selection.
  @override
  AcceptResult? accept(String buffer, int cursor) {
    if (!_active || _matches.isEmpty) return null;
    final match = _matches[_selected];

    String text;
    if (_mode == _Mode.name) {
      final suffix = match.acceptContinues ? ' ' : '';
      text = '${match.acceptValue}$suffix';
    } else {
      final tokenStart = _buffer.lastIndexOf(' ') + 1;
      final before = _buffer.substring(0, tokenStart);
      final suffix = match.acceptContinues ? ' ' : '';
      text = '$before${match.acceptValue}$suffix';
    }

    dismiss();
    return AcceptResult(text, text.length);
  }

  /// Render the popup as lines to be painted in the overlay zone.
  @override
  List<String> render(int width) {
    if (!_active || _matches.isEmpty) return [];

    final end = (_scrollOffset + maxVisible).clamp(0, _matches.length);
    final visible = _matches.sublist(_scrollOffset, end);

    final lines = <String>[];
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final absoluteIndex = _scrollOffset + i;
      final namePadded = c.display.padRight(16);
      final content = '   $namePadded ${c.description}';
      final truncated = visibleLength(content) > width
          ? ansiTruncate(content, width)
          : content;
      final padCount = width - visibleLength(truncated);
      final padded = '$truncated${' ' * (padCount > 0 ? padCount : 0)}';
      lines.add(absoluteIndex == _selected
          ? '${padded.styled.bg256(24).brightWhite}'
          : '${padded.styled.bg256(236).white}');
    }

    return lines;
  }

  /// How many rows the overlay needs.
  @override
  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }
}
