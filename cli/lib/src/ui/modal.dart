import 'dart:async';
import '../terminal/styled.dart';
import '../terminal/terminal.dart';

/// A choice in a confirmation modal.
class ModalChoice {
  final String label;
  final String hotkey;

  const ModalChoice(this.label, this.hotkey);
}

/// An inline confirmation prompt rendered in the content flow.
///
/// Displays a highlighted title bar with context, followed by
/// selectable choices. Navigate with ←/→ or press hotkeys directly.
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
        final noIndex =
            choices.indexWhere((c) => c.hotkey.toLowerCase() == 'n');
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

  /// Render the modal as lines to be appended to the output.
  List<String> render(int terminalWidth) {
    final lines = <String>[];

    // Title bar — yellow background with tool name and context.
    final contextStr = bodyLines.isNotEmpty ? '  ${bodyLines.first}' : '';
    final titleContent = ' ? $title ';
    final maxContext = terminalWidth - titleContent.length - 4;
    final truncContext = contextStr.length > maxContext && maxContext > 0
        ? '${contextStr.substring(0, maxContext - 1)}…'
        : contextStr;
    lines.add(
      ' ${titleContent.styled.black.bgYellow}'
      '  ${truncContext.trim().styled.gray}',
    );

    // Extra body lines (if more than one arg).
    for (var i = 1; i < bodyLines.length; i++) {
      final line = bodyLines[i];
      final truncated = line.length > terminalWidth - 6
          ? '${line.substring(0, terminalWidth - 7)}…'
          : line;
      lines.add('    ${truncated.styled.gray}');
    }

    lines.add('');

    // Choices row.
    final choiceBuf = StringBuffer('   ');
    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      if (i == _selected) {
        choiceBuf
            .write('${'  (${choice.hotkey}) ${choice.label}  '.styled.inverse} ');
      } else {
        choiceBuf.write('  (${choice.hotkey}) ${choice.label}  ');
      }
    }
    lines.add(choiceBuf.toString());

    return lines;
  }
}
