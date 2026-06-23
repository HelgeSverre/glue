/// Describes how a host directory maps onto the working tree as seen
/// inside a runtime.
///
/// For the host runtime, [hostCwd] and [runtimeCwd] are identical and
/// no translation is needed. For Docker, [hostCwd] is the user's
/// working directory and [runtimeCwd] is the bind-mount target inside
/// the container (`/workspace`). For cloud runtimes, [hostCwd] is the
/// local source the agent edits and [runtimeCwd] is the path inside
/// the sandbox where the workspace lives.
class WorkspaceMapping {
  /// Absolute path on the host that holds the user's working tree.
  final String hostCwd;

  /// Absolute path inside the runtime where [hostCwd] is exposed.
  ///
  /// Conventionally `'/workspace'` for Docker and cloud runtimes;
  /// equal to [hostCwd] for the host runtime.
  final String runtimeCwd;

  /// Where session artifacts (e.g. transcripts, end-of-session diffs)
  /// are written inside the runtime. Defaults to
  /// `<runtimeCwd>/.glue/artifacts`.
  final String artifactsDir;

  WorkspaceMapping({
    required this.hostCwd,
    required this.runtimeCwd,
    String? artifactsDir,
  }) : artifactsDir = artifactsDir ?? '$runtimeCwd/.glue/artifacts';

  /// Convenience constructor for the no-translation case (host runtime).
  factory WorkspaceMapping.host(String cwd) =>
      WorkspaceMapping(hostCwd: cwd, runtimeCwd: cwd);

  /// True when [hostCwd] equals [runtimeCwd] — i.e. no path translation
  /// is needed because the runtime sees the same paths as the host.
  bool get isIdentity => hostCwd == runtimeCwd;

  /// Translates a host path into the equivalent runtime path.
  ///
  /// Returns `null` when [hostPath] is not under [hostCwd] — callers
  /// can use that to decide whether to reject the path or pass it
  /// through unchanged.
  String? toRuntimePath(String hostPath) {
    if (isIdentity) return hostPath;
    // Host paths captured on Windows (e.g. from `Directory.listSync`) use
    // `\`, while runtime paths are POSIX. Normalize separators for the prefix
    // match and carry the relative remainder over with `/`, so the runtime
    // sees `/workspace/foo` rather than `/workspace\foo`. Backslashes are
    // vanishingly rare in POSIX filenames, so treating them as separators is
    // safe in practice.
    final host = _normalizeSeparators(hostPath);
    final base = _normalizeSeparators(hostCwd);
    if (host == base) return runtimeCwd;
    final basePrefix = _withTrailingSlash(base);
    if (host.startsWith(basePrefix)) {
      final rel = host.substring(basePrefix.length);
      return '${_withTrailingSlash(runtimeCwd)}$rel';
    }
    return null;
  }

  /// Translates a runtime path back to the equivalent host path.
  ///
  /// Paths that already look like host paths (e.g. when the runtime is
  /// the host itself) pass through unchanged. Paths that are not under
  /// [runtimeCwd] are returned as-is so callers can decide whether to
  /// reject or pass them through.
  String toHostPath(String runtimePath) {
    if (isIdentity) return runtimePath;
    final runtimePrefix = _withTrailingSlash(runtimeCwd);
    if (runtimePath == runtimeCwd) return hostCwd;
    if (runtimePath.startsWith(runtimePrefix)) {
      final rel = runtimePath.substring(runtimePrefix.length);
      return '${_withTrailingSlash(hostCwd)}$rel';
    }
    return runtimePath;
  }

  static String _withTrailingSlash(String s) => s.endsWith('/') ? s : '$s/';

  static String _normalizeSeparators(String path) => path.replaceAll(r'\', '/');

  @override
  String toString() =>
      'WorkspaceMapping(hostCwd: $hostCwd, runtimeCwd: $runtimeCwd)';
}
