import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:glue_runtimes/src/common/host_bundle.dart';

/// Result of a successful workspace bootstrap.
class BootstrapResult {
  /// Commit SHA the sandbox was bootstrapped from (when the host cwd
  /// was a git repo). `null` when the sandbox was resumed and
  /// already had `/workspace/.git` populated.
  final String? bootstrapSha;

  /// Whether [WorkspaceBootstrap.bootstrap] resumed an existing
  /// sandbox/sprite (i.e. `/workspace/.git` already existed).
  final bool resumed;

  const BootstrapResult({required this.resumed, this.bootstrapSha});
}

/// Narrow contract over a runtime's exec channel that the bootstrap
/// flow needs. Each adapter wraps its client/cli/sidecar in an impl
/// of this interface so the bootstrap logic stays transport-agnostic.
abstract class BootstrapExec {
  /// Runs [shellCommand] inside the runtime via `sh -c`-equivalent
  /// semantics. Returns `exitCode` and the (possibly combined)
  /// `output` for error reporting.
  Future<BootstrapExecResult> run(String shellCommand);
}

/// Extended transport contract for the bundle bootstrap path —
/// adapters that want to support uploading a host-built git bundle
/// implement this. Adapters that only implement [BootstrapExec] fall
/// back to the clone-from-remote strategy.
abstract class BootstrapBundleTransport implements BootstrapExec {
  /// Uploads [bytes] to [runtimePath] inside the sandbox. Caller
  /// guarantees the parent directory will be created (via [run] or
  /// the adapter's own semantics). Errors are wrapped in
  /// [BootstrapException(stage: 'upload')].
  Future<void> uploadBytes(String runtimePath, List<int> bytes);

  /// Per-runtime cap on what [uploadBytes] can practically handle in
  /// a single call. Used by [WorkspaceBootstrap] to decide whether to
  /// take the bundle path or fall back to clone-from-remote.
  ///
  /// Verified caps (see cloud-runtimes-correctness-plan §Phase 2):
  /// - Daytona multipart upload: ~200 MB
  /// - Modal sidecar base64-in-JSON: ~30 MB
  /// - Sprites base64-over-shell: ~3 MB
  int get bundleSizeCapBytes;
}

class BootstrapExecResult {
  final int exitCode;
  final String output;
  const BootstrapExecResult({required this.exitCode, required this.output});
}

/// Raised when a bootstrap step fails. Adapters typically catch this
/// and re-throw their own `*ApiException` so the failure surfaces in
/// a runtime-consistent shape.
class BootstrapException implements Exception {
  final String stage;
  final String message;
  final int? exitCode;
  final String? output;
  const BootstrapException({
    required this.stage,
    required this.message,
    this.exitCode,
    this.output,
  });
  @override
  String toString() =>
      'BootstrapException($stage${exitCode == null ? '' : ', exit=$exitCode'}): '
      '$message${output == null ? '' : '\n$output'}';
}

/// Seeds a freshly-created or resumed runtime sandbox with the
/// user's working tree at `runtimeCwd`.
///
/// Strategy:
///   1. Resume — if `<runtimeCwd>/.git` already exists, treat the
///      sandbox as previously bootstrapped and skip the clone. This
///      is the auto-sleep / wake path used by persistent providers
///      (sprites, daytona snapshots).
///   2. Clone — if [hostCwd] is a git repo with a reachable remote,
///      `git clone <remote> <runtimeCwd>` and `git checkout <sha>`.
///      SSH-form remotes are rewritten to HTTPS so fresh sandboxes
///      without SSH keys can still clone public repos.
///   3. Otherwise — throw [UnimplementedError]; tarball fallback is
///      not implemented yet.
///
/// [prepCommand] runs once before the clone (e.g. Daytona's
/// `sudo mkdir -p $runtimeCwd && sudo chown ...` to fix ownership
/// on snapshots that mount `/` as root). `null` skips it.
class WorkspaceBootstrap {
  final BootstrapExec exec;
  final String? prepCommand;

  /// Session identifier, used to namespace the host-built bundle
  /// under `~/.glue/sessions/<id>/bootstrap.bundle` and as the
  /// synthetic commit message inside it.
  final String sessionId;

  WorkspaceBootstrap({
    required this.exec,
    required this.sessionId,
    this.prepCommand,
  });

  /// Strategy preference (Phase 2 of cloud-runtimes-correctness-plan):
  ///
  /// 1. **resume** — `<runtimeCwd>/.git` already exists; skip clone.
  /// 2. **bundle** — host has git; build a single-commit bundle of
  ///    the working tree (respects .gitignore, captures uncommitted,
  ///    works on non-git workspaces, works with no remote, bypasses
  ///    sandbox-side auth). Requires [exec] to implement
  ///    [BootstrapBundleTransport] AND bundle size ≤ runtime cap.
  /// 3. **clone-from-remote** — fall back when bundle isn't an option
  ///    (no upload transport, or bundle exceeds cap). Requires
  ///    remote.origin.url + committed HEAD reachable on the remote.
  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final probe = await exec.run('test -d $runtimeCwd/.git');
    if (probe.exitCode == 0) {
      return const BootstrapResult(resumed: true);
    }

    if (prepCommand != null) {
      final prep = await exec.run(prepCommand!);
      if (prep.exitCode != 0) {
        throw BootstrapException(
          stage: 'prep',
          message: 'pre-clone prep failed',
          exitCode: prep.exitCode,
          output: prep.output,
        );
      }
    }

    // Strategy: prefer bundle if transport supports it AND bundle
    // fits in the runtime's upload cap. Falls back to clone-from-
    // remote otherwise — and falls back further to a clear error
    // explaining what to set up.
    final transport = exec;
    if (transport is BootstrapBundleTransport) {
      try {
        return await _bootstrapViaBundle(
          transport: transport,
          hostCwd: hostCwd,
          runtimeCwd: runtimeCwd,
        );
      } on _BundleSkipped catch (skip) {
        // Bundle exceeds runtime cap or host has no git — try
        // clone-from-remote next.
        stderr.writeln('[glue bootstrap] bundle path unavailable '
            '(${skip.reason}); falling back to clone-from-remote');
      }
    }

    return _bootstrapViaClone(hostCwd: hostCwd, runtimeCwd: runtimeCwd);
  }

  Future<BootstrapResult> _bootstrapViaBundle({
    required BootstrapBundleTransport transport,
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final HostBundle bundle;
    try {
      bundle = await buildHostBundle(
        hostCwd: hostCwd,
        sessionId: sessionId,
      );
    } on HostBundleException catch (e) {
      throw _BundleSkipped('host git unavailable (${e.stage}: ${e.message})');
    }

    if (bundle.sizeBytes > transport.bundleSizeCapBytes) {
      throw _BundleSkipped(
        'bundle is ${bundle.sizeBytes} bytes, exceeds runtime cap of '
        '${transport.bundleSizeCapBytes}',
      );
    }

    final runtimeBundlePath = p.posix.join('/tmp', 'glue-bootstrap.bundle');
    try {
      await transport.uploadBytes(
        runtimeBundlePath,
        await bundle.path.readAsBytes(),
      );
    } catch (e) {
      throw BootstrapException(
        stage: 'upload',
        message: 'bundle upload to $runtimeBundlePath failed',
        output: e.toString(),
      );
    }

    final clone = await exec.run(
      'git clone $runtimeBundlePath $runtimeCwd '
      '&& cd $runtimeCwd && git remote remove origin 2>/dev/null || true',
    );
    if (clone.exitCode != 0) {
      throw BootstrapException(
        stage: 'clone-bundle',
        message: 'sandbox failed to clone uploaded bundle at $runtimeBundlePath',
        exitCode: clone.exitCode,
        output: clone.output,
      );
    }

    // Bundle has been consumed; remove it to free sandbox disk.
    await exec.run('rm -f $runtimeBundlePath');

    // Best-effort: delete the host-side bundle (keep the tempGitDir
    // for diagnostics). Failures are non-fatal.
    try {
      await bundle.path.delete();
    } catch (_) {}

    return BootstrapResult(resumed: false, bootstrapSha: bundle.bundleSha);
  }

  Future<BootstrapResult> _bootstrapViaClone({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final remoteUrl = await _gitRemoteUrl(hostCwd);
    final sha = await _gitHeadSha(hostCwd);
    if (remoteUrl == null || sha == null) {
      throw const BootstrapException(
        stage: 'clone',
        message: 'no bundle transport AND host is not a git repo with '
            'a reachable remote. Either: (a) use a runtime adapter that '
            'supports bundle bootstrap, or (b) push your changes to a '
            'reachable remote first.',
      );
    }

    final cloneUrl = _toHttpsCloneUrl(remoteUrl);
    final clone = await exec.run('git clone $cloneUrl $runtimeCwd');
    if (clone.exitCode != 0) {
      throw BootstrapException(
        stage: 'clone',
        message: 'git clone failed inside the sandbox',
        exitCode: clone.exitCode,
        output: clone.output,
      );
    }

    final checkout = await exec.run('cd $runtimeCwd && git checkout $sha');
    if (checkout.exitCode != 0) {
      throw BootstrapException(
        stage: 'checkout',
        message: 'git checkout $sha failed inside the sandbox',
        exitCode: checkout.exitCode,
        output: checkout.output,
      );
    }

    return BootstrapResult(resumed: false, bootstrapSha: sha);
  }

  /// Rewrites `git@host:owner/repo.git` to
  /// `https://host/owner/repo.git`. Fresh sandboxes have no SSH key
  /// to authenticate with, so SSH clones fail on host-key
  /// verification. Public repos work fine over HTTPS; private repos
  /// would need credentials configured in the sandbox first.
  static String _toHttpsCloneUrl(String remote) {
    final match = RegExp(r'^git@([^:]+):(.+)$').firstMatch(remote);
    if (match == null) return remote;
    return 'https://${match.group(1)}/${match.group(2)}';
  }

  static Future<String?> _gitRemoteUrl(String cwd) async {
    final result = await Process.run(
      'git',
      ['config', '--get', 'remote.origin.url'],
      workingDirectory: cwd,
    );
    if (result.exitCode != 0) return null;
    final url = (result.stdout as String).trim();
    return url.isEmpty ? null : url;
  }

  static Future<String?> _gitHeadSha(String cwd) async {
    final result = await Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: cwd,
    );
    if (result.exitCode != 0) return null;
    final sha = (result.stdout as String).trim();
    return sha.isEmpty ? null : sha;
  }
}

/// Internal signal from `_bootstrapViaBundle` to its caller that the
/// bundle path isn't viable (host has no git, bundle exceeds runtime
/// cap, etc.) — caller falls back to clone-from-remote.
class _BundleSkipped implements Exception {
  final String reason;
  _BundleSkipped(this.reason);
}
