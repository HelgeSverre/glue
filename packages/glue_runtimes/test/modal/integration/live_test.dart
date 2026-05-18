/// Live integration smoke test for the Modal adapter.
///
/// Skipped by default — the `cloud-modal` tag in `dart_test.yaml`
/// gates this on opt-in via `dart test --run-skipped -t cloud-modal`
/// (or `just modal` from the repo root).
///
/// Requires the `modal` CLI installed and authenticated
/// (`modal token set ...`). Creates a real sandbox under the
/// configured modal app and tears it down at the end.
@Tags(['cloud-modal'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/modal.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';

void main() {
  group('Modal live integration', () {
    setUpAll(() async {
      try {
        final res = await Process.run('modal', ['profile', 'current']);
        if (res.exitCode != 0) {
          markTestSkipped(
            'modal CLI not authenticated (run `modal token set` first)',
          );
        }
      } on ProcessException {
        markTestSkipped('modal CLI not on PATH');
      }
    });

    test('start / exec / read / write / shutdown round-trip', () async {
      const config = ModalConfig(appName: 'glue-it');
      final sidecar = ModalSidecar(config);

      try {
        await sidecar.start();

        // Sync exec
        final exec = await sidecar.execCapture('echo hello');
        expect(exec.exitCode, 0);
        expect(exec.stdout.trim(), 'hello');

        // FS round-trip via sidecar helpers
        await sidecar.writeFile(
          '/tmp/glue-it.txt',
          'glue-modal-integration\n'.codeUnits,
        );
        final bytes = await sidecar.readFile('/tmp/glue-it.txt');
        expect(String.fromCharCodes(bytes).trim(), 'glue-modal-integration');

        final entries = await sidecar.listDir('/tmp');
        expect(entries.any((e) => e.name == 'glue-it.txt'), isTrue);
      } finally {
        await sidecar.shutdown();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
