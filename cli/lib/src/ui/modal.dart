import 'dart:async';
import 'dart:math';
import '../terminal/terminal.dart';

/// A choice in a confirmation modal.
class ModalChoice {
  final String label;
  final String hotkey;

  const ModalChoice(this.label, this.hotkey);
}

/// A confirmation modal rendered as a centered box overlay.
class ConfirmModal {
  final String title;
  final List<String> bodyLines;
  final List<ModalChoice> choices;
  final _completer = Completer<int>();
  int _selected = 0;

  ConfirmModal({
    required this.title,
    required this.bodyLines,
    required this.choices,
  });

  /// The future that resolves with the index of the chosen option.
  Future<int> get result => _completer.future;

  /// Whether the modal has been resolved.
  bool get isComplete => _completer.isCompleted;

  /// The currently selected choice index.
  int get selected => _selected;

  /// Handle a terminal event. Returns true if consumed.
  bool handleEvent(TerminalEvent event) {
    if (_completer.isCompleted) return false;

    switch (event) {
      case KeyEvent(key: Key.left):
        _selected = (_selected - 1).clamp(0, choices.length - 1);
        return true;
      case KeyEvent(key: Key.right) || KeyEvent(key: Key.tab):
        _selected = (_selected + 1) % choices.length;
        return true;
      case KeyEvent(key: Key.enter):
        _completer.complete(_selected);
        return true;
      case KeyEvent(key: Key.escape):
        // Escape = deny (find "No" choice, or default to 1)
        final noIndex = choices.indexWhere((c) => c.hotkey.toLowerCase() == 'n');
        _completer.complete(noIndex >= 0 ? noIndex : 1);
        return true;
      case CharEvent(char: final c):
        final idx = choices.indexWhere(
          (ch) => ch.hotkey.toLowerCase() == c.toLowerCase(),
        );
        if (idx >= 0) {
          _completer.complete(idx);
          return true;
        }
        return true; // Swallow all input while modal is open
      default:
        return true;
    }
  }

  /// Cancel the modal by completing with the "No"/deny choice.
  void cancel() {
    if (_completer.isCompleted) return;
    final noIndex = choices.indexWhere((c) => c.hotkey.toLowerCase() == 'n');
    _completer.complete(noIndex >= 0 ? noIndex : 1);
  }

  /// Render the modal as lines to be painted over the output zone.
  List<String> render(int terminalWidth) {
    final contentWidth = min(terminalWidth - 4, 64);
    if (contentWidth < 10) return ['[Modal too small]'];
    final horizontal = '─' * (contentWidth - 2);

    final lines = <String>[];
    lines.add(_center('┌$horizontal┐', terminalWidth));

    // Title
    lines.add(_center('│${_pad(' $title', contentWidth - 2)}│', terminalWidth));
    lines.add(_center('│${'─' * (contentWidth - 2)}│', terminalWidth));

    // Body
    for (final line in bodyLines) {
      final truncated = line.length > contentWidth - 4
          ? '${line.substring(0, contentWidth - 5)}…'
          : line;
      lines.add(_center('│${_pad('  $truncated', contentWidth - 2)}│', terminalWidth));
    }

    lines.add(_center('│${' ' * (contentWidth - 2)}│', terminalWidth));

    // Choices
    final choiceBuf = StringBuffer();
    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      if (i == _selected) {
        choiceBuf.write(' \x1b[7m [${choice.hotkey}]${choice.label} \x1b[27m ');
      } else {
        choiceBuf.write(' [${choice.hotkey}]${choice.label} ');
      }
    }
    lines.add(_center('│${_pad(choiceBuf.toString(), contentWidth - 2)}│', terminalWidth));
    lines.add(_center('└$horizontal┘', terminalWidth));

    return lines;
  }

  String _pad(String s, int width) {
    final visible = s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    if (visible.length >= width) return s;
    return '$s${' ' * (width - visible.length)}';
  }

  String _center(String s, int terminalWidth) {
    final visible = s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    final pad = ((terminalWidth - visible.length) / 2).floor().clamp(0, terminalWidth);
    return '${' ' * pad}$s';
  }
}
