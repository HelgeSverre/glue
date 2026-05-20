@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/bootstrap.dart';

/// Verifies WorkspaceBootstrap's strategy selection: prefers bundle
/// when transport supports it AND bundle fits, falls back to
/// clone-from-remote otherwise. Uses a real on-disk repo + a fake
/// transport whose upload writes to a host path the sandbox-side
/// `git clone <path>` actually reads — so the test exercises the
/// full host→sandbox→clone round trip.
void main() {
  late Directory tmp;

  setUpAll(() async {
    final which = await Process.run('which', ['git']);
    if (which.exitCode != 0) markTestSkipped('git not on PATH');
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('glue-bundle-boot-');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('WorkspaceBootstrap via BootstrapBundleTransport', () {
    test('takes the bundle path on a non-git host (no remote needed)',
        () async {
      // Host workspace: a plain non-git directory.
      final hostCwd = await Directory('${tmp.path}/host').create();
      File('${hostCwd.path}/main.dart').writeAsStringSync('void main() {}\n');

      // The "sandbox" filesystem is just another temp dir; the fake
      // transport stages uploads there and runs git commands against
      // the local filesystem.
      final sandboxDir = await Directory('${tmp.path}/sandbox').create();
      final transport = _FakeBundleTransport(sandboxDir);

      final ws = WorkspaceBootstrap(
        exec: transport,
        sessionId: 'test-session',
      );
      final result = await ws.bootstrap(
        hostCwd: hostCwd.path,
        runtimeCwd: '${sandboxDir.path}/workspace',
      );

      expect(result.resumed, isFalse);
      expect(result.bootstrapSha, hasLength(40));
      expect(
          File('${sandboxDir.path}/workspace/main.dart').existsSync(), isTrue);
    });

    test('captures uncommitted host changes (user\'s broken scenario)',
        () async {
      // Host: a git repo with uncommitted edits — the exact case the
      // user originally complained about.
      final hostCwd = await Directory('${tmp.path}/host').create();
      await _git(['init', '-q'], hostCwd);
      await _git(['config', 'user.email', 'test@test'], hostCwd);
      await _git(['config', 'user.name', 'test'], hostCwd);
      File('${hostCwd.path}/feature.dart').writeAsStringSync('// v1\n');
      await _git(['add', 'feature.dart'], hostCwd);
      await _git(['commit', '-q', '-m', 'v1'], hostCwd);
      // Agent's would-be view: uncommitted v2:
      File('${hostCwd.path}/feature.dart').writeAsStringSync('// v2 wip\n');

      final sandboxDir = await Directory('${tmp.path}/sandbox').create();
      final transport = _FakeBundleTransport(sandboxDir);

      final ws = WorkspaceBootstrap(
        exec: transport,
        sessionId: 'test',
      );
      await ws.bootstrap(
        hostCwd: hostCwd.path,
        runtimeCwd: '${sandboxDir.path}/workspace',
      );

      final inSandbox =
          File('${sandboxDir.path}/workspace/feature.dart').readAsStringSync();
      expect(inSandbox, '// v2 wip\n',
          reason:
              'sandbox must see the uncommitted edit, not the committed v1');
    });

    test('raises BootstrapException(clone-bundle) when sandbox clone fails',
        () async {
      // Regression for a bug where the clone-bundle shell chain ended
      // in `|| true`, which swallowed `git clone` failures and let
      // bootstrap proceed with an empty workspace. The fake transport
      // here always exits non-zero from `run` to simulate the failure.
      final hostCwd = await Directory('${tmp.path}/host').create();
      File('${hostCwd.path}/x.txt').writeAsStringSync('x\n');
      final sandboxDir = await Directory('${tmp.path}/sandbox').create();

      final transport = _AlwaysFailingCloneTransport(sandboxDir);
      final ws = WorkspaceBootstrap(
        exec: transport,
        sessionId: 'test',
      );
      await expectLater(
        ws.bootstrap(
          hostCwd: hostCwd.path,
          runtimeCwd: '${sandboxDir.path}/workspace',
        ),
        throwsA(isA<BootstrapException>()
            .having((e) => e.stage, 'stage', 'clone-bundle')
            .having((e) => e.kind, 'kind', BootstrapErrorKind.cloneBundle)),
      );
    });

    test('deletes the host-side bundle file when size cap forces fallback',
        () async {
      // Regression for: bundle file leaked under <bundleBaseDir>
      // whenever the runtime cap was exceeded.
      final hostCwd = await Directory('${tmp.path}/host').create();
      await _git(['init', '-q'], hostCwd);
      await _git(['config', 'user.email', 'test@test'], hostCwd);
      await _git(['config', 'user.name', 'test'], hostCwd);
      File('${hostCwd.path}/a.txt').writeAsStringSync('a\n');
      await _git(['add', 'a.txt'], hostCwd);
      await _git(['commit', '-q', '-m', 'init'], hostCwd);
      final sandboxDir = await Directory('${tmp.path}/sandbox').create();
      final bundleBase = await Directory('${tmp.path}/glue').create();
      final transport = _FakeBundleTransport(sandboxDir, bundleSizeCapBytes: 1);
      final ws = WorkspaceBootstrap(
        exec: transport,
        sessionId: 'leak-test',
        bundleBaseDir: bundleBase.path,
      );
      // Fallback to clone-from-remote will fail (no remote configured),
      // but that's not what we're testing here — just verify the bundle
      // file is gone.
      await expectLater(
        ws.bootstrap(
          hostCwd: hostCwd.path,
          runtimeCwd: '${sandboxDir.path}/workspace',
        ),
        throwsA(isA<BootstrapException>()),
      );
      final bundleFile = File('${bundleBase.path}/bootstrap.bundle');
      expect(bundleFile.existsSync(), isFalse,
          reason: 'bundle file should be deleted when size cap forces '
              'fallback');
    });

    test('falls back to clone-from-remote when bundle exceeds size cap',
        () async {
      // Fake transport with a tiny cap. A 50-byte file → bundle will
      // be a few hundred bytes minimum, so the cap of 1 byte forces
      // the fallback path.
      final hostCwd = await Directory('${tmp.path}/host').create();
      await _git(['init', '-q'], hostCwd);
      await _git(['config', 'user.email', 'test@test'], hostCwd);
      await _git(['config', 'user.name', 'test'], hostCwd);
      File('${hostCwd.path}/a.txt').writeAsStringSync('a\n');
      await _git(['add', 'a.txt'], hostCwd);
      await _git(['commit', '-q', '-m', 'init'], hostCwd);
      // No remote configured → clone fallback will also fail; we
      // assert the *fallback was tried* by catching the clone-stage
      // error rather than an upload-stage one.

      final sandboxDir = await Directory('${tmp.path}/sandbox').create();
      final transport = _FakeBundleTransport(sandboxDir, bundleSizeCapBytes: 1);

      final ws = WorkspaceBootstrap(
        exec: transport,
        sessionId: 'test',
      );
      await expectLater(
        ws.bootstrap(
          hostCwd: hostCwd.path,
          runtimeCwd: '${sandboxDir.path}/workspace',
        ),
        throwsA(
            isA<BootstrapException>().having((e) => e.stage, 'stage', 'clone')),
      );
    });
  });
}

Future<void> _git(List<String> args, Directory cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd.path);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} failed in ${cwd.path}: ${r.stderr}');
  }
}

/// In-process stand-in for a real cloud BootstrapBundleTransport.
/// `uploadBytes` writes to the sandbox temp dir; `run` shells out to
/// `sh -c` with that temp dir as cwd, so paths like
/// `/tmp/glue-bootstrap.bundle` resolve naturally against
/// `<sandboxDir>/tmp/glue-bootstrap.bundle`.
class _FakeBundleTransport implements BootstrapBundleTransport {
  _FakeBundleTransport(this.sandboxDir, {this.bundleSizeCapBytes = 1 << 30});

  final Directory sandboxDir;
  @override
  final int bundleSizeCapBytes;

  @override
  Future<void> uploadBytes(String runtimePath, List<int> bytes) async {
    final dest = File('${sandboxDir.path}$runtimePath');
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes);
  }

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    // Rewrite sandbox-absolute paths into our sandboxDir so the test
    // doesn't need root to write under `/tmp/glue-bootstrap.bundle`.
    final rewritten = shellCommand.replaceAll('/tmp/glue-bootstrap.bundle',
        '${sandboxDir.path}/tmp/glue-bootstrap.bundle');
    final r = await Process.run('sh', ['-c', rewritten]);
    return BootstrapExecResult(
      exitCode: r.exitCode,
      output: '${r.stdout}${r.stderr}',
    );
  }
}

/// Transport whose [run] always exits non-zero — used to verify that
/// a failing `git clone` inside the sandbox is surfaced as
/// `BootstrapException(clone-bundle)` and not swallowed.
class _AlwaysFailingCloneTransport implements BootstrapBundleTransport {
  _AlwaysFailingCloneTransport(this.sandboxDir);
  final Directory sandboxDir;

  @override
  int get bundleSizeCapBytes => 1 << 30;

  @override
  Future<void> uploadBytes(String runtimePath, List<int> bytes) async {
    final dest = File('${sandboxDir.path}$runtimePath');
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes);
  }

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    // First call is the `test -d /workspace/.git` probe — answer
    // "doesn't exist" so the bootstrap proceeds to the bundle path.
    if (shellCommand.startsWith('test -d')) {
      return const BootstrapExecResult(exitCode: 1, output: '');
    }
    // Every subsequent command (including the bundle clone) fails.
    return const BootstrapExecResult(
      exitCode: 128,
      output: 'fatal: simulated clone failure',
    );
  }
}
