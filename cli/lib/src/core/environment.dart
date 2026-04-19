import 'dart:io';

import 'package:path/path.dart' as p;

/// Runtime environment abstraction for paths and environment variables.
class Environment {
  final String cwd;
  final String home;
  final Map<String, String> vars;
  final bool isWindows;

  /// Explicit override for the Glue home directory. When set (via the
  /// `GLUE_HOME` environment variable), `glueDir` returns this path
  /// directly instead of `$HOME/.glue`. `null` when not overridden.
  final String? glueHomeOverride;

  const Environment._({
    required this.cwd,
    required this.home,
    required this.vars,
    required this.isWindows,
    required this.glueHomeOverride,
  });

  factory Environment.detect({
    String? cwd,
    Map<String, String>? vars,
    bool? isWindows,
  }) {
    final env = vars ?? Platform.environment;
    final detectedHome = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final override = env['GLUE_HOME'];
    return Environment._(
      cwd: cwd ?? Directory.current.path,
      home: detectedHome,
      vars: Map<String, String>.unmodifiable(Map<String, String>.from(env)),
      isWindows: isWindows ?? Platform.isWindows,
      glueHomeOverride:
          (override != null && override.isNotEmpty) ? override : null,
    );
  }

  factory Environment.test({
    required String home,
    String? cwd,
    Map<String, String> vars = const {},
    bool isWindows = false,
  }) {
    final env = <String, String>{...vars, 'HOME': home};
    return Environment._(
      cwd: cwd ?? '.',
      home: home,
      vars: Map<String, String>.unmodifiable(env),
      isWindows: isWindows,
      glueHomeOverride:
          (env['GLUE_HOME'] != null && env['GLUE_HOME']!.isNotEmpty)
              ? env['GLUE_HOME']
              : null,
    );
  }

  String get glueDir => glueHomeOverride ?? p.join(home, '.glue');
  String get configPath => p.join(glueDir, 'preferences.json');
  String get configYamlPath => p.join(glueDir, 'config.yaml');
  String get credentialsPath => p.join(glueDir, 'credentials.json');
  String get modelsYamlPath => p.join(glueDir, 'models.yaml');
  String get sessionsDir => p.join(glueDir, 'sessions');
  String get logsDir => p.join(glueDir, 'logs');
  String get plansDir => p.join(glueDir, 'plans');
  String get skillsDir => p.join(glueDir, 'skills');
  String get cacheDir => p.join(glueDir, 'cache');

  String sessionDir(String sessionId) => p.join(sessionsDir, sessionId);

  void ensureDirectories() {
    Directory(sessionsDir).createSync(recursive: true);
    Directory(logsDir).createSync(recursive: true);
    Directory(cacheDir).createSync(recursive: true);
  }
}
