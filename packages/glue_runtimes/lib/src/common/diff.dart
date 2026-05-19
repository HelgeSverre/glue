import 'package:glue_strategies/glue_strategies.dart';

/// Bridges this package's [DiffOutcome] vocabulary back into the
/// surface-facing [RuntimeDiffOutcome] in `glue_strategies`. Each
/// cloud `RuntimeSession.diffSinceBootstrap` calls into the helpers
/// in this file and returns the result of [toSurfaceOutcome] so
/// surfaces don't have to import `glue_runtimes`.
extension RuntimeDiffOutcomeAdapter on DiffOutcome {
  RuntimeDiffOutcome toSurfaceOutcome() {
    final self = this;
    return switch (self) {
      DiffSuccess() => RuntimeDiffOutcomeSuccess(
          patch: self.patch,
          meta: _toSurfaceMeta(self.meta),
        ),
      DiffEmpty() => RuntimeDiffOutcomeEmpty(meta: _toSurfaceMeta(self.meta)),
      DiffUnavailable() => RuntimeDiffOutcomeUnavailable(
          reason: switch (self.reason) {
            DiffUnavailableReason.noBootstrapSha =>
              RuntimeDiffUnavailableReason.noBootstrapSha,
            DiffUnavailableReason.gitFailed =>
              RuntimeDiffUnavailableReason.gitFailed,
            DiffUnavailableReason.executorDead =>
              RuntimeDiffUnavailableReason.executorDead,
            DiffUnavailableReason.runtimeNotGit =>
              RuntimeDiffUnavailableReason.runtimeNotGit,
          },
          hint: self.hint,
        ),
    };
  }
}

RuntimeDiffMeta _toSurfaceMeta(DiffMeta m) {
  return RuntimeDiffMeta(
    runtimeId: m.runtimeId,
    sandboxId: m.sandboxId,
    bootstrapSha: m.bootstrapSha,
    remoteUrl: m.remoteUrl,
    runtimeCwd: m.runtimeCwd,
    format: m.format,
    capturedAt: m.capturedAt,
    sizeBytes: m.sizeBytes,
  );
}

/// Outcome of attempting to capture a workspace diff at session end.
///
/// Replaces the previous `Future<String?>` shape so callers can
/// distinguish "no changes" from "we couldn't even try" — silent
/// nulls were eating Sprites-resume data loss and Modal sandbox
/// auto-termination, per
/// `docs/plans/2026-05-19-cloud-runtimes-correctness-plan.md` §S1/S4.
sealed class DiffOutcome {
  const DiffOutcome();
}

/// The runtime captured a non-empty diff successfully.
class DiffSuccess extends DiffOutcome {
  final String patch;
  final DiffMeta meta;
  const DiffSuccess({required this.patch, required this.meta});
}

/// The runtime ran the diff and found nothing changed since bootstrap.
class DiffEmpty extends DiffOutcome {
  final DiffMeta meta;
  const DiffEmpty({required this.meta});
}

/// The runtime couldn't produce a diff. [reason] tells the caller why;
/// surfaces should turn this into a visible warning so the user knows
/// the session didn't silently lose their work.
class DiffUnavailable extends DiffOutcome {
  final DiffUnavailableReason reason;

  /// Human-readable hint for the warning surface. May embed an
  /// adapter-specific remediation (e.g. "commit changes inside the
  /// sandbox before resuming").
  final String? hint;

  const DiffUnavailable({required this.reason, this.hint});
}

enum DiffUnavailableReason {
  /// Runtime never recorded a bootstrap SHA — typically a Sprites
  /// resume that found `/workspace/.git` and skipped cloning.
  noBootstrapSha,

  /// `git` exited non-zero inside the runtime (binary missing, SHA
  /// not reachable, etc.).
  gitFailed,

  /// The executor itself failed — sandbox is gone, transport died.
  executorDead,

  /// The runtime's workspace isn't a git repo (no `/workspace/.git`).
  runtimeNotGit,
}

/// Metadata captured alongside a diff for the host-side surfaces.
/// Persisted next to the patch file as `runtime.<ext>.meta.json`.
class DiffMeta {
  final String runtimeId;
  final String? sandboxId;
  final String? bootstrapSha;
  final String? remoteUrl;
  final String runtimeCwd;
  final String format;
  final DateTime capturedAt;
  final int sizeBytes;

  const DiffMeta({
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

/// Captures the workspace diff a cloud runtime accumulated since its
/// bootstrap commit.
///
/// Runs `git -C <runtimeCwd> diff <bootstrapSha>` via [executor]. The
/// returned [DiffOutcome] distinguishes:
/// - [DiffSuccess] — non-empty patch captured
/// - [DiffEmpty] — git ran cleanly but nothing changed
/// - [DiffUnavailable] with one of [DiffUnavailableReason] — null
///   `bootstrapSha`, git exit code non-zero, etc.
///
/// Caller threads [runtimeId], [sandboxId], [remoteUrl] into the
/// returned [DiffMeta] so the host surface can write a
/// `<patch>.meta.json` sidecar without re-discovering them.
Future<DiffOutcome> captureWorkspaceDiff({
  required CommandExecutor executor,
  required String runtimeCwd,
  required String? bootstrapSha,
  required String runtimeId,
  String? sandboxId,
  String? remoteUrl,
  String format = 'diff',
}) async {
  if (bootstrapSha == null || bootstrapSha.isEmpty) {
    return const DiffUnavailable(
      reason: DiffUnavailableReason.noBootstrapSha,
      hint: 'runtime did not record a bootstrap commit (resumed sandbox?); '
          'commit changes inside the sandbox before exiting to preserve them',
    );
  }
  final CaptureResult r;
  try {
    r = await executor.runCapture(
      'git -C ${_q(runtimeCwd)} diff ${_q(bootstrapSha)}',
    );
  } catch (e) {
    return DiffUnavailable(
      reason: DiffUnavailableReason.executorDead,
      hint: 'runtime executor failed before diff could run: $e',
    );
  }
  if (r.exitCode != 0) {
    return DiffUnavailable(
      reason: DiffUnavailableReason.gitFailed,
      hint: 'git diff exited ${r.exitCode}: '
          '${r.stderr.isEmpty ? r.stdout : r.stderr}'.trim(),
    );
  }
  final patch = r.stdout;
  final meta = DiffMeta(
    runtimeId: runtimeId,
    sandboxId: sandboxId,
    bootstrapSha: bootstrapSha,
    remoteUrl: remoteUrl,
    runtimeCwd: runtimeCwd,
    format: format,
    capturedAt: DateTime.now().toUtc(),
    sizeBytes: patch.length,
  );
  if (patch.isEmpty) return DiffEmpty(meta: meta);
  return DiffSuccess(patch: patch, meta: meta);
}

String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";
