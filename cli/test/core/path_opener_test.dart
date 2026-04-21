import 'dart:io';

import 'package:glue/src/core/path_opener.dart';
import 'package:test/test.dart';

void main() {
  group('openInFileManager', () {
    test('invokes the platform-appropriate launcher for a valid directory',
        () async {
      String? capturedExe;
      List<String>? capturedArgs;

      final ok = await openInFileManager(
        '/tmp/glue-home',
        directoryExists: (_) => true,
        runner: (exe, args) async {
          capturedExe = exe;
          capturedArgs = args;
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(ok, isTrue);
      expect(capturedArgs, ['/tmp/glue-home']);
      if (Platform.isMacOS) {
        expect(capturedExe, 'open');
      } else if (Platform.isWindows) {
        expect(capturedExe, 'explorer');
      } else {
        expect(capturedExe, 'xdg-open');
      }
    });

    test('returns false and skips launch when the directory is missing',
        () async {
      var launched = false;
      final ok = await openInFileManager(
        '/tmp/does-not-exist',
        directoryExists: (_) => false,
        runner: (_, __) async {
          launched = true;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(ok, isFalse);
      expect(launched, isFalse);
    });

    test('returns false for paths with shell metacharacters', () async {
      var launched = false;
      final results = <bool>[];
      for (final badPath in [
        r'/tmp/foo && rm -rf /',
        '/tmp/foo | nc bad 80',
        '/tmp/foo`id`',
        '/tmp/foo\$(whoami)',
        '/tmp/foo\n/evil',
      ]) {
        results.add(await openInFileManager(
          badPath,
          directoryExists: (_) => true,
          runner: (_, __) async {
            launched = true;
            return ProcessResult(0, 0, '', '');
          },
        ));
      }
      expect(results, everyElement(isFalse));
      expect(launched, isFalse);
    });

    test('returns false for empty paths', () async {
      final ok = await openInFileManager(
        '',
        directoryExists: (_) => true,
        runner: (_, __) async => ProcessResult(0, 0, '', ''),
      );
      expect(ok, isFalse);
    });

    test('returns false when the launcher exits non-zero', () async {
      final ok = await openInFileManager(
        '/tmp/glue-home',
        directoryExists: (_) => true,
        runner: (_, __) async => ProcessResult(0, 1, '', 'launch failed'),
      );
      expect(ok, isFalse);
    });

    test('swallows ProcessException from the runner', () async {
      final ok = await openInFileManager(
        '/tmp/glue-home',
        directoryExists: (_) => true,
        runner: (_, __) async =>
            throw const ProcessException('open', [], 'not found', 2),
      );
      expect(ok, isFalse);
    });

    test('accepts non-ASCII paths (accented home directories)', () async {
      String? capturedExe;
      final ok = await openInFileManager(
        '/tmp/héllo/glüe',
        directoryExists: (_) => true,
        runner: (exe, _) async {
          capturedExe = exe;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(ok, isTrue);
      expect(capturedExe, isNotNull);
    });
  });
}
