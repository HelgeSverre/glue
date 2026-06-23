import 'dart:io';

/// Expands a leading `~`, `~/`, or `~\` (Windows) in [path] to the user's home
/// directory.
///
/// `dart:io`, `Process.start`, and `docker -v` do **not** perform shell-style
/// tilde expansion — only a real shell does. Any path that originates from a
/// user or agent and is then handed to one of those APIs (rather than to a
/// shell command string) must be expanded first, or `~/foo` is treated as a
/// literal path segment relative to the current directory and silently fails.
///
/// Only a leading tilde-prefix is expanded (`~` or `~/...`/`~\...`); a mid-path
/// `~`, a `~user` form, and `$VAR` references are left untouched. When no home
/// can be resolved the path is returned unchanged.
///
/// Callers that already hold an environment map should pass [home] explicitly
/// (e.g. `home: env['HOME'] ?? env['USERPROFILE']`) so the result is
/// deterministic; otherwise the process environment is consulted.
String expandUserPath(String path, {String? home}) {
  if (path != '~' && !path.startsWith('~/') && !path.startsWith('~\\')) {
    return path;
  }
  final resolved =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (resolved == null || resolved.isEmpty) return path;
  return path == '~' ? resolved : '$resolved${path.substring(1)}';
}
