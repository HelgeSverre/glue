import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of building a host-side workspace bundle.
class HostBundle {
  /// The bundle file on the host. Caller is responsible for deletion
  /// after upload (the temp git-dir is kept for diagnostics).
  final File path;

  /// SHA of the synthetic commit the bundle wraps. This becomes the
  /// runtime's `bootstrapSha`.
  final String bundleSha;

  /// Bundle file size, used by [BundleBootstrap] to decide whether the
  /// upload fits within the runtime's per-call cap.
  final int sizeBytes;

  /// `remote.origin.url` of the source repo, when one is configured.
  /// Persisted alongside the runtime patch so apply tools can sanity-
  /// check the host.
  final String? originRemoteUrl;

  /// The temp `.git` directory used to build the bundle. Kept on disk
  /// for diagnostics; safe to delete after the session ends.
  final Directory tempGitDir;

  HostBundle({
    required this.path,
    required this.bundleSha,
    required this.sizeBytes,
    required this.tempGitDir,
    this.originRemoteUrl,
  });
}

/// Why [buildHostBundle] couldn't produce a bundle.
class HostBundleException implements Exception {
  final String stage;
  final String message;
  final int? exitCode;
  final String? stderr;
  const HostBundleException({
    required this.stage,
    required this.message,
    this.exitCode,
    this.stderr,
  });
  @override
  String toString() =>
      'HostBundleException($stage${exitCode == null ? '' : ', exit=$exitCode'}): '
      '$message${stderr == null || stderr!.isEmpty ? '' : '\n$stderr'}';
}

/// Builds a single-commit git bundle of [hostCwd] using a temp git-dir
/// overlay, so the user's actual `.git` (if any) is never touched.
///
/// Strategy (Phase 2 of cloud-runtimes-correctness-plan):
///
/// 1. `git --git-dir=<temp> --work-tree=<hostCwd> init`
/// 2. `git ... add -A` — respects `.gitignore` semantics for the
///    overlay; ignored files are dropped
/// 3. `git ... commit -m "glue bootstrap <sessionId>"`
/// 4. `git --git-dir=<temp> bundle create <out>.bundle --all`
///
/// The resulting bundle contains exactly one commit that snapshots
/// the host's current working tree. Sandbox-side bootstrap clones it,
/// recording the synthetic commit SHA as `bootstrapSha`. The diff
/// machinery then captures everything the agent does inside the
/// sandbox relative to that snapshot.
///
/// `git add -A` is the only filter (Q4 default — keep it simple; no
/// `.glueignore` until users ask). To preserve `.env` and other
/// .gitignore'd files the agent needs, the user must temporarily
/// un-ignore them.
///
/// Throws [HostBundleException] when `git` isn't available or any
/// step fails.
Future<HostBundle> buildHostBundle({
  required String hostCwd,
  required String sessionId,
  String? sessionDir,
}) async {
  if (!Directory(hostCwd).existsSync()) {
    throw HostBundleException(
      stage: 'init',
      message: 'host cwd does not exist: $hostCwd',
    );
  }
  // Refuse bare-repo / mirror clones — they have no working tree
  // for `git add -A` to capture, so the bundle would be empty and
  // misleading. (Phase 4: T6 — clear refusal beats silent emptiness.)
  if (await _isBareRepo(hostCwd)) {
    throw const HostBundleException(
      stage: 'init',
      message:
          'host cwd is a bare/mirror git repository; cloud runtimes '
          'need a working tree to mirror. Clone the bare repo to a '
          'regular working tree and re-run from there.',
    );
  }

  final baseDir = sessionDir ?? await _defaultSessionDir(sessionId);
  await Directory(baseDir).create(recursive: true);

  final tempGitDir = Directory(p.join(baseDir, 'bootstrap.git'));
  if (tempGitDir.existsSync()) {
    await tempGitDir.delete(recursive: true);
  }
  await tempGitDir.create(recursive: true);

  final bundlePath = File(p.join(baseDir, 'bootstrap.bundle'));
  if (bundlePath.existsSync()) await bundlePath.delete();

  final env = <String, String>{
    // Cosmetic — keeps `git commit` from prompting for identity on
    // hosts that don't have a global config.
    'GIT_AUTHOR_NAME': 'glue bootstrap',
    'GIT_AUTHOR_EMAIL': 'glue@bootstrap',
    'GIT_COMMITTER_NAME': 'glue bootstrap',
    'GIT_COMMITTER_EMAIL': 'glue@bootstrap',
  };

  await _git(
    ['--git-dir=${tempGitDir.path}', '--work-tree=$hostCwd', 'init', '-q'],
    cwd: hostCwd,
    env: env,
    stage: 'init',
  );

  await _git(
    ['--git-dir=${tempGitDir.path}', '--work-tree=$hostCwd', 'add', '-A'],
    cwd: hostCwd,
    env: env,
    stage: 'add',
  );

  // `--allow-empty` covers the edge case of a completely empty
  // workspace — without it git refuses to commit, blocking bootstrap
  // on what should be a degenerate-but-valid case.
  await _git(
    [
      '--git-dir=${tempGitDir.path}',
      '--work-tree=$hostCwd',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'glue bootstrap $sessionId',
    ],
    cwd: hostCwd,
    env: env,
    stage: 'commit',
  );

  final sha = (await _git(
    ['--git-dir=${tempGitDir.path}', 'rev-parse', 'HEAD'],
    cwd: hostCwd,
    env: env,
    stage: 'sha',
  )).stdout.toString().trim();

  await _git(
    [
      '--git-dir=${tempGitDir.path}',
      'bundle',
      'create',
      bundlePath.path,
      '--all',
    ],
    cwd: hostCwd,
    env: env,
    stage: 'bundle',
  );

  // Submodule warning — Phase 4 W7. The bundle includes the
  // gitlink (commit SHA pointer) but not the submodule's own
  // content. The sandbox would need to recursively fetch each
  // submodule's remote, which brings back the auth problem the
  // bundle path is supposed to bypass. Warn so the user knows
  // submodules will be empty inside the sandbox.
  if (File('$hostCwd/.gitmodules').existsSync()) {
    stderr.writeln(
      '[glue bootstrap] WARN: host has .gitmodules; submodule contents '
      'are NOT included in the bundle. The agent will see empty '
      'submodule directories inside the sandbox.',
    );
  }

  return HostBundle(
    path: bundlePath,
    bundleSha: sha,
    sizeBytes: bundlePath.lengthSync(),
    tempGitDir: tempGitDir,
    originRemoteUrl: await _readHostRemoteUrl(hostCwd),
  );
}

Future<ProcessResult> _git(
  List<String> args, {
  required String cwd,
  required Map<String, String> env,
  required String stage,
}) async {
  final ProcessResult result;
  try {
    result = await Process.run(
      'git',
      args,
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: true,
    );
  } on ProcessException catch (e) {
    throw HostBundleException(
      stage: stage,
      message: '`git ${args.first}` not available on host: ${e.message}',
    );
  }
  if (result.exitCode != 0) {
    throw HostBundleException(
      stage: stage,
      message: 'git ${args.join(' ')} failed',
      exitCode: result.exitCode,
      stderr: result.stderr.toString(),
    );
  }
  return result;
}

Future<bool> _isBareRepo(String hostCwd) async {
  try {
    final r = await Process.run('git', [
      'rev-parse',
      '--is-bare-repository',
    ], workingDirectory: hostCwd);
    if (r.exitCode != 0) return false;
    return (r.stdout as String).trim().toLowerCase() == 'true';
  } catch (_) {
    return false;
  }
}

Future<String?> _readHostRemoteUrl(String hostCwd) async {
  try {
    final r = await Process.run('git', [
      'config',
      '--get',
      'remote.origin.url',
    ], workingDirectory: hostCwd);
    if (r.exitCode != 0) return null;
    final url = (r.stdout as String).trim();
    return url.isEmpty ? null : url;
  } catch (_) {
    return null;
  }
}

Future<String> _defaultSessionDir(String sessionId) async {
  final home =
      Platform.environment['GLUE_HOME'] ??
      p.join(Platform.environment['HOME'] ?? '.', '.glue');
  return p.join(home, 'sessions', sessionId);
}

/// Generates a short opaque session id used to namespace the bundle
/// file and synthetic commit message. Cloud runtimes that don't yet
/// thread a real session id from the harness use this — Phase 3 will
/// wire the actual session id through.
String generateSessionId() =>
    'bootstrap-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
