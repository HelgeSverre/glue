import 'package:glue/glue.dart';
import 'package:glue/src/terminal/screen_buffer.dart';
import 'package:test/test.dart';

void main() {
  // ── Cell ──────────────────────────────────────────────────────────────

  group('Cell', () {
    test('same char and style are equal', () {
      expect(Cell('a', style: AnsiStyle.bold),
          equals(Cell('a', style: AnsiStyle.bold)));
    });

    test('different char are not equal', () {
      expect(Cell('a'), isNot(equals(Cell('b'))));
    });

    test('different style are not equal', () {
      expect(Cell('a', style: AnsiStyle.bold),
          isNot(equals(Cell('a', style: AnsiStyle.dim))));
    });

    test('null style vs non-null style are not equal', () {
      expect(Cell('a'), isNot(equals(Cell('a', style: AnsiStyle.red))));
    });

    test('hashCode is consistent with equality', () {
      final a = Cell('x', style: AnsiStyle.green);
      final b = Cell('x', style: AnsiStyle.green);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ── ConfirmModal ──────────────────────────────────────────────────────

  group('ConfirmModal', () {
    ConfirmModal makeModal() => ConfirmModal(
          title: 'Apply changes?',
          bodyLines: ['File: foo.dart', 'Size: 42 bytes'],
          choices: [
            const ModalChoice('Yes', 'y'),
            const ModalChoice('No', 'n'),
            const ModalChoice('Always', 'a'),
          ],
        );

    test('isComplete is false initially', () {
      final modal = makeModal();
      expect(modal.isComplete, isFalse);
    });

    test('selected starts at 0', () {
      final modal = makeModal();
      expect(modal.selected, equals(0));
    });

    test('Key.right moves selection forward', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.right));
      expect(modal.selected, equals(1));
    });

    test('Key.right wraps around', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.right));
      modal.handleEvent(KeyEvent(Key.right));
      modal.handleEvent(KeyEvent(Key.right));
      expect(modal.selected, equals(0)); // wraps from 2 -> 0
    });

    test('Key.left moves selection backward', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.right)); // -> 1
      modal.handleEvent(KeyEvent(Key.left)); // -> 0
      expect(modal.selected, equals(0));
    });

    test('Key.left clamps at 0', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.left));
      expect(modal.selected, equals(0));
    });

    test('Key.enter completes with selected index', () async {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.right)); // select 1
      modal.handleEvent(KeyEvent(Key.enter));
      expect(modal.isComplete, isTrue);
      expect(await modal.result, equals(1));
    });

    test('Key.escape completes with "no" index', () async {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.escape));
      expect(modal.isComplete, isTrue);
      expect(await modal.result, equals(1)); // index of 'n' hotkey
    });

    test('CharEvent matching hotkey completes immediately', () async {
      final modal = makeModal();
      modal.handleEvent(CharEvent('a'));
      expect(modal.isComplete, isTrue);
      expect(await modal.result, equals(2)); // 'Always' is index 2
    });

    test('CharEvent matching hotkey is case-insensitive', () async {
      final modal = makeModal();
      modal.handleEvent(CharEvent('Y'));
      expect(modal.isComplete, isTrue);
      expect(await modal.result, equals(0));
    });

    test('handleEvent returns false after completion', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.enter));
      expect(modal.handleEvent(KeyEvent(Key.right)), isFalse);
    });

    test('render produces non-empty output', () {
      final modal = makeModal();
      final lines = modal.render(80);
      expect(lines, isNotEmpty);
    });

    test('render works at small width', () {
      final modal = makeModal();
      final lines = modal.render(10);
      expect(lines, isNotEmpty);
    });

    test('render includes title', () {
      final modal = makeModal();
      final lines = modal.render(80);
      final joined = lines.join('\n');
      expect(joined, contains('Apply changes?'));
    });

    test('render includes body lines', () {
      final modal = makeModal();
      final lines = modal.render(80);
      final joined = lines.join('\n');
      expect(joined, contains('foo.dart'));
      expect(joined, contains('42 bytes'));
    });

    test('render includes choice labels', () {
      final modal = makeModal();
      final lines = modal.render(80);
      final joined = lines.join('\n');
      expect(joined, contains('(y) Yes'));
      expect(joined, contains('(n) No'));
      expect(joined, contains('(a) Always'));
    });

    test('tab moves selection forward like right', () {
      final modal = makeModal();
      modal.handleEvent(KeyEvent(Key.tab));
      expect(modal.selected, equals(1));
    });
  });
}
