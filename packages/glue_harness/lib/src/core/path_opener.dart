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

import 'package:glue_harness/src/core/process_runner.dart';

typedef DirectoryExistsCheck = bool Function(String path);

Future<bool> openInFileManager(
  String dir, {
  ProcessRunner? runner,
  DirectoryExistsCheck? directoryExists,
}) async {
  if (dir.isEmpty ||
      dir.codeUnits.any(
        (c) => c < 0x20 || '&|^<>"`\$'.contains(String.fromCharCode(c)),
      )) {
    return false;
  }
  final exists = directoryExists ?? (p) => Directory(p).existsSync();
  if (!exists(dir)) return false;
  final run = runner ?? Process.run;
  final exe = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'explorer'
      : 'xdg-open';
  try {
    final result = await run(exe, [dir]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
