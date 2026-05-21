/// End-to-end tests for `glue mcp add|remove|enable|disable`. We drive
/// the real binary via `Process.start` with a scratch `GLUE_HOME` so the
/// arg parser, the config-file path resolution, and `McpConfigWriter`
/// are all exercised together.
///
/// Heavy by design — each test spawns a Dart VM. Keep the count small;
/// per-edge-case coverage lives in `mcp_config_writer_test.dart`.
library;

import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _runGlue(
  List<String> args, {
  required String glueHome,
}) async {
  final process = await Process.start(
    'dart',
    ['run', '--verbosity=error', 'bin/glue.dart', ...args],
    workingDirectory: Directory.current.path,
    runInShell: true,
    environment: {...Platform.environment, 'GLUE_HOME': glueHome},
  );
  await process.stdin.close();
  final out = await process.stdout
      .transform(const SystemEncoding().decoder)
      .join();
  final err = await process.stderr
      .transform(const SystemEncoding().decoder)
      .join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, out, err);
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_mcp_cmd_test_');

void main() {
  group('glue mcp', () {
    test(
      'full lifecycle: add stdio → list → disable → enable → remove',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));

        // 1. add
        var r = await _runGlue([
          'mcp',
          'add',
          'demo',
          '--transport',
          'stdio',
          '--',
          'echo',
          'hi',
        ], glueHome: dir.path);
        expect(r.exitCode, 0, reason: 'add stderr: ${r.stderr}');
        expect(r.stdout.toString(), contains('Added stdio server "demo"'));
        final configContent = File(
          '${dir.path}/config.yaml',
        ).readAsStringSync();
        expect(configContent, contains('demo:'));
        expect(configContent, contains('command: echo'));

        // 2. list shows it as enabled
        r = await _runGlue(['mcp', 'list'], glueHome: dir.path);
        expect(r.exitCode, 0);
        expect(r.stdout.toString(), contains('demo'));
        expect(r.stdout.toString(), contains('enabled'));

        // 3. disable + list shows disabled
        r = await _runGlue(['mcp', 'disable', 'demo'], glueHome: dir.path);
        expect(r.exitCode, 0);
        r = await _runGlue(['mcp', 'list'], glueHome: dir.path);
        expect(r.stdout.toString(), contains('disabled'));

        // 4. enable round-trips back
        r = await _runGlue(['mcp', 'enable', 'demo'], glueHome: dir.path);
        expect(r.exitCode, 0);
        r = await _runGlue(['mcp', 'list'], glueHome: dir.path);
        expect(r.stdout.toString(), contains('enabled'));

        // 5. remove
        r = await _runGlue(['mcp', 'remove', 'demo'], glueHome: dir.path);
        expect(r.exitCode, 0);
        expect(r.stdout.toString(), contains("Removed server 'demo'"));
        final after = File('${dir.path}/config.yaml').readAsStringSync();
        expect(after, isNot(contains('demo:')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('add rejects invalid id', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));

      final r = await _runGlue([
        'mcp',
        'add',
        'Bad Id!',
        '--transport',
        'stdio',
        '--',
        'echo',
      ], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(r.stderr.toString(), contains('Invalid id'));
    });

    test('add requires --transport', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));

      final r = await _runGlue([
        'mcp',
        'add',
        'foo',
        '--',
        'echo',
      ], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(r.stderr.toString(), contains('--transport is required'));
    });

    test('add stdio without command rest is an error', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));

      final r = await _runGlue([
        'mcp',
        'add',
        'foo',
        '--transport',
        'stdio',
      ], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(r.stderr.toString(), contains('stdio transport needs a command'));
    });

    test('add http requires --url and rejects stdio-only flags', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));

      // Missing --url
      var r = await _runGlue([
        'mcp',
        'add',
        'foo',
        '--transport',
        'http',
      ], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(r.stderr.toString(), contains('--url is required'));

      // --env with http
      r = await _runGlue([
        'mcp',
        'add',
        'foo',
        '--transport',
        'http',
        '--url',
        'https://example.com/mcp',
        '-e',
        'KEY=val',
      ], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(
        r.stderr.toString(),
        contains('--env and --cwd are only valid for --transport stdio'),
      );
    });

    test('remove of unknown id exits 1', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/config.yaml').createSync(recursive: true);

      final r = await _runGlue(['mcp', 'remove', 'ghost'], glueHome: dir.path);
      expect(r.exitCode, 1);
      expect(r.stderr.toString(), contains("ghost' is not in config.yaml"));
    });

    test(
      'tools warns and exits 1 when server is disabled',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));

        var r = await _runGlue([
          'mcp',
          'add',
          'parked',
          '--transport',
          'stdio',
          '--disabled',
          '--',
          'echo',
          'hi',
        ], glueHome: dir.path);
        expect(r.exitCode, 0, reason: r.stderr.toString());

        r = await _runGlue([
          'mcp',
          'tools',
          'parked',
        ], glueHome: dir.path).timeout(const Duration(seconds: 15));
        expect(r.exitCode, 1);
        expect(r.stderr.toString(), contains('disabled'));
        expect(r.stderr.toString(), contains('glue mcp enable parked'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'tools (no arg) with empty config prints friendly message',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));

        final r = await _runGlue([
          'mcp',
          'tools',
        ], glueHome: dir.path).timeout(const Duration(seconds: 30));
        expect(r.exitCode, 0, reason: r.stderr.toString());
        expect(r.stdout.toString(), contains('No MCP servers configured'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'tools (no arg) with only disabled servers groups them as disabled',
      () async {
        final dir = _scratch();
        addTearDown(() => dir.deleteSync(recursive: true));

        var r = await _runGlue([
          'mcp',
          'add',
          'parked',
          '--transport',
          'stdio',
          '--disabled',
          '--',
          'echo',
          'hi',
        ], glueHome: dir.path);
        expect(r.exitCode, 0, reason: r.stderr.toString());

        r = await _runGlue([
          'mcp',
          'tools',
        ], glueHome: dir.path).timeout(const Duration(seconds: 30));
        expect(r.exitCode, 0, reason: r.stderr.toString());
        final out = r.stdout.toString();
        expect(out, contains('parked'));
        expect(out, contains('disabled'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('add http with --auth bearer hints at follow-up auth set', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));

      final r = await _runGlue([
        'mcp',
        'add',
        'api',
        '--transport',
        'http',
        '--url',
        'https://api.example.com/mcp',
        '--auth',
        'bearer',
      ], glueHome: dir.path);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      expect(r.stdout.toString(), contains('glue mcp auth set api --bearer'));
      final yaml = File('${dir.path}/config.yaml').readAsStringSync();
      expect(yaml, contains('kind: bearer'));
    });
  });
}
