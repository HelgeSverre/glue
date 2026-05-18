import 'dart:io';

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

  WorkspaceBootstrap({required this.exec, this.prepCommand});

  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final probe = await exec.run('test -d $runtimeCwd/.git');
    if (probe.exitCode == 0) {
      return const BootstrapResult(resumed: true);
    }

    final remoteUrl = await _gitRemoteUrl(hostCwd);
    final sha = await _gitHeadSha(hostCwd);
    if (remoteUrl == null || sha == null) {
      throw UnimplementedError(
        'Tarball bootstrap not yet implemented. The working directory '
        'must be a git repo with a reachable remote and a committed '
        'HEAD. Push your changes (even to a scratch branch) before '
        'running with a cloud runtime.',
      );
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
