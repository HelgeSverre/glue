import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:path/path.dart' as p;

/// Discover bundled skill directories that ship with the Glue CLI checkout.
///
/// Resolution order:
/// 1. `GLUE_BUNDLED_SKILLS_DIR` env var (if present)
/// 2. Paths derived from the running script location
List<String> discoverBundledSkillPaths({
  Map<String, String>? environment,
  String? scriptPath,
}) {
  final env = environment ?? Platform.environment;
  final found = <String>{};

  final home = env['HOME'] ?? env['USERPROFILE'];
  void addIfDir(String? path) {
    if (path == null || path.isEmpty) return;
    final expanded = expandUserPath(path, home: home);
    if (Directory(expanded).existsSync()) {
      found.add(p.normalize(expanded));
    }
  }

  addIfDir(env['GLUE_BUNDLED_SKILLS_DIR']);

  final resolvedScriptPath = scriptPath ?? _defaultScriptPath();
  if (resolvedScriptPath != null && resolvedScriptPath.isNotEmpty) {
    final scriptDir = p.dirname(resolvedScriptPath);
    final packageRoot = p.dirname(scriptDir);
    addIfDir(p.join(packageRoot, 'skills'));
    addIfDir(p.join(packageRoot, 'cli', 'skills'));
  }

  return found.toList(growable: false);
}

String? _defaultScriptPath() {
  try {
    if (!Platform.script.isScheme('file')) return null;
    return Platform.script.toFilePath();
  } catch (_) {
    return null;
  }
}
