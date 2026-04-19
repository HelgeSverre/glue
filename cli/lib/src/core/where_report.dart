import 'dart:io';

import 'package:glue/src/core/environment.dart';

/// Signature for checking whether a filesystem path exists.
typedef PathExistenceCheck = bool Function(String path, {required bool isDir});

/// Renders the paths table for both `glue --where` (CLI flag) and the
/// `/paths` slash command. Keeping it in one place ensures the two surfaces
/// never drift — adding a new row updates both at once.
///
/// Output is ANSI-coloured and ends with a trailing newline so callers can
/// `stdout.write` it directly.
String buildWhereReport(
  Environment env, {
  PathExistenceCheck? existsCheck,
}) {
  final check = existsCheck ?? _defaultExistenceCheck;
  final buf = StringBuffer();
  final overrideNote =
      env.glueHomeOverride != null ? '  (via \$GLUE_HOME)' : '';

  buf.writeln('\x1b[1mGLUE_HOME\x1b[0m  ${env.glueDir}$overrideNote');
  buf.writeln();

  void line(String label, String path, {bool isDir = false}) {
    final mark =
        check(path, isDir: isDir) ? ' \x1b[32m✓\x1b[0m' : ' \x1b[90m-\x1b[0m';
    buf.writeln('  ${label.padRight(18)}$path$mark');
  }

  line('config.yaml', env.configYamlPath);
  line('preferences.json', env.configPath);
  line('credentials.json', env.credentialsPath);
  line('models.yaml', env.modelsYamlPath);
  line('sessions/', env.sessionsDir, isDir: true);
  line('logs/', env.logsDir, isDir: true);
  line('cache/', env.cacheDir, isDir: true);
  line('skills/', env.skillsDir, isDir: true);
  line('plans/', env.plansDir, isDir: true);
  buf.writeln();
  buf.writeln('Legend: ✓ exists · - not yet created');

  return buf.toString();
}

bool _defaultExistenceCheck(String path, {required bool isDir}) {
  return isDir ? Directory(path).existsSync() : File(path).existsSync();
}
