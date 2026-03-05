import 'dart:io';

import 'package:path/path.dart' as p;

/// Runtime environment abstraction for paths and environment variables.
class Environment {
  final String cwd;
  final String home;
  final Map<String, String> vars;
  final bool isWindows;

  const Environment._({
    required this.cwd,
    required this.home,
    required this.vars,
    required this.isWindows,
  });

  factory Environment.detect({
    String? cwd,
    Map<String, String>? vars,
    bool? isWindows,
  }) {
    final env = vars ?? Platform.environment;
    final detectedHome = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    return Environment._(
      cwd: cwd ?? Directory.current.path,
      home: detectedHome,
      vars: Map<String, String>.unmodifiable(Map<String, String>.from(env)),
      isWindows: isWindows ?? Platform.isWindows,
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
    );
  }

  String get glueDir => p.join(home, '.glue');
  String get preferencesPath => p.join(glueDir, 'preferences.json');
  String get legacyConfigPath => p.join(glueDir, 'config.json');
  String get configPath => preferencesPath;
  String get configYamlPath => p.join(glueDir, 'config.yaml');
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
