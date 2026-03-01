import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('session_resume_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('SessionStore.listSessions', () {
    test('returns empty list when no sessions', () {
      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions, isEmpty);
    });

    test('returns sessions sorted newest first', () {
      _createSession(tmpDir.path, 'sess-1', DateTime(2026, 1, 1), 'model-a');
      _createSession(tmpDir.path, 'sess-2', DateTime(2026, 1, 3), 'model-b');
      _createSession(tmpDir.path, 'sess-3', DateTime(2026, 1, 2), 'model-c');

      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions.length, 3);
      expect(sessions[0].id, 'sess-2');
      expect(sessions[1].id, 'sess-3');
      expect(sessions[2].id, 'sess-1');
    });

    test('loads session title from meta.json', () {
      final dir =
          _createSession(tmpDir.path, 'sess-t', DateTime.now(), 'model');
      final metaFile = File(p.join(dir, 'meta.json'));
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      meta['title'] = 'Fix auth bug';
      metaFile.writeAsStringSync(jsonEncode(meta));

      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions.first.title, 'Fix auth bug');
    });

    test('sessions without title have null title', () {
      _createSession(tmpDir.path, 'sess-no-title', DateTime.now(), 'model');
      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions.first.title, isNull);
    });

    test('skips directories without meta.json', () {
      Directory(p.join(tmpDir.path, 'broken-session')).createSync();
      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions, isEmpty);
    });
  });

  group('SessionStore.loadConversation', () {
    test('loads user and assistant events', () {
      final sessDir =
          _createSession(tmpDir.path, 'sess-1', DateTime.now(), 'model');
      _appendEvent(sessDir, 'user_message', {'text': 'hello'});
      _appendEvent(sessDir, 'assistant_message', {'text': 'hi there'});

      final events = SessionStore.loadConversation(sessDir);
      expect(events.length, 2);
      expect(events[0]['type'], 'user_message');
      expect(events[1]['type'], 'assistant_message');
    });

    test('returns empty list for missing conversation file', () {
      final sessDir = p.join(tmpDir.path, 'empty-sess');
      Directory(sessDir).createSync();
      final events = SessionStore.loadConversation(sessDir);
      expect(events, isEmpty);
    });
  });
}

String _createSession(String base, String id, DateTime start, String model) {
  final dir = p.join(base, id);
  Directory(dir).createSync(recursive: true);
  final meta = {
    'id': id,
    'cwd': '/tmp',
    'model': model,
    'provider': 'anthropic',
    'start_time': start.toIso8601String(),
  };
  File(p.join(dir, 'meta.json')).writeAsStringSync(jsonEncode(meta));
  return dir;
}

void _appendEvent(String sessDir, String type, Map<String, dynamic> data) {
  final file = File(p.join(sessDir, 'conversation.jsonl'));
  final record = {
    'timestamp': DateTime.now().toIso8601String(),
    'type': type,
    ...data,
  };
  file.writeAsStringSync('${jsonEncode(record)}\n', mode: FileMode.append);
}
