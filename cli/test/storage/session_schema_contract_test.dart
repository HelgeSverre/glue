import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue/src/generated/session_schemas_generated.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late JsonSchema metaSchema;
  late JsonSchema eventSchema;

  setUpAll(() {
    final root = Directory.current.parent.path;
    Object load(String name) =>
        jsonDecode(
              File(p.join(root, 'schemas', 'session', name)).readAsStringSync(),
            )
            as Object;
    expect(jsonDecode(sessionMetaV5SchemaJson), load('meta-v5.schema.json'));
    expect(
      jsonDecode(conversationEventV1SchemaJson),
      load('conversation-event-v1.schema.json'),
    );
    metaSchema = JsonSchema.create(
      jsonDecode(sessionMetaV5SchemaJson) as Object,
      schemaVersion: SchemaVersion.draft2020_12,
    );
    eventSchema = JsonSchema.create(
      jsonDecode(conversationEventV1SchemaJson) as Object,
      schemaVersion: SchemaVersion.draft2020_12,
    );
  });

  test('metadata serializer conforms to meta v5', () {
    final meta = SessionMeta(
      id: const SessionId('schema-session'),
      cwd: '/tmp/project',
      modelRef: 'anthropic/claude-sonnet-4-6',
      startTime: DateTime.utc(2026, 8, 12),
    );
    expect(
      metaSchema.validate(meta.toJson(), validateFormats: true).errors,
      isEmpty,
    );
  });

  test('all persisted event families conform to transcript v1', () {
    final temp = Directory.systemTemp.createTempSync('glue_schema_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = SessionStore(
      sessionDir: p.join(temp.path, 'schema-session'),
      meta: SessionMeta(
        id: const SessionId('schema-session'),
        cwd: '/tmp/project',
        modelRef: 'anthropic/claude-sonnet-4-6',
        startTime: DateTime.utc(2026, 8, 12),
      ),
    );
    final events = <(String, Map<String, dynamic>)>[
      ('user_message', {'text': 'hello'}),
      (
        'assistant_message',
        {'text': 'hi', 'model_ref': 'anthropic/claude-sonnet-4-6'},
      ),
      (
        'assistant_thinking',
        {'text': 'considering', 'model_ref': 'anthropic/claude-sonnet-4-6'},
      ),
      (
        'tool_call',
        {'id': 'call-1', 'name': 'read', 'arguments': <String, dynamic>{}},
      ),
      (
        'tool_result',
        {
          'call_id': 'call-1',
          'content': 'ok',
          'success': true,
          'status': 'completed',
        },
      ),
      (
        'usage',
        {
          'role': 'main',
          'model_ref': 'anthropic/claude-sonnet-4-6',
          'input_tokens': 1,
          'output_tokens': 2,
          'turn_count': 1,
        },
      ),
      ('title_generated', {'title': 'A title'}),
      ('title_reevaluated', {'title': 'A better title'}),
      ('agent_notice', {'kind': 'info', 'message': 'notice'}),
      (
        'subagent_spawned',
        {
          'subagent_id': 'sub-1',
          'task': 'inspect',
          'depth': 0,
          'model_ref': 'anthropic/claude-haiku-4-5',
        },
      ),
      (
        'subagent_event',
        {
          'subagent_id': 'sub-1',
          'inner': {'type': 'assistant_message', 'text': 'done'},
        },
      ),
      (
        'subagent_usage',
        {
          'subagent_id': 'sub-1',
          'model_ref': 'anthropic/claude-haiku-4-5',
          'input_tokens': 1,
          'output_tokens': 2,
          'turn_count': 1,
        },
      ),
      (
        'subagent_completed',
        {'subagent_id': 'sub-1', 'status': 'completed', 'duration_ms': 4},
      ),
    ];
    for (final (type, data) in events) {
      store.logEvent(type, data);
    }
    final rows = File(
      p.join(store.sessionDir, 'conversation.jsonl'),
    ).readAsLinesSync().map(jsonDecode);
    for (final row in rows) {
      expect(
        eventSchema.validate(row, validateFormats: true).errors,
        isEmpty,
        reason: jsonEncode(row),
      );
    }
  });
}
