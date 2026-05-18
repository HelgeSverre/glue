import 'package:glue_strategies/glue_strategies.dart';

/// Captures the workspace diff a cloud runtime accumulated since its
/// bootstrap commit.
///
/// Runs `git -C <runtimeCwd> diff <bootstrapSha>` via [executor].
/// Returns the patch text on success, or `null` when:
/// - [bootstrapSha] is `null` (no bootstrap recorded — typically a
///   resumed sandbox where there's no obvious baseline);
/// - the git command exits non-zero (`git` not in PATH inside the
///   sandbox, the SHA isn't reachable, etc. — we'd rather return
///   null than block session shutdown on a diff failure).
///
/// Empty diffs (no changes) return an empty string, not null — the
/// caller can distinguish "nothing changed" from "diff unavailable".
Future<String?> captureWorkspaceDiff({
  required CommandExecutor executor,
  required String runtimeCwd,
  required String? bootstrapSha,
}) async {
  if (bootstrapSha == null || bootstrapSha.isEmpty) return null;
  final r = await executor.runCapture(
    'git -C ${_q(runtimeCwd)} diff ${_q(bootstrapSha)}',
  );
  if (r.exitCode != 0) return null;
  return r.stdout;
}

String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";
