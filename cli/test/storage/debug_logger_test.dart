import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/src/storage/debug_logger.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('debug_logger_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('writes to log file when enabled', () async {
    final logger = DebugLogger(logsDir: tempDir.path, enabled: true);
    logger.log('TEST', 'hello world');
    await logger.close();

    final files = tempDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.first.path, contains('debug-'));

    final content = files.first.readAsStringSync();
    expect(content, contains('Session started'));
    expect(content, contains('[TEST] hello world'));
  });

  test('logHttp writes method and status', () async {
    final logger = DebugLogger(logsDir: tempDir.path, enabled: true);
    logger.logHttp('POST', 'https://api.example.com/v1/chat', 200);
    await logger.close();

    final files = tempDir.listSync().whereType<File>().toList();
    final content = files.first.readAsStringSync();
    expect(content, contains('POST https://api.example.com/v1/chat'));
    expect(content, contains('200'));
  });

  test('no-ops when disabled', () async {
    final logger = DebugLogger(logsDir: tempDir.path, enabled: false);
    logger.log('TEST', 'should not appear');
    await logger.close();

    final files = tempDir.listSync().whereType<File>().toList();
    expect(files, isEmpty);
  });
}
