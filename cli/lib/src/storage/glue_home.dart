import 'dart:io';
import 'package:path/path.dart' as p;

class GlueHome {
  final String basePath;

  GlueHome({String? basePath})
      : basePath =
            basePath ?? p.join(Platform.environment['HOME'] ?? '.', '.glue');

  String get configPath => p.join(basePath, 'config.json');
  String get sessionsDir => p.join(basePath, 'sessions');
  String get logsDir => p.join(basePath, 'logs');
  String get skillsDir => p.join(basePath, 'skills');
  String get cacheDir => p.join(basePath, 'cache');

  void ensureDirectories() {
    Directory(sessionsDir).createSync(recursive: true);
    Directory(logsDir).createSync(recursive: true);
    Directory(cacheDir).createSync(recursive: true);
  }

  String sessionDir(String sessionId) => p.join(sessionsDir, sessionId);
}
