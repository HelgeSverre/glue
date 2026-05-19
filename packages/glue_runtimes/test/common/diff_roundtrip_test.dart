@TestOn('vm')
library;

import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/diff.dart';

/// Round-trip integration: build a real git repo on disk, mutate it
/// the way an agent would, capture the diff via [captureWorkspaceDiff],
/// and apply it to a *fresh clone* of the baseline. Tree equivalence
/// proves the format-patch output is `git am`-applyable end-to-end.
///
/// Skipped automatically if git isn't on PATH.
void main() {
  late Directory tmp;
  late String gitPath;

  setUpAll(() async {
    final which = await Process.run('which', ['git']);
    if (which.exitCode != 0) {
      markTestSkipped('git not on PATH');
      return;
    }
    gitPath = (which.stdout as String).trim();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('glue-diff-roundtrip-');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  group('captureWorkspaceDiff → git am round-trip', () {
    test('captures untracked files (the silent-loss case)', () async {
      final repo = await _initRepo(tmp, gitPath);
      final baseSha = await _headSha(repo, gitPath);

      // Agent creates an untracked file (no `git add`).
      File('${repo.path}/new_test.dart')
          .writeAsStringSync('void main() {}\n');

      final outcome = await captureWorkspaceDiff(
        executor: HostExecutor(const ShellConfig()),
        runtimeCwd: repo.path,
        bootstrapSha: baseSha,
        runtimeId: 'test',
      );
      expect(outcome, isA<DiffSuccess>());

      final applied = await _applyToFreshClone(
        repo: repo,
        gitPath: gitPath,
        mbox: (outcome as DiffSuccess).patch,
        baseSha: baseSha,
      );
      expect(File('${applied.path}/new_test.dart').existsSync(), isTrue,
          reason: 'untracked file must survive the round trip');
    });

    test('captures binary file changes via --binary', () async {
      final repo = await _initRepo(tmp, gitPath);
      // Add a baseline binary so git's "new binary" path differs from
      // "modified binary" path; we want to exercise the latter.
      final binFile = File('${repo.path}/blob.bin')
        ..writeAsBytesSync(List<int>.generate(64, (i) => i));
      await _run(gitPath, ['add', 'blob.bin'], cwd: repo);
      await _commit(repo, gitPath, 'add binary');
      final baseSha = await _headSha(repo, gitPath);

      // Agent flips the binary.
      binFile.writeAsBytesSync(List<int>.generate(64, (i) => 255 - i));

      final outcome = await captureWorkspaceDiff(
        executor: HostExecutor(const ShellConfig()),
        runtimeCwd: repo.path,
        bootstrapSha: baseSha,
        runtimeId: 'test',
      );
      expect(outcome, isA<DiffSuccess>());

      final applied = await _applyToFreshClone(
        repo: repo,
        gitPath: gitPath,
        mbox: (outcome as DiffSuccess).patch,
        baseSha: baseSha,
      );
      final roundTripped = File('${applied.path}/blob.bin').readAsBytesSync();
      expect(roundTripped, List<int>.generate(64, (i) => 255 - i),
          reason: 'binary blob must survive byte-for-byte');
    });

    test('captures agent commits with preserved authorship', () async {
      final repo = await _initRepo(tmp, gitPath);
      final baseSha = await _headSha(repo, gitPath);

      // Agent makes two commits with distinct messages.
      File('${repo.path}/a.txt').writeAsStringSync('one\n');
      await _run(gitPath, ['add', 'a.txt'], cwd: repo);
      await _commit(repo, gitPath, 'agent: first change');
      File('${repo.path}/b.txt').writeAsStringSync('two\n');
      await _run(gitPath, ['add', 'b.txt'], cwd: repo);
      await _commit(repo, gitPath, 'agent: second change');

      final outcome = await captureWorkspaceDiff(
        executor: HostExecutor(const ShellConfig()),
        runtimeCwd: repo.path,
        bootstrapSha: baseSha,
        runtimeId: 'test',
      );
      expect(outcome, isA<DiffSuccess>());

      final applied = await _applyToFreshClone(
        repo: repo,
        gitPath: gitPath,
        mbox: (outcome as DiffSuccess).patch,
        baseSha: baseSha,
      );
      final log = await _run(
        gitPath,
        ['log', '--format=%s', '$baseSha..HEAD'],
        cwd: applied,
      );
      final messages = (log.stdout as String).trim().split('\n');
      expect(messages, ['agent: second change', 'agent: first change']);
    });
  });
}

Future<Directory> _initRepo(Directory parent, String gitPath) async {
  final repo = await Directory('${parent.path}/repo').create();
  await _run(gitPath, ['init', '-q'], cwd: repo);
  await _run(gitPath, ['config', 'user.email', 'glue@test'], cwd: repo);
  await _run(gitPath, ['config', 'user.name', 'glue test'], cwd: repo);
  File('${repo.path}/README.md').writeAsStringSync('# init\n');
  await _run(gitPath, ['add', 'README.md'], cwd: repo);
  await _commit(repo, gitPath, 'init');
  return repo;
}

Future<Directory> _applyToFreshClone({
  required Directory repo,
  required String gitPath,
  required String mbox,
  required String baseSha,
}) async {
  final clone = await Directory('${repo.parent.path}/clone').create();
  // Clone the source repo at baseSha so `git am` has a clean target
  // matching the bootstrap commit.
  await _run(gitPath, ['clone', '-q', repo.path, clone.path]);
  await _run(gitPath, ['checkout', '-q', baseSha], cwd: clone);

  final mboxFile = File('${repo.parent.path}/session.mbox')
    ..writeAsStringSync(mbox);

  // Try `git am --3way` first (the recommended apply path). Fall back
  // to `git apply --3way` for working-tree-only patches (no mbox
  // header).
  final am = await Process.run(
    gitPath,
    ['am', '--3way', mboxFile.path],
    workingDirectory: clone.path,
  );
  if (am.exitCode != 0) {
    await _run(gitPath, ['am', '--abort'], cwd: clone, ignoreExit: true);
    final apply = await Process.run(
      gitPath,
      ['apply', '--3way', mboxFile.path],
      workingDirectory: clone.path,
    );
    expect(apply.exitCode, 0,
        reason: 'git apply failed:\nstdout=${apply.stdout}\nstderr=${apply.stderr}');
  }
  return clone;
}

Future<String> _headSha(Directory cwd, String gitPath) async {
  final r = await _run(gitPath, ['rev-parse', 'HEAD'], cwd: cwd);
  return (r.stdout as String).trim();
}

Future<void> _commit(Directory cwd, String gitPath, String msg) =>
    _run(gitPath, ['commit', '-q', '-m', msg], cwd: cwd);

Future<ProcessResult> _run(
  String exe,
  List<String> args, {
  Directory? cwd,
  bool ignoreExit = false,
}) async {
  final r = await Process.run(exe, args, workingDirectory: cwd?.path);
  if (!ignoreExit && r.exitCode != 0) {
    fail('$exe ${args.join(' ')} exited ${r.exitCode}\n'
        'stdout: ${r.stdout}\nstderr: ${r.stderr}');
  }
  return r;
}
