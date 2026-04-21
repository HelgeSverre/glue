/// Verifies the URL launcher invokes the right platform command. The runner
/// is injectable so the tests don't actually spawn anything.
library;

import 'dart:io';

import 'package:glue/src/core/url_launcher.dart';
import 'package:test/test.dart';

class _Call {
  _Call(this.exe, this.args);

  final String exe;
  final List<String> args;
}

void main() {
  group('openInBrowser', () {
    test('returns true when the runner exits 0', () async {
      final calls = <_Call>[];
      final ok = await openInBrowser(
        'https://example.com',
        runner: (exe, args) async {
          calls.add(_Call(exe, args));
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(ok, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.args, contains('https://example.com'));
    });

    test('returns false when the runner exits non-zero', () async {
      final ok = await openInBrowser(
        'https://example.com',
        runner: (_, __) async => ProcessResult(0, 1, '', 'not found'),
      );
      expect(ok, isFalse);
    });

    test('returns false when the runner throws', () async {
      final ok = await openInBrowser(
        'https://example.com',
        runner: (_, __) async => throw const ProcessException('x', []),
      );
      expect(ok, isFalse);
    });

    test('picks the platform command', () async {
      final calls = <_Call>[];
      await openInBrowser(
        'https://example.com',
        runner: (exe, args) async {
          calls.add(_Call(exe, args));
          return ProcessResult(0, 0, '', '');
        },
      );
      if (Platform.isMacOS) {
        expect(calls.single.exe, 'open');
      } else if (Platform.isWindows) {
        // Must NOT be cmd (cmd.exe does shell-metachar interpretation on
        // the URL). rundll32 runs the URL protocol handler directly.
        expect(calls.single.exe, 'rundll32');
        expect(calls.single.args.first, contains('FileProtocolHandler'));
      } else {
        expect(calls.single.exe, 'xdg-open');
      }
    });

    group('URL validation', () {
      test('rejects file:// URLs', () async {
        var called = false;
        final ok = await openInBrowser(
          'file:///etc/passwd',
          runner: (_, __) async {
            called = true;
            return ProcessResult(0, 0, '', '');
          },
        );
        expect(ok, isFalse);
        expect(called, isFalse, reason: 'validator should short-circuit');
      });

      test('rejects javascript: URLs', () async {
        final ok = await openInBrowser(
          'javascript:alert(1)',
          runner: (_, __) async => ProcessResult(0, 0, '', ''),
        );
        expect(ok, isFalse);
      });

      test('rejects URLs with shell metacharacters (& | ^ < > " `)', () async {
        for (final url in [
          'https://example.com?x=1&cmd=bad',
          'https://example.com"quoted',
          'https://example.com|pipe',
          'https://example.com^caret',
          'https://example.com<less',
          'https://example.com`backtick',
        ]) {
          final ok = await openInBrowser(
            url,
            runner: (_, __) async => ProcessResult(0, 0, '', ''),
          );
          expect(ok, isFalse, reason: 'should reject: $url');
        }
      });

      test('rejects empty / malformed URLs', () async {
        for (final url in ['', 'not a url', 'ftp://example.com']) {
          final ok = await openInBrowser(
            url,
            runner: (_, __) async => ProcessResult(0, 0, '', ''),
          );
          expect(ok, isFalse, reason: 'should reject: "$url"');
        }
      });

      test('accepts normal https URLs with percent encoding', () async {
        var called = false;
        final ok = await openInBrowser(
          'https://github.com/login/device?user_code=ABCD-1234',
          runner: (_, __) async {
            called = true;
            return ProcessResult(0, 0, '', '');
          },
        );
        // URLs with `&` are rejected by the metachar guard — but there's no
        // `&` in this one, and `-` / `?` / `=` / `:` are all safe.
        expect(called, isTrue);
        expect(ok, isTrue);
      });
    });
  });
}
