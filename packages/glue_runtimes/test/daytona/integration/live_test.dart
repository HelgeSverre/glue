/// Live integration smoke test for the Daytona adapter.
///
/// Skipped by default — the `cloud-daytona` tag in `dart_test.yaml`
/// gates this on opt-in via `dart test --run-skipped -t cloud-daytona`
/// (or `just daytona` from the repo root).
///
/// Requires `DAYTONA_API_KEY` in the environment. Creates a real
/// sandbox on the user's Daytona account, exercises exec + FS, and
/// stops it on completion.
@Tags(['cloud-daytona'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/daytona.dart';
import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/runtime.dart';

void main() {
  group('Daytona live integration', () {
    final apiKey = Platform.environment['DAYTONA_API_KEY'] ?? '';

    setUpAll(() {
      if (apiKey.isEmpty) {
        markTestSkipped('DAYTONA_API_KEY not set');
      }
    });

    test('create / exec / read / write / stop round-trip', () async {
      final config = DaytonaConfig(apiKey: apiKey);
      final client = DaytonaClient(config: config);

      DaytonaSandbox? sandbox;
      try {
        sandbox = await client.createSandbox();
        expect(sandbox.id, isNotEmpty);
        expect(sandbox.toolboxBaseUrl, isNotEmpty);

        final exec = await client.execCapture(sandbox, 'echo hello');
        expect(exec.exitCode, 0);
        expect(exec.result.trim(), 'hello');

        await client.writeFile(
          sandbox,
          '/tmp/glue-live-test.txt',
          'glue-live-test\n'.codeUnits,
        );
        final bytes = await client.readFile(
          sandbox,
          '/tmp/glue-live-test.txt',
        );
        expect(String.fromCharCodes(bytes).trim(), 'glue-live-test');

        final entries = await client.listDir(sandbox, '/tmp');
        expect(
          entries.any((e) => e.name == 'glue-live-test.txt'),
          isTrue,
        );
      } finally {
        if (sandbox != null) {
          await client.stopSandbox(sandbox.id);
        }
        client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('DaytonaRuntime.start succeeds on a real git repo', () async {
      final repoRoot = Directory.current.path;
      final runtime = await DaytonaRuntime.start(
        config: DaytonaConfig(apiKey: apiKey),
        hostCwd: repoRoot,
      );
      try {
        expect(runtime.sandbox.id, isNotEmpty);
        expect(runtime.bootstrapSha, isNotNull);
        final entries = await runtime.workspace.list('/workspace');
        expect(entries, isNotEmpty);
      } finally {
        await runtime.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
