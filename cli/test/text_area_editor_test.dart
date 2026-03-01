import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  late TextAreaEditor editor;

  setUp(() {
    editor = TextAreaEditor();
  });

  /// Helper: type a string character by character.
  void type(String s) {
    for (final c in s.split('')) {
      editor.handle(CharEvent(c));
    }
  }

  /// Helper: send a key event.
  InputAction? key(Key k, {bool shift = false, bool alt = false}) =>
      editor.handle(KeyEvent(k, shift: shift, alt: alt));

  group('character insertion', () {
    test('single character updates text and cursor', () {
      final action = editor.handle(CharEvent('a'));
      expect(action, InputAction.changed);
      expect(editor.text, 'a');
      expect(editor.cursor, 1);
    });

    test('multiple characters build up text', () {
      type('hello');
      expect(editor.text, 'hello');
      expect(editor.cursor, 5);
    });

    test('insertion at cursor position (middle of text)', () {
      type('hllo');
      key(Key.home);
      key(Key.right);
      editor.handle(CharEvent('e'));
      expect(editor.text, 'hello');
      expect(editor.cursor, 2);
    });
  });

  group('submit (Enter)', () {
    test('returns submit action', () {
      type('hello');
      expect(key(Key.enter), InputAction.submit);
    });

    test('sets lastSubmitted', () {
      type('hello');
      key(Key.enter);
      expect(editor.lastSubmitted, 'hello');
    });

    test('clears buffer after submit', () {
      type('hello');
      key(Key.enter);
      expect(editor.text, '');
      expect(editor.cursor, 0);
      expect(editor.isEmpty, isTrue);
    });

    test('submitting empty buffer returns submit and empty lastSubmitted', () {
      final action = key(Key.enter);
      expect(action, InputAction.submit);
      expect(editor.lastSubmitted, '');
    });

    test('non-empty submit adds to history', () {
      type('cmd1');
      key(Key.enter);
      expect(editor.history, ['cmd1']);
    });

    test('empty submit does not add to history', () {
      key(Key.enter);
      expect(editor.history, isEmpty);
    });
  });

  group('newline insertion', () {
    test('Shift+Enter inserts newline', () {
      type('hello');
      final action = key(Key.enter, shift: true);
      expect(action, InputAction.changed);
      expect(editor.lines, ['hello', '']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 0);
    });

    test('Shift+Enter in middle of line splits it', () {
      type('helloworld');
      // Move cursor to position 5
      key(Key.home);
      for (var i = 0; i < 5; i++) {
        key(Key.right);
      }
      key(Key.enter, shift: true);
      expect(editor.lines, ['hello', 'world']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 0);
    });

    test('backslash-Enter removes backslash and inserts newline', () {
      type(r'hello\');
      final action = key(Key.enter);
      expect(action, InputAction.changed);
      expect(editor.lines, ['hello', '']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 0);
    });

    test('backslash-Enter only works at end of line', () {
      type(r'hello\');
      key(Key.left); // cursor before backslash
      // Regular enter should submit since cursor not at end of backslash
      // Actually cursor is at position 5, line is 'hello\', so cursor not at end
      // But the check is at col == line.length; cursor at 5 and line length is 6,
      // so enter should submit
      final action = key(Key.enter);
      expect(action, InputAction.submit);
    });

    test('multiple newlines create multiple lines', () {
      type('line1');
      key(Key.enter, shift: true);
      type('line2');
      key(Key.enter, shift: true);
      type('line3');
      expect(editor.lines, ['line1', 'line2', 'line3']);
      expect(editor.text, 'line1\nline2\nline3');
    });

    test('submitting multiline text preserves newlines in lastSubmitted', () {
      type('line1');
      key(Key.enter, shift: true);
      type('line2');
      key(Key.enter);
      expect(editor.lastSubmitted, 'line1\nline2');
    });

    test('empty lines are preserved', () {
      type('a');
      key(Key.enter, shift: true);
      key(Key.enter, shift: true);
      type('b');
      expect(editor.lines, ['a', '', 'b']);
      expect(editor.text, 'a\n\nb');
    });
  });

  group('backspace', () {
    test('deletes character before cursor', () {
      type('ab');
      expect(key(Key.backspace), InputAction.changed);
      expect(editor.text, 'a');
      expect(editor.cursor, 1);
    });

    test('at beginning of buffer returns null', () {
      type('abc');
      key(Key.home);
      expect(key(Key.backspace), isNull);
      expect(editor.text, 'abc');
    });

    test('at col 0 joins with previous line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.home);
      final action = key(Key.backspace);
      expect(action, InputAction.changed);
      expect(editor.lines, ['helloworld']);
      expect(editor.cursorRow, 0);
      expect(editor.cursorCol, 5);
    });

    test('on empty buffer returns null', () {
      expect(key(Key.backspace), isNull);
    });
  });

  group('delete', () {
    test('deletes character at cursor', () {
      type('abc');
      key(Key.home);
      expect(key(Key.delete), InputAction.changed);
      expect(editor.text, 'bc');
    });

    test('at end of line joins with next line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      // Move to end of first line
      key(Key.home);
      // Go to row 0
      key(Key.up);
      key(Key.end);
      final action = key(Key.delete);
      expect(action, InputAction.changed);
      expect(editor.lines, ['helloworld']);
    });

    test('at end of last line returns null', () {
      type('abc');
      expect(key(Key.delete), isNull);
    });
  });

  group('cursor movement', () {
    test('left moves cursor back', () {
      type('abc');
      expect(key(Key.left), InputAction.changed);
      expect(editor.cursorCol, 2);
    });

    test('left at start of line wraps to end of previous line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.home);
      key(Key.left);
      expect(editor.cursorRow, 0);
      expect(editor.cursorCol, 5);
    });

    test('left at absolute start returns null', () {
      type('abc');
      key(Key.home);
      expect(key(Key.left), isNull);
    });

    test('right moves cursor forward', () {
      type('abc');
      key(Key.home);
      expect(key(Key.right), InputAction.changed);
      expect(editor.cursorCol, 1);
    });

    test('right at end of line wraps to start of next line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      // Navigate to end of first line
      key(Key.home);
      key(Key.up);
      key(Key.end);
      key(Key.right);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 0);
    });

    test('right at absolute end returns null', () {
      type('abc');
      expect(key(Key.right), isNull);
    });

    test('up moves cursor to previous row', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.up);
      expect(editor.cursorRow, 0);
      expect(editor.cursorCol, 5); // clamped to line length
    });

    test('up on row 0 navigates history', () {
      type('first');
      key(Key.enter);
      key(Key.up);
      expect(editor.text, 'first');
    });

    test('down moves cursor to next row', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.up);
      key(Key.down);
      expect(editor.cursorRow, 1);
    });

    test('down on last row navigates history', () {
      type('first');
      key(Key.enter);
      type('second');
      key(Key.enter);
      // Now history = ['first', 'second']
      key(Key.up); // loads 'second'
      expect(editor.text, 'second');
      key(Key.up); // loads 'first'
      expect(editor.text, 'first');
      key(Key.down); // back to 'second'
      expect(editor.text, 'second');
      key(Key.down); // back to saved buffer ('')
      expect(editor.text, '');
    });

    test('up clamps col to shorter line', () {
      type('longline');
      key(Key.enter, shift: true);
      type('ab');
      key(Key.home);
      key(Key.up);
      // Row 0 col should be clamped; but we were at col 0, so stays 0
      expect(editor.cursorRow, 0);

      // Try with cursor at end of long line, then a short line above
      editor.clear();
      type('ab');
      key(Key.enter, shift: true);
      type('longline');
      key(Key.up);
      expect(editor.cursorRow, 0);
      expect(editor.cursorCol, 2); // clamped to 'ab'.length
    });

    test('home moves to start of current line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.home);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 0);
    });

    test('end moves to end of current line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.home);
      key(Key.end);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 5);
    });
  });

  group('line editing', () {
    test('ctrlU clears from start of current line to cursor', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      // Move cursor to position 3 in 'world'
      key(Key.home);
      for (var i = 0; i < 3; i++) {
        key(Key.right);
      }
      key(Key.ctrlU);
      expect(editor.lines[1], 'ld');
      expect(editor.cursorCol, 0);
      // First line unaffected
      expect(editor.lines[0], 'hello');
    });

    test('ctrlK kills to end of current line', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      key(Key.home);
      for (var i = 0; i < 2; i++) {
        key(Key.right);
      }
      key(Key.ctrlK);
      expect(editor.lines[1], 'wo');
      expect(editor.cursorCol, 2);
    });

    test('ctrlW deletes word on current line', () {
      type('hello world');
      key(Key.ctrlW);
      expect(editor.text, 'hello ');
      expect(editor.cursorCol, 6);
    });
  });

  group('paste handling', () {
    test('single-line paste inserts inline', () {
      type('hello');
      key(Key.home);
      for (var i = 0; i < 3; i++) {
        key(Key.right);
      }
      final action = editor.handle(PasteEvent('XY'));
      expect(action, InputAction.changed);
      expect(editor.text, 'helXYlo');
      expect(editor.cursorCol, 5);
    });

    test('multiline paste splits across lines', () {
      type('hello');
      key(Key.home);
      for (var i = 0; i < 3; i++) {
        key(Key.right);
      }
      editor.handle(PasteEvent('X\nY\nZ'));
      expect(editor.lines, ['helX', 'Y', 'Zlo']);
      expect(editor.cursorRow, 2);
      expect(editor.cursorCol, 1); // after 'Z'
    });

    test('paste at end of buffer', () {
      type('hello');
      editor.handle(PasteEvent('\nworld'));
      expect(editor.lines, ['hello', 'world']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 5);
    });

    test('paste strips ANSI sequences', () {
      editor.handle(PasteEvent('\x1b[31mhello\x1b[0m'));
      expect(editor.text, 'hello');
    });

    test('empty paste is a no-op', () {
      type('hello');
      editor.handle(PasteEvent(''));
      expect(editor.text, 'hello');
    });
  });

  group('history', () {
    test('up with no history returns null', () {
      expect(key(Key.up), isNull);
    });

    test('navigates to previous entry', () {
      type('first');
      key(Key.enter);
      type('second');
      key(Key.enter);

      expect(key(Key.up), InputAction.changed);
      expect(editor.text, 'second');
    });

    test('multiline history entry is restored correctly', () {
      type('line1');
      key(Key.enter, shift: true);
      type('line2');
      key(Key.enter);
      expect(editor.history, ['line1\nline2']);

      key(Key.up);
      expect(editor.lines, ['line1', 'line2']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 5);
    });

    test('saves current buffer when entering history', () {
      type('cmd1');
      key(Key.enter);

      type('typing');
      key(Key.up);
      key(Key.down);
      expect(editor.text, 'typing');
    });
  });

  group('flat offset compatibility', () {
    test('cursor returns correct flat offset for single line', () {
      type('hello');
      expect(editor.cursor, 5);
      key(Key.home);
      expect(editor.cursor, 0);
    });

    test('cursor returns correct flat offset for multiline', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      // cursor at row 1 col 5 = 5 (hello) + 1 (\n) + 5 (world) = 11
      expect(editor.cursor, 11);
    });

    test('cursor at start of second line', () {
      type('hello');
      key(Key.enter, shift: true);
      key(Key.home);
      // cursor at row 1 col 0 = 5 (hello) + 1 (\n) = 6
      expect(editor.cursor, 6);
    });

    test('text returns lines joined by newline', () {
      type('a');
      key(Key.enter, shift: true);
      type('b');
      key(Key.enter, shift: true);
      type('c');
      expect(editor.text, 'a\nb\nc');
    });
  });

  group('setText', () {
    test('sets text and cursor at end', () {
      editor.setText('hello world');
      expect(editor.text, 'hello world');
      expect(editor.cursorCol, 11);
    });

    test('sets multiline text', () {
      editor.setText('line1\nline2');
      expect(editor.lines, ['line1', 'line2']);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 5);
    });

    test('sets cursor at specific flat offset', () {
      editor.setText('hello\nworld', cursor: 7);
      expect(editor.cursorRow, 1);
      expect(editor.cursorCol, 1); // offset 7 = 'hello\n' (6) + 'w' (1)
    });
  });

  group('interrupt and EOF', () {
    test('ctrlC returns interrupt', () {
      expect(key(Key.ctrlC), InputAction.interrupt);
    });

    test('ctrlD on empty buffer returns eof', () {
      expect(key(Key.ctrlD), InputAction.eof);
    });

    test('ctrlD on non-empty buffer returns null', () {
      type('x');
      expect(key(Key.ctrlD), isNull);
    });
  });

  group('tab and escape', () {
    test('tab returns requestCompletion', () {
      expect(key(Key.tab), InputAction.requestCompletion);
    });

    test('escape returns escape', () {
      expect(key(Key.escape), InputAction.escape);
    });
  });

  group('edge cases', () {
    test('empty buffer is empty', () {
      expect(editor.isEmpty, isTrue);
      expect(editor.text, '');
      expect(editor.cursor, 0);
    });

    test('clear resets to empty', () {
      type('hello');
      key(Key.enter, shift: true);
      type('world');
      editor.clear();
      expect(editor.isEmpty, isTrue);
      expect(editor.lines, ['']);
      expect(editor.cursorRow, 0);
      expect(editor.cursorCol, 0);
    });

    test('isMultiline is false for single line', () {
      type('hello');
      expect(editor.isMultiline, isFalse);
    });

    test('isMultiline is true for multiple lines', () {
      type('hello');
      key(Key.enter, shift: true);
      expect(editor.isMultiline, isTrue);
    });

    test('alt+char is swallowed (not inserted)', () {
      type('hello');
      final action = editor.handle(CharEvent('f', alt: true));
      expect(action, isNull);
      expect(editor.text, 'hello');
    });

    test('resize event returns null', () {
      expect(editor.handle(ResizeEvent(80, 24)), isNull);
    });

    test('unknown key returns null', () {
      expect(key(Key.unknown), isNull);
    });

    test('word movement (alt+left)', () {
      type('hello world');
      final action = editor.handle(KeyEvent(Key.left, alt: true));
      expect(action, InputAction.changed);
      expect(editor.cursorCol, 6);
    });

    test('word movement (alt+right)', () {
      type('hello world');
      key(Key.home);
      final action = editor.handle(KeyEvent(Key.right, alt: true));
      expect(action, InputAction.changed);
      expect(editor.cursorCol, 5);
    });

    test('alt+backspace deletes word', () {
      type('hello world');
      final action = editor.handle(KeyEvent(Key.backspace, alt: true));
      expect(action, InputAction.changed);
      expect(editor.text, 'hello ');
    });
  });
}
