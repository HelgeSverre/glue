import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/storage/session_store.dart';

void main() {
  late Directory tempDir;
  late String sessionDir;
  late SessionMeta meta;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_store_test_');
    sessionDir = p.join(tempDir.path, 'session-001');
    meta = SessionMeta(
      id: 'session-001',
      cwd: '/tmp/project',
      model: 'claude-sonnet-4-6',
      provider: 'anthropic',
      startTime: DateTime.utc(2026, 2, 27, 10, 0),
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('creates session directory and meta.json on init', () {
    SessionStore(sessionDir: sessionDir, meta: meta);

    expect(Directory(sessionDir).existsSync(), isTrue);
    final metaFile = File(p.join(sessionDir, 'meta.json'));
    expect(metaFile.existsSync(), isTrue);

    final metaJson = jsonDecode(metaFile.readAsStringSync());
    expect(metaJson['id'], 'session-001');
    expect(metaJson['model'], 'claude-sonnet-4-6');
  });

  test('logEvent appends JSONL lines', () async {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'hello'});
    store.logEvent('assistant_message', {'text': 'hi there'});
    await store.close();

    final lines = File(p.join(sessionDir, 'conversation.jsonl'))
        .readAsLinesSync()
        .where((l) => l.isNotEmpty)
        .toList();
    expect(lines, hasLength(2));

    final first = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(first['type'], 'user_message');
    expect(first['text'], 'hello');
    expect(first['timestamp'], isNotNull);

    final second = jsonDecode(lines[1]) as Map<String, dynamic>;
    expect(second['type'], 'assistant_message');
    expect(second['text'], 'hi there');
  });

  test('close writes endTime to meta.json', () async {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    await store.close();

    final metaJson = jsonDecode(
      File(p.join(sessionDir, 'meta.json')).readAsStringSync(),
    );
    expect(metaJson['end_time'], isNotNull);
  });
}
