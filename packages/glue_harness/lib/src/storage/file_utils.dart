import 'dart:io';

/// Atomically replaces [file]'s contents: writes a sibling `.tmp` (flushed to
/// disk so a crash can't leave a torn file), then renames it over [file].
///
/// On non-Windows the temp file is restricted to owner (0600) *before* the
/// rename, so the final file is never briefly world-readable (mirrors the
/// atomic-write-then-chmod pattern in `credential_store`). L3 / M12.
void atomicWrite(File file, String content) {
  file.parent.createSync(recursive: true);
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(content, flush: true);
  if (!Platform.isWindows) {
    try {
      Process.runSync('chmod', ['600', tmp.path]);
    } catch (_) {}
  }
  if (Platform.isWindows && file.existsSync()) {
    file.deleteSync();
  }
  tmp.renameSync(file.path);
}
