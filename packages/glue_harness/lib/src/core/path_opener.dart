/// Opens local directories in the OS file manager.
///
/// Platform-agnostic wrapper over the usual reveal-a-folder commands:
///   - macOS:   `open <dir>`                         (argv, no shell)
///   - Windows: `explorer <dir>`                     (argv, no shell)
///   - other:   `xdg-open <dir>`                     (Linux, BSD, Unix-likes)
///
/// Paths are validated before launch: control chars and a set of shell
/// metacharacters (`& | ^ < > " \` `` ` `` `$`) are rejected as defence in
/// depth, even though we never pass the path through a shell. Non-ASCII
/// characters are allowed — home directories with accented names are common.
///
/// The runner and existence check are injectable so tests don't spawn real
/// processes or touch the real filesystem.
library;

import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef DirectoryExistsCheck = bool Function(String path);

/// Open [dir] in the OS file manager. Returns `false` (never throws) when:
///   - [dir] is empty, contains shell metacharacters, or control chars
///   - [dir] does not exist as a directory
///   - the launched command exits non-zero
///   - the launcher itself throws (`ProcessException`, etc.)
Future<bool> openInFileManager(
  String dir, {
  ProcessRunner? runner,
  DirectoryExistsCheck? directoryExists,
}) async {
  if (!_isSafePath(dir)) return false;
  final exists = directoryExists ?? (p) => Directory(p).existsSync();
  if (!exists(dir)) return false;
  final run = runner ?? Process.run;
  final (exe, args) = _commandFor(dir);
  try {
    final result = await run(exe, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

bool _isSafePath(String dir) {
  if (dir.isEmpty) return false;
  const blocked = {'&', '|', '^', '<', '>', '"', '`', r'$'};
  for (final codeUnit in dir.codeUnits) {
    if (codeUnit < 0x20) return false;
    if (blocked.contains(String.fromCharCode(codeUnit))) return false;
  }
  return true;
}

(String, List<String>) _commandFor(String dir) {
  if (Platform.isMacOS) return ('open', [dir]);
  if (Platform.isWindows) return ('explorer', [dir]);
  return ('xdg-open', [dir]);
}
