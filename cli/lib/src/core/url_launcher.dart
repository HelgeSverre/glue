/// Opens URLs in the user's default browser.
///
/// Platform-agnostic wrapper over the usual open-a-URL commands:
///   - macOS:   `open <url>`                         (argv, no shell)
///   - Windows: `rundll32 url.dll,FileProtocolHandler <url>`
///              (argv, no shell — avoids the `cmd /c start` metachar
///              interpretation that would treat `&`, `^`, `|` etc. as
///              shell operators on URLs merged from untrusted catalogs)
///   - other:   `xdg-open <url>`                     (Linux, BSD, Unix-likes)
///
/// URLs are validated before launch: only `http`/`https` schemes are allowed
/// and any character that cmd.exe would special-case (`& | ^ < > " ` `` ` ``
/// plus control chars) is rejected even on non-Windows, as defence in depth.
///
/// The runner is injectable so tests don't spawn real processes.
library;

import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef FileExistsCheck = bool Function(String path);

/// Open [url] in the default browser. Returns false (never throws) when:
///   - [url] isn't http/https or contains shell metacharacters
///   - the launched command exits non-zero
///   - the launcher itself throws (`ProcessException`, etc.)
Future<bool> openInBrowser(
  String url, {
  ProcessRunner? runner,
}) async {
  if (!_isSafeHttpUrl(url)) return false;
  final run = runner ?? Process.run;
  final (exe, args) = _commandFor(url);
  try {
    final result = await run(exe, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Open a local HTML file in the user's default browser.
///
/// Returns false (never throws) when:
///   - [path] is empty, unsafe, missing, or not an .html/.htm file
///   - the launched command exits non-zero
///   - the launcher itself throws (`ProcessException`, etc.)
Future<bool> openLocalFileInBrowser(
  String path, {
  ProcessRunner? runner,
  FileExistsCheck? fileExists,
}) async {
  if (!_isSafeLocalPath(path)) return false;
  final resolvedPath = File(path).absolute.path;
  if (!_isHtmlPath(resolvedPath)) return false;
  final exists = fileExists ?? (p) => File(p).existsSync();
  if (!exists(resolvedPath)) return false;

  final run = runner ?? Process.run;
  final (exe, args) = _commandForLocalFile(resolvedPath);
  try {
    final result = await run(exe, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

bool _isSafeHttpUrl(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  // Reject chars that cmd.exe / PowerShell parse as shell operators, plus
  // control chars and anything outside printable ASCII. Legitimate URLs
  // percent-encode these.
  const blocked = {'&', '|', '^', '<', '>', '"', '`', r'$', '\\'};
  for (final codeUnit in url.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7e) return false;
    if (blocked.contains(String.fromCharCode(codeUnit))) return false;
  }
  return true;
}

bool _isSafeLocalPath(String path) {
  if (path.isEmpty) return false;
  const blocked = {'&', '|', '^', '<', '>', '"', '`', r'$'};
  for (final codeUnit in path.codeUnits) {
    if (codeUnit < 0x20) return false;
    if (blocked.contains(String.fromCharCode(codeUnit))) return false;
  }
  return true;
}

bool _isHtmlPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

(String, List<String>) _commandFor(String url) {
  if (Platform.isMacOS) return ('open', [url]);
  if (Platform.isWindows) {
    return ('rundll32', ['url.dll,FileProtocolHandler', url]);
  }
  return ('xdg-open', [url]);
}

(String, List<String>) _commandForLocalFile(String path) {
  if (Platform.isMacOS) return ('open', [path]);
  if (Platform.isWindows) {
    return (
      'rundll32',
      ['url.dll,FileProtocolHandler', File(path).absolute.uri.toString()]
    );
  }
  return ('xdg-open', [path]);
}
