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

    test(
      'picks macOS command on mac',
      () async {
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
          expect(calls.single.exe, 'cmd');
          expect(calls.single.args.first, '/c');
        } else {
          expect(calls.single.exe, 'xdg-open');
        }
      },
    );
  });
}
