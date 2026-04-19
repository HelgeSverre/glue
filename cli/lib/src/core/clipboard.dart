/// Writes text to the system clipboard across platforms.
///
/// Tries a platform-specific list of commands in order (on Linux there are
/// several clipboard tools; try each). Stdin is the only input path — no
/// shell interpretation, so arbitrary binary-safe text works.
///
/// The runner is injectable; tests supply a fake to avoid spawning a real
/// `pbcopy` / `clip` / `wl-copy`.
library;

import 'dart:io';

class ClipboardProcess {
  const ClipboardProcess({required this.stdin, required this.exitCode});
  final IOSink stdin;
  final Future<int> exitCode;
}

typedef ClipboardRunner = Future<ClipboardProcess> Function(
  String executable,
  List<String> arguments,
);

/// Copies [text] to the system clipboard. Returns true if any command in
/// the platform's fallback chain succeeds (exit code 0).
///
/// Never throws — process-launch failures (`ProcessException`) and
/// non-zero exits fall through to the next candidate, and the final return
/// value is false if every candidate failed.
Future<bool> copyToClipboard(
  String text, {
  ClipboardRunner? runner,
}) async {
  final run = runner ?? _defaultRunner;
  for (final (exe, args) in _clipboardCommands()) {
    try {
      final process = await run(exe, args);
      process.stdin.write(text);
      await process.stdin.close();
      final code = await process.exitCode;
      if (code == 0) return true;
    } on ProcessException {
      // Try next command.
    }
  }
  return false;
}

Future<ClipboardProcess> _defaultRunner(
  String executable,
  List<String> arguments,
) async {
  final p = await Process.start(executable, arguments);
  return ClipboardProcess(stdin: p.stdin, exitCode: p.exitCode);
}

List<(String, List<String>)> _clipboardCommands() {
  if (Platform.isMacOS) {
    return [('pbcopy', const [])];
  }
  if (Platform.isWindows) {
    return [('clip', const [])];
  }
  if (Platform.isLinux) {
    return [
      ('wl-copy', const []),
      ('xclip', const ['-selection', 'clipboard']),
      ('xsel', const ['--clipboard', '--input']),
    ];
  }
  return const [];
}
