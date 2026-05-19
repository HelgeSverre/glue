import 'dart:convert';
import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;

/// `glue session …` — list, inspect, apply, and export the
/// `runtime.mbox` patches produced by cloud sessions.
///
/// Phase 3 of `docs/plans/2026-05-19-cloud-runtimes-correctness-plan.md`.
/// The mbox itself is captured at session shutdown (see
/// `cli/lib/src/app.dart` `_captureRuntimePatch`); these are the
/// host-side commands that turn it into something useful.

/// Sessions whose runtime started a cloud sandbox but whose
/// `runtimeClosedAt` is null and start time is older than [maxAge]
/// are likely leaks — glue closed/crashed before stopping the
/// sandbox, and the user is still being billed (or has a sandbox
/// counting toward an account quota).
List<SessionSummary> findOrphanedRuntimeSessions(
  Environment env, {
  Duration maxAge = const Duration(hours: 24),
}) {
  final now = DateTime.now().toUtc();
  return listSessions(env).where((s) {
    final m = s.meta;
    if (m.runtimeId == null || m.sandboxId == null) return false;
    if (m.runtimeId == 'host' || m.runtimeId == 'docker') return false;
    if (m.runtimeClosedAt != null) return false;
    return now.difference(m.startTime.toUtc()) > maxAge;
  }).toList();
}

/// Loads all sessions from the on-disk store sorted by start time
/// descending. Sessions without a runtime patch on disk are still
/// listed — call sites distinguish via [SessionSummary.patchPath].
List<SessionSummary> listSessions(Environment env) {
  final dir = Directory(env.sessionsDir);
  if (!dir.existsSync()) return const [];
  final metas = <SessionMeta>[];
  for (final entry in dir.listSync().whereType<Directory>()) {
    final metaFile = File(p.join(entry.path, 'meta.json'));
    if (!metaFile.existsSync()) continue;
    try {
      metas.add(SessionMeta.fromJson(
        jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>,
      ));
    } catch (_) {/* skip corrupt meta */}
  }
  metas.sort((a, b) => b.startTime.compareTo(a.startTime));
  return metas.map((m) => SessionSummary.from(m, env)).toList();
}

class SessionSummary {
  final SessionMeta meta;
  final String sessionDir;
  final String? patchPath;
  final int? patchSizeBytes;

  const SessionSummary({
    required this.meta,
    required this.sessionDir,
    required this.patchPath,
    required this.patchSizeBytes,
  });

  factory SessionSummary.from(SessionMeta meta, Environment env) {
    final dir = env.sessionDir(meta.id);
    String? patch = meta.runtimePatchPath;
    int? size;
    if (patch == null) {
      // Best-effort scan for the patch file if meta didn't record it
      // (older sessions, pre-Phase-3).
      for (final name in [
        'runtime.mbox',
        'runtime.mbox.truncated',
        'runtime.patch',
        'runtime.patch.truncated',
      ]) {
        final candidate = File(p.join(dir, name));
        if (candidate.existsSync()) {
          patch = candidate.path;
          size = candidate.lengthSync();
          break;
        }
      }
    } else if (File(patch).existsSync()) {
      size = File(patch).lengthSync();
    }
    return SessionSummary(
      meta: meta,
      sessionDir: dir,
      patchPath: patch,
      patchSizeBytes: size,
    );
  }
}

class SessionApplyResult {
  final bool ok;
  final String message;
  final String? branch;
  final List<String> rejectedFiles;

  const SessionApplyResult({
    required this.ok,
    required this.message,
    this.branch,
    this.rejectedFiles = const [],
  });
}

/// Applies a session's `runtime.mbox` to [targetDir] using `git am
/// --3way`. When [branch] is provided (Q6 default behavior — `glue
/// session apply` always creates a branch unless `--in-place`), a
/// fresh branch is created from the current HEAD and switched to
/// before applying.
Future<SessionApplyResult> applySessionPatch({
  required SessionSummary session,
  required String targetDir,
  String? branch,
  bool inPlace = false,
}) async {
  final patchPath = session.patchPath;
  if (patchPath == null) {
    return const SessionApplyResult(
      ok: false,
      message: 'no runtime.mbox found for this session',
    );
  }
  if (patchPath.endsWith('.truncated')) {
    return SessionApplyResult(
      ok: false,
      message: 'patch is truncated (exceeded size cap during capture); '
          'cannot be applied — inspect $patchPath manually',
    );
  }

  // Confirm target is a git repo.
  final inRepo = await Process.run(
    'git',
    ['rev-parse', '--is-inside-work-tree'],
    workingDirectory: targetDir,
  );
  if (inRepo.exitCode != 0) {
    return SessionApplyResult(
      ok: false,
      message: '$targetDir is not inside a git working tree',
    );
  }

  // Q6 default: create a branch unless caller passes inPlace.
  if (!inPlace) {
    final branchName = branch ??
        'glue/${session.meta.id.value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '-')}';
    final co = await Process.run(
      'git',
      ['checkout', '-b', branchName],
      workingDirectory: targetDir,
    );
    if (co.exitCode != 0) {
      return SessionApplyResult(
        ok: false,
        message: 'failed to create branch $branchName: ${co.stderr}',
      );
    }
    branch = branchName;
  }

  // Try `git am --3way` first (proper apply for format-patch mbox).
  final am = await Process.run(
    'git',
    ['am', '--3way', patchPath],
    workingDirectory: targetDir,
  );
  if (am.exitCode == 0) {
    return SessionApplyResult(
      ok: true,
      message: 'applied via git am --3way',
      branch: branch,
    );
  }
  // Abort the half-applied `git am` state before falling back.
  await Process.run(
    'git',
    ['am', '--abort'],
    workingDirectory: targetDir,
  );

  // Fall back to `git apply --3way` for patches without an mbox
  // header (working-tree-only diffs).
  final apply = await Process.run(
    'git',
    ['apply', '--3way', patchPath],
    workingDirectory: targetDir,
  );
  if (apply.exitCode == 0) {
    return SessionApplyResult(
      ok: true,
      message: 'applied via git apply --3way (no commit history)',
      branch: branch,
    );
  }

  // Scan for `.rej` files to help the user resolve conflicts.
  final rejected = <String>[];
  try {
    final find = await Process.run(
      'find',
      [targetDir, '-name', '*.rej'],
      workingDirectory: targetDir,
    );
    if (find.exitCode == 0) {
      rejected.addAll(
        (find.stdout as String)
            .trim()
            .split('\n')
            .where((s) => s.isNotEmpty),
      );
    }
  } catch (_) {/* find isn't critical */}

  return SessionApplyResult(
    ok: false,
    message:
        'git am and git apply both failed. Inspect rejections or apply '
        'manually:\n  ${apply.stderr.toString().trim().split('\n').join('\n  ')}',
    branch: branch,
    rejectedFiles: rejected,
  );
}
