/// Surface-facing mirror of `DiffOutcome` from `glue_runtimes/common/diff.dart`.
///
/// Lives here so `glue_strategies` consumers can pattern-match without
/// importing the runtime adapter package.
library;

/// Outcome of attempting to diff the runtime workspace against its
/// bootstrap SHA.
sealed class RuntimeDiffOutcome {
  const RuntimeDiffOutcome();
}

class RuntimeDiffOutcomeSuccess extends RuntimeDiffOutcome {
  final String patch;
  final RuntimeDiffMeta meta;
  const RuntimeDiffOutcomeSuccess({required this.patch, required this.meta});
}

class RuntimeDiffOutcomeEmpty extends RuntimeDiffOutcome {
  final RuntimeDiffMeta meta;
  const RuntimeDiffOutcomeEmpty({required this.meta});
}

class RuntimeDiffOutcomeUnavailable extends RuntimeDiffOutcome {
  final RuntimeDiffUnavailableReason reason;
  final String? hint;
  const RuntimeDiffOutcomeUnavailable({required this.reason, this.hint});
}

enum RuntimeDiffUnavailableReason {
  /// Adapter doesn't implement diff capture (host/docker today).
  notSupported,

  /// Runtime never recorded a bootstrap SHA — typically a resumed
  /// cloud sandbox where there was no clean baseline to diff against.
  noBootstrapSha,

  /// `git` exited non-zero inside the runtime.
  gitFailed,

  /// The executor itself failed (transport died, sandbox terminated).
  executorDead,

  /// The runtime's workspace isn't a git repo.
  runtimeNotGit,
}

class RuntimeDiffMeta {
  final String runtimeId;
  final String? sandboxId;
  final String? bootstrapSha;
  final String? remoteUrl;
  final String runtimeCwd;
  final String format;
  final DateTime capturedAt;
  final int sizeBytes;

  const RuntimeDiffMeta({
    required this.runtimeId,
    required this.sandboxId,
    required this.bootstrapSha,
    required this.remoteUrl,
    required this.runtimeCwd,
    required this.format,
    required this.capturedAt,
    required this.sizeBytes,
  });

  Map<String, Object?> toJson() {
    return {
      'runtime_id': runtimeId,
      'sandbox_id': sandboxId,
      'bootstrap_sha': bootstrapSha,
      'remote_url': remoteUrl,
      'runtime_cwd': runtimeCwd,
      'format': format,
      'captured_at': capturedAt.toIso8601String(),
      'size_bytes': sizeBytes,
    };
  }
}
