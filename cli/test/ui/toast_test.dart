import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  // Real timers, just configured tight so tests run sub-second.
  const fast = Duration(milliseconds: 30);

  group('Toast.show', () {
    test('marks visible and calls onRender synchronously', () {
      var renders = 0;
      final toast = Toast(
        onRender: () => renders++,
        successDuration: fast,
        errorDuration: fast,
      );
      expect(toast.visible, isFalse);
      toast.show('Copied 3 lines');
      expect(toast.visible, isTrue);
      expect(renders, 1);
      toast.dismiss();
    });

    test('auto-dismisses after successDuration and re-renders', () async {
      var renders = 0;
      final toast = Toast(onRender: () => renders++, successDuration: fast);
      toast.show('done');
      await Future<void>.delayed(fast * 3);
      expect(toast.visible, isFalse);
      expect(renders, 2); // show + auto-dismiss
    });

    test('a second show() cancels the prior timer (no double-dismiss)',
        () async {
      var renders = 0;
      final toast = Toast(
        onRender: () => renders++,
        successDuration: const Duration(milliseconds: 25),
      );
      toast.show('first');
      toast.show('second');
      // Long enough for the first timer to have fired if it weren't cancelled,
      // not long enough for the second.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(toast.visible, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(toast.visible, isFalse);
      // show #1 + show #2 + final dismiss = 3
      expect(renders, 3);
    });

    test('error kind uses errorDuration not successDuration', () async {
      final toast = Toast(
        onRender: () {},
        successDuration: const Duration(milliseconds: 10),
        errorDuration: const Duration(milliseconds: 60),
      );
      toast.show('boom', kind: ToastKind.error);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(toast.visible, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(toast.visible, isFalse);
    });
  });

  group('Toast.dismiss', () {
    test('cancels pending timer and hides immediately', () async {
      var renders = 0;
      final toast = Toast(
        onRender: () => renders++,
        successDuration: const Duration(milliseconds: 50),
      );
      toast.show('x');
      toast.dismiss();
      expect(toast.visible, isFalse);
      expect(renders, 2);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(renders, 2); // timer was cancelled — no extra render
    });

    test('dismiss while not visible is a silent no-op', () {
      var renders = 0;
      final toast = Toast(onRender: () => renders++);
      toast.dismiss();
      expect(renders, 0);
    });
  });

  group('Toast.cellWidth and renderLine', () {
    test('cellWidth is zero when not visible', () {
      final toast = Toast(onRender: () {});
      expect(toast.cellWidth, 0);
      expect(toast.renderLine(), isEmpty);
    });

    test('cellWidth matches the rendered chip width', () {
      final toast = Toast(onRender: () {});
      toast.show('Copied 3 lines');
      // 1 pad + 1 glyph + 1 sep + 14 chars + 1 pad = 18
      expect(toast.cellWidth, 18);
      expect(visibleLength(toast.renderLine()), 18);
      toast.dismiss();
    });

    test('renderLine includes charcoal bg and yellow glyph for success', () {
      final toast = Toast(onRender: () {});
      toast.show('ok');
      final line = toast.renderLine();
      // Charcoal background (256-colour 236).
      expect(line, contains('\x1b[48;5;236m'));
      // Yellow glyph fg (256-colour 220).
      expect(line, contains('\x1b[38;5;220m'));
      // Reset at end so styling doesn't leak.
      expect(line, endsWith('\x1b[0m'));
      // The visible glyph itself.
      expect(stripAnsi(line), equals(' ✓ ok '));
      toast.dismiss();
    });

    test('renderLine uses red glyph for error kind', () {
      final toast = Toast(onRender: () {});
      toast.show('Clipboard unavailable', kind: ToastKind.error);
      final line = toast.renderLine();
      expect(line, contains('\x1b[38;5;196m'));
      expect(stripAnsi(line), equals(' ! Clipboard unavailable '));
      toast.dismiss();
    });

    test('cellWidth accounts for wide glyphs in the message', () {
      final toast = Toast(onRender: () {});
      toast.show('漢字'); // 2 CJK glyphs = 4 cells
      // 1 pad + 1 glyph + 1 sep + 4 cells + 1 pad = 8
      expect(toast.cellWidth, 8);
      toast.dismiss();
    });
  });
}
