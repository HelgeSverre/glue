import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String sessionDir;
  late SessionMeta meta;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_store_test_');
    sessionDir = p.join(tempDir.path, 'session-001');
    meta = SessionMeta(
      id: const SessionId('session-001'),
      cwd: '/tmp/project',
      modelRef: 'anthropic/claude-sonnet-4.6',
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

    final savedMeta = SessionMeta.fromJson(
      jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(savedMeta.id, 'session-001');
    expect(savedMeta.modelRef, 'anthropic/claude-sonnet-4.6');
  });

  test('toJson always emits the current schema version (H4)', () {
    SessionStore(sessionDir: sessionDir, meta: meta);
    final metaJson =
        jsonDecode(File(p.join(sessionDir, 'meta.json')).readAsStringSync())
            as Map<String, dynamic>;
    expect(metaJson['schema_version'], SessionMeta.currentSchemaVersion);
    expect(metaJson['model_ref'], 'anthropic/claude-sonnet-4.6');
    expect(metaJson['glue_version'], AppConstants.version);
    expect(metaJson['transcript_schema_version'], 1);
    expect(metaJson['termination_status'], 'running');
  });

  test('legacy session model_ref survives a save/load round-trip (H4)', () {
    // A schema-1 session stored the model in separate model/provider fields.
    final legacy = SessionMeta.fromJson({
      'schema_version': 1,
      'id': 'legacy-1',
      'cwd': '/tmp/project',
      'model': 'claude-3-5-sonnet',
      'provider': 'anthropic',
      'start_time': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    expect(legacy.modelRef, 'anthropic/claude-3-5-sonnet');

    // Persisting rewrites the file in the v3 shape (model_ref only). Before
    // the fix it kept schema_version: 1, so reloading dropped model_ref and
    // resolved to anthropic/unknown.
    final reloaded = SessionMeta.fromJson(
      jsonDecode(jsonEncode(legacy.toJson())) as Map<String, dynamic>,
    );
    expect(reloaded.schemaVersion, SessionMeta.currentSchemaVersion);
    expect(reloaded.modelRef, 'anthropic/claude-3-5-sonnet');
  });

  test('logEvent appends JSONL lines', () async {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'hello'});
    store.logEvent('assistant_message', {'text': 'hi there'});
    await store.close();

    final lines = File(
      p.join(sessionDir, 'conversation.jsonl'),
    ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(2));

    final first = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(first['type'], 'user_message');
    expect(first['text'], 'hello');
    expect(first['timestamp'], isNotNull);
    expect(first['schema_version'], 1);
    expect(first['event_id'], 'session-001:1');
    expect(first['session_id'], 'session-001');
    expect(first['sequence'], 1);

    final second = jsonDecode(lines[1]) as Map<String, dynamic>;
    expect(second['type'], 'assistant_message');
    expect(second['text'], 'hi there');
    expect(second['event_id'], 'session-001:2');
    expect(second['sequence'], 2);
  });

  test('loadConversation skips corrupt/torn tail lines (M12)', () {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'hello'});
    // Simulate a torn tail line from a crash mid-append.
    File(p.join(sessionDir, 'conversation.jsonl')).writeAsStringSync(
      '{"type":"assistant_message","text":"partia',
      mode: FileMode.append,
    );

    final events = SessionStore.loadConversation(sessionDir);

    // The valid record survives; the corrupt tail is dropped, not fatal.
    expect(events, hasLength(1));
    expect(events.single['type'], 'user_message');
  });

  test('session dir and files get owner-only perms (L3)', () {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'hello'});

    if (Platform.isWindows) return; // POSIX-only perms.

    int perms(String path) => File(path).statSync().mode & 0x1FF;
    int dirPerms(String path) => Directory(path).statSync().mode & 0x1FF;

    expect(dirPerms(sessionDir), 0x1C0); // 0700
    expect(perms(p.join(sessionDir, 'meta.json')), 0x180); // 0600
    expect(perms(p.join(sessionDir, 'conversation.jsonl')), 0x180); // 0600
  });

  test('setTitle persists title to meta.json', () {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.setTitle('Fix auth bug');

    final metaJson = jsonDecode(
      File(p.join(sessionDir, 'meta.json')).readAsStringSync(),
    );
    expect((metaJson as Map<String, dynamic>)['title'], 'Fix auth bug');
  });

  test('title is omitted from meta.json when null', () {
    SessionStore(sessionDir: sessionDir, meta: meta);

    final metaJson =
        jsonDecode(File(p.join(sessionDir, 'meta.json')).readAsStringSync())
            as Map<String, dynamic>;
    expect(metaJson.containsKey('title'), isFalse);
  });

  test('close writes endTime to meta.json', () async {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    await store.close();

    final savedMeta = SessionMeta.fromJson(
      jsonDecode(File(p.join(sessionDir, 'meta.json')).readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(savedMeta.endTime, isNotNull);
    expect(savedMeta.terminationStatus, SessionTerminationStatus.completed);
  });

  test('new events continue sequence after legacy rows', () {
    Directory(sessionDir).createSync(recursive: true);
    File(p.join(sessionDir, 'conversation.jsonl')).writeAsStringSync(
      '${jsonEncode({'timestamp': '2026-01-01T00:00:00Z', 'type': 'user_message', 'text': 'legacy'})}\n',
    );
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'new'});

    final rows = File(p.join(sessionDir, 'conversation.jsonl'))
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(rows.first.containsKey('schema_version'), isFalse);
    expect(rows.last['sequence'], 2);
    expect(rows.last['event_id'], 'session-001:2');
  });

  test('atomic writes do not leave temporary files behind', () async {
    final store = SessionStore(sessionDir: sessionDir, meta: meta);
    store.logEvent('user_message', {'text': 'hello'});
    store.setTitle('Atomic title');
    await store.close();

    expect(File(p.join(sessionDir, 'meta.json.tmp')).existsSync(), isFalse);
    expect(
      File(p.join(sessionDir, 'conversation.jsonl.tmp')).existsSync(),
      isFalse,
    );
  });
}
