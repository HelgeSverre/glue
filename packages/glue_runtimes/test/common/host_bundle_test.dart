@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/host_bundle.dart';

/// Verifies the host-side bundle builder produces a single-commit
/// bundle that captures the working tree (Phase 2 of the
/// cloud-runtimes-correctness-plan). All tests use a temp directory
/// so we never touch the user's actual repo state.
void main() {
  late Directory tmp;
  late Directory sessionDir;

  setUpAll(() async {
    final which = await Process.run('which', ['git']);
    if (which.exitCode != 0) markTestSkipped('git not on PATH');
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('glue-host-bundle-');
    sessionDir = Directory('${tmp.path}/.glue/session');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('buildHostBundle', () {
    test('builds a bundle from a non-git directory (no remote needed)',
        () async {
      final src = await Directory('${tmp.path}/src').create();
      File('${src.path}/hello.txt').writeAsStringSync('hi\n');

      final bundle = await buildHostBundle(
        hostCwd: src.path,
        sessionId: 'test-session',
        sessionDir: sessionDir.path,
      );
      expect(bundle.path.existsSync(), isTrue);
      expect(bundle.bundleSha, hasLength(40));
      expect(bundle.sizeBytes, greaterThan(0));

      // The bundle should be clonable into a fresh dir and contain
      // the source file.
      final clone = await Directory('${tmp.path}/clone').create();
      final r = await Process.run(
        'git',
        ['clone', '-q', bundle.path.path, clone.path],
      );
      expect(r.exitCode, 0, reason: 'bundle should be clonable');
      expect(File('${clone.path}/hello.txt').existsSync(), isTrue);
    });

    test('captures uncommitted changes in an existing git repo', () async {
      final src = await Directory('${tmp.path}/src').create();
      await _git(['init', '-q'], src);
      await _git(['config', 'user.email', 'test@test'], src);
      await _git(['config', 'user.name', 'test'], src);
      File('${src.path}/committed.txt').writeAsStringSync('committed\n');
      await _git(['add', 'committed.txt'], src);
      await _git(['commit', '-q', '-m', 'init'], src);
      // The agent's would-be uncommitted change:
      File('${src.path}/dirty.txt').writeAsStringSync('uncommitted\n');

      final bundle = await buildHostBundle(
        hostCwd: src.path,
        sessionId: 'test-session',
        sessionDir: sessionDir.path,
      );
      final clone = await Directory('${tmp.path}/clone').create();
      await _git(['clone', '-q', bundle.path.path, clone.path], null);
      expect(File('${clone.path}/dirty.txt').existsSync(), isTrue,
          reason: 'uncommitted file must be in the bundle');
    });

    test('respects .gitignore via `git add -A`', () async {
      final src = await Directory('${tmp.path}/src').create();
      File('${src.path}/.gitignore').writeAsStringSync('ignored.txt\n');
      File('${src.path}/included.txt').writeAsStringSync('keep me\n');
      File('${src.path}/ignored.txt').writeAsStringSync('skip me\n');

      final bundle = await buildHostBundle(
        hostCwd: src.path,
        sessionId: 'test',
        sessionDir: sessionDir.path,
      );
      final clone = await Directory('${tmp.path}/clone').create();
      await _git(['clone', '-q', bundle.path.path, clone.path], null);
      expect(File('${clone.path}/included.txt').existsSync(), isTrue);
      expect(File('${clone.path}/ignored.txt').existsSync(), isFalse,
          reason: '.gitignore should be honored');
    });

    test('captures originRemoteUrl when host has one', () async {
      final src = await Directory('${tmp.path}/src').create();
      await _git(['init', '-q'], src);
      await _git(['config', 'user.email', 'test@test'], src);
      await _git(['config', 'user.name', 'test'], src);
      await _git(
        ['remote', 'add', 'origin', 'https://example.invalid/foo.git'],
        src,
      );
      File('${src.path}/a.txt').writeAsStringSync('a\n');

      final bundle = await buildHostBundle(
        hostCwd: src.path,
        sessionId: 'test',
        sessionDir: sessionDir.path,
      );
      expect(bundle.originRemoteUrl, 'https://example.invalid/foo.git');
    });

    test('throws HostBundleException when host cwd does not exist',
        () async {
      await expectLater(
        buildHostBundle(
          hostCwd: '${tmp.path}/nonexistent',
          sessionId: 'test',
          sessionDir: sessionDir.path,
        ),
        throwsA(isA<HostBundleException>()),
      );
    });
  });
}

Future<void> _git(List<String> args, Directory? cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd?.path);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${r.stderr}');
  }
}
