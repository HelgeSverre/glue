/// Opens URLs in the user's default browser.
///
/// Platform-agnostic wrapper over the usual open-a-URL commands:
///   - macOS:   `open <url>`
///   - Windows: `cmd /c start "" <url>` (empty title avoids window-title parsing)
///   - other:   `xdg-open <url>` (Linux, BSD, Unix-likes)
///
/// The runner is injectable so tests don't spawn real processes.
library;

import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Open [url] in the default browser. Returns true on success (exit 0).
/// Never throws — failures fall through as `false` so the caller can decide
/// whether to surface them (e.g. "couldn't open browser; copy the URL").
Future<bool> openInBrowser(
  String url, {
  ProcessRunner? runner,
}) async {
  final run = runner ?? Process.run;
  final (exe, args) = _commandFor(url);
  try {
    final result = await run(exe, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

(String, List<String>) _commandFor(String url) {
  if (Platform.isMacOS) return ('open', [url]);
  if (Platform.isWindows) return ('cmd', ['/c', 'start', '', url]);
  return ('xdg-open', [url]);
}
