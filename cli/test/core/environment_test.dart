import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('environment_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('test factory builds expected paths', () {
    final environment = Environment.test(home: tempDir.path, cwd: '/work/cwd');

    expect(environment.home, tempDir.path);
    expect(environment.cwd, '/work/cwd');
    expect(environment.configPath, endsWith('.glue/preferences.json'));
    expect(environment.configYamlPath, endsWith('.glue/config.yaml'));
    expect(environment.sessionDir('abc123'), endsWith('.glue/sessions/abc123'));
  });

  test('ensureDirectories creates sessions, logs, and cache dirs', () {
    final environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();

    expect(Directory(environment.sessionsDir).existsSync(), isTrue);
    expect(Directory(environment.logsDir).existsSync(), isTrue);
    expect(Directory(environment.cacheDir).existsSync(), isTrue);
  });
}
