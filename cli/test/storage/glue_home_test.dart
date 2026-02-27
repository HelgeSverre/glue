import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/src/storage/glue_home.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('glue_home_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ensureDirectories creates sessions and logs dirs', () {
    final home = GlueHome(basePath: tempDir.path);
    home.ensureDirectories();

    expect(Directory(home.sessionsDir).existsSync(), isTrue);
    expect(Directory(home.logsDir).existsSync(), isTrue);
  });

  test('configPath points to config.json', () {
    final home = GlueHome(basePath: tempDir.path);
    expect(home.configPath, endsWith('config.json'));
  });

  test('sessionDir returns path under sessions', () {
    final home = GlueHome(basePath: tempDir.path);
    final dir = home.sessionDir('abc123');
    expect(dir, contains('sessions'));
    expect(dir, endsWith('abc123'));
  });
}
