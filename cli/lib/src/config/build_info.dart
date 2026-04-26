/// Build metadata injected via `dart compile --define` flags.
///
/// Populated by `just build` / `just release` with the build timestamp and
/// git commit information. When absent (e.g. `dart run`), values are empty
/// and the formatted output falls back to `(dev)`.
class BuildInfo {
  /// ISO-8601 UTC timestamp of when the binary was compiled.
  static const String buildTime = String.fromEnvironment(
    'GLUE_BUILD_TIME',
    defaultValue: '',
  );

  /// Short git SHA (e.g. `a1b2c3d`) at compile time.
  static const String gitSha = String.fromEnvironment(
    'GLUE_GIT_SHA',
    defaultValue: '',
  );

  /// Non-empty marker (e.g. `+dirty`) when the working tree had uncommitted
  /// changes at compile time.
  static const String gitDirty = String.fromEnvironment(
    'GLUE_GIT_DIRTY',
    defaultValue: '',
  );

  /// Host that produced the build — typically `$USER@$HOSTNAME` or `ci`.
  static const String builtBy = String.fromEnvironment(
    'GLUE_BUILT_BY',
    defaultValue: '',
  );

  /// True when any build metadata was injected at compile time.
  static bool get isReleaseBuild => buildTime.isNotEmpty || gitSha.isNotEmpty;

  /// Compact single-line summary, e.g. `a1b2c3d+dirty, 2026-04-20T14:23:11Z`
  /// or `dev` when no metadata is present.
  static String get summary {
    if (!isReleaseBuild) return 'dev';
    final parts = <String>[
      if (gitSha.isNotEmpty) '$gitSha$gitDirty',
      if (buildTime.isNotEmpty) buildTime,
    ];
    return parts.join(', ');
  }

  /// Multi-line detailed report for `--version` / debug banners.
  static String details({String? appVersion}) {
    final buffer = StringBuffer();
    if (appVersion != null) {
      buffer.writeln('glue v$appVersion');
    }
    if (!isReleaseBuild) {
      buffer.writeln('build: dev (no metadata injected)');
      return buffer.toString().trimRight();
    }

    if (gitSha.isNotEmpty) {
      buffer.writeln('commit: $gitSha$gitDirty');
    }

    if (buildTime.isNotEmpty) {
      buffer.writeln('built:  $buildTime');
    }

    if (builtBy.isNotEmpty) {
      buffer.writeln('by:     $builtBy');
    }
    return buffer.toString().trimRight();
  }

  BuildInfo._();
}
