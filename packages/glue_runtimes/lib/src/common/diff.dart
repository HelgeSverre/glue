import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/common/shell_quote.dart';

/// Captures everything the agent did inside the sandbox workspace and
/// returns a surface-facing [RuntimeDiffOutcome] directly, so cloud
/// `RuntimeSession.diffSinceBootstrap` implementations can
/// `return await captureWorkspaceDiff(...)` with no translation.
///
/// Strategy (Phase 1 of cloud-runtimes-correctness-plan):
///
/// 1. `git add -N -- .` — intent-to-add for untracked files so they
///    appear in the working-tree diff. Without this, files the agent
///    *created* (test fixtures, new modules) are silently dropped.
/// 2. `git format-patch --binary -M -C --stdout <sha>..HEAD` — captures
///    every commit the agent made inside the sandbox as an mbox
///    sequence, preserving message + authorship. Skipped when
///    `HEAD == bootstrapSha` (no agent commits).
/// 3. `git diff --binary -M -C <sha>` — working-tree delta on top of
///    HEAD (anything the agent wrote but didn't commit).
///
/// Concatenated output is mbox-compatible: callers should save with a
/// `.mbox` extension and apply with `git am --3way`. `--binary`
/// captures binary blob changes (images, PDFs) so they survive
/// round-trip; `-M -C` enables rename/copy detection so a moved file
/// is one hunk, not delete+add.
///
/// Empty output (no commits and no worktree changes) →
/// [RuntimeDiffOutcomeEmpty]. `git` failure at any step →
/// [RuntimeDiffOutcomeUnavailable] with the stderr included in the hint.
Future<RuntimeDiffOutcome> captureWorkspaceDiff({
  required CommandExecutor executor,
  required String runtimeCwd,
  required String? bootstrapSha,
  required String runtimeId,
  String? sandboxId,
  String? remoteUrl,
  String format = 'format-patch',
}) async {
  if (bootstrapSha == null || bootstrapSha.isEmpty) {
    return const RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.noBootstrapSha,
      hint:
          'runtime did not record a bootstrap commit (resumed sandbox?); '
          'commit changes inside the sandbox before exiting to preserve them',
    );
  }

  final cwd = shQuote(runtimeCwd);
  final sha = shQuote(bootstrapSha);

  // (1) intent-to-add for untracked. Failures here are non-fatal —
  // if the workspace isn't a git repo we'll catch it in step (2).
  try {
    await executor.runCapture('git -C $cwd add -N -- . 2>/dev/null || true');
  } catch (e) {
    return RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.executorDead,
      hint: 'runtime executor failed during diff prep: $e',
    );
  }

  // (2) format-patch for committed history. May produce an empty
  // string when HEAD == bootstrapSha; that's normal.
  final CaptureResult formatPatch;
  try {
    formatPatch = await executor.runCapture(
      'git -C $cwd format-patch --binary -M -C --stdout $sha..HEAD',
    );
  } catch (e) {
    return RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.executorDead,
      hint: 'runtime executor failed during format-patch: $e',
    );
  }
  if (formatPatch.exitCode != 0) {
    return RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.gitFailed,
      hint:
          'git format-patch exited ${formatPatch.exitCode}: '
                  '${formatPatch.stderr.isEmpty ? formatPatch.stdout : formatPatch.stderr}'
              .trim(),
    );
  }

  // (3) working-tree delta on top of HEAD.
  final CaptureResult workTree;
  try {
    workTree = await executor.runCapture(
      'git -C $cwd diff --binary -M -C HEAD',
    );
  } catch (e) {
    return RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.executorDead,
      hint: 'runtime executor failed during working-tree diff: $e',
    );
  }
  if (workTree.exitCode != 0) {
    return RuntimeDiffOutcomeUnavailable(
      reason: RuntimeDiffUnavailableReason.gitFailed,
      hint:
          'git diff exited ${workTree.exitCode}: '
                  '${workTree.stderr.isEmpty ? workTree.stdout : workTree.stderr}'
              .trim(),
    );
  }

  final mbox = [
    formatPatch.stdout,
    workTree.stdout,
  ].where((s) => s.isNotEmpty).join();
  final meta = RuntimeDiffMeta(
    runtimeId: runtimeId,
    sandboxId: sandboxId,
    bootstrapSha: bootstrapSha,
    remoteUrl: remoteUrl,
    runtimeCwd: runtimeCwd,
    format: format,
    capturedAt: DateTime.now().toUtc(),
    sizeBytes: mbox.length,
  );
  if (mbox.isEmpty) return RuntimeDiffOutcomeEmpty(meta: meta);
  return RuntimeDiffOutcomeSuccess(patch: mbox, meta: meta);
}
