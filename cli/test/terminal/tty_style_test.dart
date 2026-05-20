import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';
import 'package:test/test.dart';

void main() {
  group('styledOrPlain', () {
    test('returns plain text when ANSI is disabled', () {
      final result =
          styledOrPlain('hello', (s) => s.bold.red, ansiEnabled: false);
      expect(result, equals('hello'));
    });

    test('emits ANSI sequences when ANSI is enabled', () {
      final result = styledOrPlain('hello', (s) => s.bold, ansiEnabled: true);
      expect(result, isNot(equals('hello')));
      expect(result, contains('hello'));
      expect(result, contains('\x1b['));
    });
  });

  group('brand markers in non-TTY context (dart test default)', () {
    // `dart test` has no TTY, so brand markers must collapse to plain
    // glyphs. This is what users see when piping `glue mcp list | grep`.
    test('brandDot is plain "●" with no ANSI', () {
      expect(brandDot, equals('●'));
    });

    test('markerOk / markerWarn / markerError / markerInfo are plain glyphs',
        () {
      expect(markerOk, equals('✓'));
      expect(markerWarn, equals('!'));
      expect(markerError, equals('✗'));
      expect(markerInfo, equals('·'));
    });
  });
}
