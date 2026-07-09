@TestOn('vm')
library;

import 'dart:io';

import 'package:glue_runtimes/src/sprites/cli.dart';
import 'package:glue_runtimes/src/sprites/config.dart';
import 'package:test/test.dart';

/// Exercises the real subprocess timeout path (M23): a client-side
/// timeout must *kill the child* rather than abandon the future and
/// leave the `sprite` process (and the remote command it drives)
/// running. Uses a fake `sprite` binary — a shell script that would
/// write a `finished` marker after a sleep if it were allowed to run to
/// completion. If the child is properly killed, that marker never
/// appears.
void main() {
  group('SpritesCli.execCapture timeout kills the child', () {
    late Directory dir;
    late File startedMarker;
    late File finishedMarker;
    late File script;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('glue-sprite-timeout-');
      startedMarker = File('${dir.path}/started');
      finishedMarker = File('${dir.path}/finished');
      script = File('${dir.path}/fake-sprite.sh');
      // `echo started` proves the child ran; `exec >/dev/null 2>&1`
      // detaches stdio so killing us frees the Dart-side pipes
      // immediately (the orphaned `sleep` won't hold them open). If we
      // survive the sleep we write `finished` — which must NOT happen
      // once we're SIGKILLed.
      await script.writeAsString(
        '#!/bin/sh\n'
        "echo started > '${startedMarker.path}'\n"
        'exec >/dev/null 2>&1\n'
        'sleep 4\n'
        "echo finished > '${finishedMarker.path}'\n",
      );
      await Process.run('chmod', ['+x', script.path]);
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test(
      'returns exit -1 promptly and the child never finishes',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('POSIX shell script fake not available on Windows');
          return;
        }
        final cli = SpritesCli(
          SpritesConfig(
            spriteCliPath: script.path,
            execTimeout: const Duration(minutes: 5),
          ),
        );

        final sw = Stopwatch()..start();
        final res = await cli.execCapture(
          'my-sprite',
          'whatever',
          timeout: const Duration(seconds: 1),
        );
        sw.stop();

        expect(res.exitCode, -1, reason: 'timeout must yield exit -1');
        expect(res.stderr, contains('timed out'));
        expect(
          sw.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'must return at ~timeout, not wait out the 4s child sleep',
        );

        // Wait well past the child's 4s sleep. A leaked (unkilled) child
        // would run to completion and write `finished`; a SIGKILLed one
        // never does. (We assert the negative — that `finished` is absent
        // — rather than that `started` was written, because child-startup
        // scheduling latency under the concurrent test harness is not
        // something this test should depend on.)
        await Future<void>.delayed(const Duration(seconds: 6));
        expect(
          finishedMarker.existsSync(),
          isFalse,
          reason: 'the child must be SIGKILLed on timeout, not left running',
        );
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });
}
