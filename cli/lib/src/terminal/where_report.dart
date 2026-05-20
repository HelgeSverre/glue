/// Renders the paths table for both `glue --where` (CLI flag) and the
/// `/paths` slash command. Keeping it in one place ensures the two surfaces
/// never drift — adding a new row updates both at once.
///
/// Output uses the shared `brand.dart` glyphs + `.styled` extension so it
/// reads as a sibling surface to `glue catalog path`, `glue mcp …`, and
/// `glue doctor`.
library;

import 'dart:io';

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue_harness/glue_harness.dart';

/// Signature for checking whether a filesystem path exists.
typedef PathExistenceCheck = bool Function(String path, {required bool isDir});

/// Builds the styled paths report. Ends with a trailing newline so callers
/// can `stdout.write` it directly.
String buildWhereReport(
  Environment env, {
  PathExistenceCheck? existsCheck,
}) {
  final check = existsCheck ?? _defaultExistenceCheck;
  final rows = <({String label, String path, bool isDir})>[
    (label: 'config.yaml', path: env.configYamlPath, isDir: false),
    (label: 'preferences.json', path: env.configPath, isDir: false),
    (label: 'credentials.json', path: env.credentialsPath, isDir: false),
    (label: 'models.yaml', path: env.modelsYamlPath, isDir: false),
    (label: 'sessions/', path: env.sessionsDir, isDir: true),
    (label: 'logs/', path: env.logsDir, isDir: true),
    (label: 'cache/', path: env.cacheDir, isDir: true),
    (label: 'skills/', path: env.skillsDir, isDir: true),
  ];

  final labelWidth =
      rows.map((r) => r.label.length).fold<int>(0, (a, b) => a > b ? a : b);
  final pathWidth =
      rows.map((r) => r.path.length).fold<int>(0, (a, b) => a > b ? a : b);

  final buf = StringBuffer();
  buf.writeln('$brandDot ${'Glue paths'.styled.bold}');
  final overrideNote = env.glueHomeOverride != null
      ? '  ${r'(via $GLUE_HOME)'.styled.gray}'
      : '';
  buf.writeln('  ${env.glueDir}$overrideNote');
  buf.writeln();

  for (final row in rows) {
    final present = check(row.path, isDir: row.isDir);
    final status = present
        ? '$markerOk ${'present'.styled.green}'
        : '$markerWarn ${'missing'.styled.yellow}';
    buf.writeln(
      '  ${row.label.padRight(labelWidth).styled.bold} '
      '${row.path.padRight(pathWidth).styled.gray}  $status',
    );
  }

  return buf.toString();
}

bool _defaultExistenceCheck(String path, {required bool isDir}) {
  return isDir ? Directory(path).existsSync() : File(path).existsSync();
}
