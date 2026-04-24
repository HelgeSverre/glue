import 'package:test/test.dart';

import 'package:glue/src/input/line_editor.dart';
import 'package:glue/src/terminal/terminal.dart';

void main() {
  late LineEditor editor;

  setUp(() {
    editor = LineEditor();
  });

  /// Helper: type a string character by character.
  void type(String s) {
    for (final c in s.split('')) {
      editor.handle(CharEvent(c));
    }
  }

  /// Helper: send a key event.
  InputAction? key(Key k) => editor.handle(KeyEvent(k));

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
      // Move cursor after 'h'
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

    test('on empty buffer returns null', () {
      expect(key(Key.backspace), isNull);
      expect(editor.text, '');
    });

    test('in middle of text', () {
      type('abc');
      key(Key.left); // cursor at 2
      key(Key.backspace);
      expect(editor.text, 'ac');
      expect(editor.cursor, 1);
    });
  });

  group('delete', () {
    test('deletes character at cursor', () {
      type('abc');
      key(Key.home);
      expect(key(Key.delete), InputAction.changed);
      expect(editor.text, 'bc');
      expect(editor.cursor, 0);
    });

    test('at end of buffer returns null', () {
      type('abc');
      expect(key(Key.delete), isNull);
      expect(editor.text, 'abc');
    });

    test('on empty buffer returns null', () {
      expect(key(Key.delete), isNull);
    });

    test('in middle of text', () {
      type('abc');
      key(Key.home);
      key(Key.right); // cursor at 1
      key(Key.delete);
      expect(editor.text, 'ac');
      expect(editor.cursor, 1);
    });
  });

  group('cursor movement', () {
    test('left moves cursor back', () {
      type('abc');
      expect(key(Key.left), InputAction.changed);
      expect(editor.cursor, 2);
    });

    test('left at start returns null', () {
      type('abc');
      key(Key.home);
      expect(key(Key.left), isNull);
      expect(editor.cursor, 0);
    });

    test('right moves cursor forward', () {
      type('abc');
      key(Key.home);
      expect(key(Key.right), InputAction.changed);
      expect(editor.cursor, 1);
    });

    test('right at end returns null', () {
      type('abc');
      expect(key(Key.right), isNull);
      expect(editor.cursor, 3);
    });

    test('home (ctrlA) moves to beginning', () {
      type('hello');
      expect(key(Key.ctrlA), InputAction.changed);
      expect(editor.cursor, 0);
    });

    test('home key moves to beginning', () {
      type('hello');
      expect(key(Key.home), InputAction.changed);
      expect(editor.cursor, 0);
    });

    test('end (ctrlE) moves to end', () {
      type('hello');
      key(Key.home);
      expect(key(Key.ctrlE), InputAction.changed);
      expect(editor.cursor, 5);
    });

    test('end key moves to end', () {
      type('hello');
      key(Key.home);
      expect(key(Key.end), InputAction.changed);
      expect(editor.cursor, 5);
    });
  });

  group('line editing', () {
    group('ctrlU (clear to start)', () {
      test('clears text before cursor', () {
        type('hello world');
        // Move cursor to position 5 (after 'hello')
        key(Key.home);
        for (var i = 0; i < 5; i++) {
          key(Key.right);
        }
        expect(key(Key.ctrlU), InputAction.changed);
        expect(editor.text, ' world');
        expect(editor.cursor, 0);
      });

      test('at beginning clears nothing', () {
        type('hello');
        key(Key.home);
        key(Key.ctrlU);
        expect(editor.text, 'hello');
        expect(editor.cursor, 0);
      });

      test('at end clears entire line', () {
        type('hello');
        key(Key.ctrlU);
        expect(editor.text, '');
        expect(editor.cursor, 0);
      });
    });

    group('ctrlK (kill to end)', () {
      test('kills text after cursor', () {
        type('hello world');
        key(Key.home);
        for (var i = 0; i < 5; i++) {
          key(Key.right);
        }
        expect(key(Key.ctrlK), InputAction.changed);
        expect(editor.text, 'hello');
        expect(editor.cursor, 5);
      });

      test('at end kills nothing', () {
        type('hello');
        key(Key.ctrlK);
        expect(editor.text, 'hello');
        expect(editor.cursor, 5);
      });

      test('at beginning kills entire line', () {
        type('hello');
        key(Key.home);
        key(Key.ctrlK);
        expect(editor.text, '');
        expect(editor.cursor, 0);
      });
    });

    group('ctrlW (delete word)', () {
      test('deletes word before cursor', () {
        type('hello world');
        expect(key(Key.ctrlW), InputAction.changed);
        expect(editor.text, 'hello ');
        expect(editor.cursor, 6);
      });

      test('at beginning returns null', () {
        type('hello');
        key(Key.home);
        expect(key(Key.ctrlW), isNull);
        expect(editor.text, 'hello');
      });

      test('on empty buffer returns null', () {
        expect(key(Key.ctrlW), isNull);
      });

      test('deletes trailing spaces and word', () {
        type('one two   ');
        key(Key.ctrlW);
        expect(editor.text, 'one ');
        expect(editor.cursor, 4);
      });

      test('single word deletes entire word', () {
        type('hello');
        key(Key.ctrlW);
        expect(editor.text, '');
        expect(editor.cursor, 0);
      });

      test('multiple words in sequence', () {
        type('a b c');
        key(Key.ctrlW); // removes 'c'
        expect(editor.text, 'a b ');
        key(Key.ctrlW); // removes 'b '
        expect(editor.text, 'a ');
        key(Key.ctrlW); // removes 'a '
        expect(editor.text, '');
      });
    });
  });

  group('history', () {
    test('up with no history returns null', () {
      expect(key(Key.up), isNull);
    });

    test('down with no history returns null', () {
      expect(key(Key.down), isNull);
    });

    test('navigates to previous entry', () {
      type('first');
      key(Key.enter);
      type('second');
      key(Key.enter);

      expect(key(Key.up), InputAction.changed);
      expect(editor.text, 'second');
      expect(editor.cursor, 6);
    });

    test('navigates through full history', () {
      type('first');
      key(Key.enter);
      type('second');
      key(Key.enter);
      type('third');
      key(Key.enter);

      key(Key.up); // third
      key(Key.up); // second
      key(Key.up); // first
      expect(editor.text, 'first');
    });

    test('up stops at oldest entry', () {
      type('only');
      key(Key.enter);

      key(Key.up); // 'only'
      expect(key(Key.up), isNull);
      expect(editor.text, 'only');
    });

    test('down navigates forward', () {
      type('first');
      key(Key.enter);
      type('second');
      key(Key.enter);

      key(Key.up); // second
      key(Key.up); // first
      expect(key(Key.down), InputAction.changed);
      expect(editor.text, 'second');
    });

    test('down past newest restores saved buffer', () {
      type('first');
      key(Key.enter);

      type('current');
      key(Key.up); // 'first', saves 'current'
      expect(key(Key.down), InputAction.changed);
      expect(editor.text, 'current');
    });

    test('down past saved buffer returns null', () {
      type('first');
      key(Key.enter);

      type('current');
      key(Key.up);
      key(Key.down); // back to 'current'
      expect(key(Key.down), isNull);
    });

    test('cursor at end after history navigation', () {
      type('hello');
      key(Key.enter);

      key(Key.up);
      expect(editor.cursor, 5);
    });

    test('saves current buffer when entering history', () {
      type('cmd1');
      key(Key.enter);
      type('cmd2');
      key(Key.enter);

      type('typing');
      key(Key.up); // cmd2
      key(Key.up); // cmd1
      key(Key.down); // cmd2
      key(Key.down); // back to 'typing'
      expect(editor.text, 'typing');
    });
  });

  group('interrupt (ctrlC)', () {
    test('returns interrupt', () {
      expect(key(Key.ctrlC), InputAction.interrupt);
    });

    test('returns interrupt with text in buffer', () {
      type('something');
      expect(key(Key.ctrlC), InputAction.interrupt);
    });
  });

  group('EOF (ctrlD)', () {
    test('on empty buffer returns eof', () {
      expect(key(Key.ctrlD), InputAction.eof);
    });

    test('on non-empty buffer returns null', () {
      type('x');
      expect(key(Key.ctrlD), isNull);
    });
  });

  group('tab', () {
    test('returns requestCompletion', () {
      expect(key(Key.tab), InputAction.requestCompletion);
    });

    test('returns requestCompletion with text', () {
      type('hel');
      expect(key(Key.tab), InputAction.requestCompletion);
    });
  });

  group('escape', () {
    test('returns escape', () {
      expect(key(Key.escape), InputAction.escape);
    });
  });

  group('alt key word navigation', () {
    test('alt+left moves to previous word boundary', () {
      type('hello world');
      final action = editor.handle(KeyEvent(Key.left, alt: true));
      expect(action, InputAction.changed);
      expect(editor.cursor, 6);
    });

    test('alt+left skips trailing spaces', () {
      type('hello   world');
      editor.handle(KeyEvent(Key.left, alt: true)); // to 'w' at 8
      editor.handle(KeyEvent(Key.left, alt: true)); // to 'h' at 0
      expect(editor.cursor, 0);
    });

    test('alt+left at beginning returns null', () {
      type('hello');
      key(Key.home);
      expect(editor.handle(KeyEvent(Key.left, alt: true)), isNull);
    });

    test('alt+right moves to next word boundary', () {
      type('hello world');
      key(Key.home);
      final action = editor.handle(KeyEvent(Key.right, alt: true));
      expect(action, InputAction.changed);
      expect(editor.cursor, 5);
    });

    test('alt+right skips leading spaces', () {
      type('hello   world');
      key(Key.home);
      editor.handle(KeyEvent(Key.right, alt: true)); // to end of 'hello'
      editor.handle(KeyEvent(Key.right, alt: true)); // to end of 'world'
      expect(editor.cursor, 13);
    });

    test('alt+right at end returns null', () {
      type('hello');
      expect(editor.handle(KeyEvent(Key.right, alt: true)), isNull);
    });

    test('alt+backspace deletes word (same as ctrl+w)', () {
      type('hello world');
      final action = editor.handle(KeyEvent(Key.backspace, alt: true));
      expect(action, InputAction.changed);
      expect(editor.text, 'hello ');
      expect(editor.cursor, 6);
    });

    test('alt+backspace at beginning returns null', () {
      type('hello');
      key(Key.home);
      expect(editor.handle(KeyEvent(Key.backspace, alt: true)), isNull);
    });

    test('alt+char is swallowed (not inserted)', () {
      type('hello');
      final action = editor.handle(CharEvent('f', alt: true));
      expect(action, isNull);
      expect(editor.text, 'hello');
    });
  });

  group('edge cases', () {
    test('empty buffer is empty', () {
      expect(editor.isEmpty, isTrue);
      expect(editor.text, '');
      expect(editor.cursor, 0);
    });

    test('non-empty buffer is not empty', () {
      type('a');
      expect(editor.isEmpty, isFalse);
    });

    test('unknown key returns null', () {
      expect(key(Key.unknown), isNull);
    });

    test('resize event returns null', () {
      expect(editor.handle(ResizeEvent(80, 24)), isNull);
    });

    test('clear() resets buffer and cursor', () {
      type('hello');
      editor.clear();
      expect(editor.text, '');
      expect(editor.cursor, 0);
    });

    test('lastSubmitted persists across multiple submits', () {
      type('first');
      key(Key.enter);
      expect(editor.lastSubmitted, 'first');

      type('second');
      key(Key.enter);
      expect(editor.lastSubmitted, 'second');
    });

    test('rapid backspace on single character', () {
      type('a');
      key(Key.backspace);
      expect(editor.text, '');
      expect(key(Key.backspace), isNull);
    });

    test('cursor stays in bounds after delete at end', () {
      type('ab');
      key(Key.delete);
      expect(editor.cursor, 2);
      expect(editor.text, 'ab');
    });

    test('insert after moving cursor left', () {
      type('ac');
      key(Key.left);
      editor.handle(CharEvent('b'));
      expect(editor.text, 'abc');
      expect(editor.cursor, 2);
    });

    test('history resets after submit', () {
      type('a');
      key(Key.enter);
      type('b');
      key(Key.enter);

      // Navigate history
      key(Key.up);
      expect(editor.text, 'b');

      // Submit from history
      key(Key.enter);
      expect(editor.lastSubmitted, 'b');

      // History index should be reset
      key(Key.up);
      expect(editor.text, 'b'); // most recent is 'b' again
    });
  });
}
