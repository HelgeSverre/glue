/// Live integration smoke test for the Sprites adapter.
///
/// Skipped by default — the `cloud-sprites` tag in `dart_test.yaml`
/// gates this on opt-in via `dart test --run-skipped -t cloud-sprites`
/// (or `just sprites` from the repo root).
///
/// Requires the `sprite` CLI in `$PATH` and an authenticated session
/// (`sprite login`). Creates a real sprite, exercises exec + FS, and
/// deletes the sprite on completion.
@Tags(['cloud-sprites'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/sprites.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';

void main() {
  group('Sprites live integration', () {
    setUpAll(() async {
      // Skip if the `sprite` CLI isn't installed or the user isn't
      // logged in — surfaced as a clean test skip, not a failure.
      try {
        final res = await Process.run('sprite', ['list']);
        if (res.exitCode != 0) {
          markTestSkipped(
            'sprite CLI not authenticated (run `sprite login` first)',
          );
        }
      } on ProcessException {
        markTestSkipped('sprite CLI not on PATH');
      }
    });

    test(
      'create / exec / read / write / delete round-trip',
      () async {
        const config = SpritesConfig();
        final cli = SpritesCli(config);
        final name =
            'glue-it-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

        try {
          await cli.createSprite(name);

          // Sync exec
          final exec = await cli.execCapture(name, 'echo hello');
          expect(exec.exitCode, 0);
          expect(exec.stdout.trim(), 'hello');

          // FS round-trip via the extension helpers
          await cli.writeFileBytes(
            name,
            '/tmp/glue-it.txt',
            'glue-integration\n'.codeUnits,
          );
          final bytes = await cli.readFileBytes(name, '/tmp/glue-it.txt');
          expect(String.fromCharCodes(bytes).trim(), 'glue-integration');

          final entries = await cli.listDir(name, '/tmp');
          expect(entries.any((e) => e.name == 'glue-it.txt'), isTrue);
        } finally {
          await cli.deleteSprite(name);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
