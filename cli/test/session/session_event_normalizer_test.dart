import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeSessionEvent', () {
    test('ignores internal title lifecycle rows', () {
      expect(
        normalizeSessionEvent({'type': 'title_generated', 'title': 'ignored'}),
        isNull,
      );
      expect(
        normalizeSessionEvent(
            {'type': 'title_reevaluated', 'title': 'ignored'}),
        isNull,
      );
    });

    test('normalizes tool result with summary and preserves raw content', () {
      final event = normalizeSessionEvent({
        'type': 'tool_result',
        'call_id': 'c1',
        'summary': '2 files changed',
        'content': 'full diff payload',
      });

      expect(event, isNotNull);
      expect(event!.kind, NormalizedSessionEventKind.toolResult);
      expect(event.visibleText, '2 files changed');
      expect(event.text, 'full diff payload');
      expect(event.toolCallId, 'c1');
    });

    test('normalizes tool arguments from generic map values', () {
      final event = normalizeSessionEvent({
        'type': 'tool_call',
        'id': 'c1',
        'name': 'read_file',
        'arguments': {'path': 'README.md'},
      });

      expect(event, isNotNull);
      expect(event!.kind, NormalizedSessionEventKind.toolCall);
      expect(event.toolName, 'read_file');
      expect(event.toolArguments, {'path': 'README.md'});
    });

    test('normalizes subagent_spawned with index/total/depth', () {
      final event = normalizeSessionEvent({
        'type': 'subagent_spawned',
        'subagent_id': 'sub-x',
        'task': 'inspect repo',
        'index': 1,
        'total': 3,
        'depth': 0,
      });

      expect(event, isNotNull);
      expect(event!.kind, NormalizedSessionEventKind.subagentSpawned);
      expect(event.subagentId, 'sub-x');
      expect(event.text, 'inspect repo');
      expect(event.subagentIndex, 1);
      expect(event.subagentTotal, 3);
      expect(event.subagentDepth, 0);
    });

    test('normalizes subagent_event by recursing into the inner payload', () {
      final event = normalizeSessionEvent({
        'type': 'subagent_event',
        'subagent_id': 'sub-x',
        'inner': {
          'type': 'tool_call',
          'name': 'read_file',
          'arguments': {'path': 'a.dart'},
        },
      });

      expect(event, isNotNull);
      expect(event!.kind, NormalizedSessionEventKind.subagentEvent);
      expect(event.subagentId, 'sub-x');
      expect(event.subagentInner, isNotNull);
      expect(event.subagentInner!.kind, NormalizedSessionEventKind.toolCall);
      expect(event.subagentInner!.toolName, 'read_file');
    });

    test('normalizes subagent_completed with optional error', () {
      final ok = normalizeSessionEvent({
        'type': 'subagent_completed',
        'subagent_id': 'sub-x',
      });
      expect(ok, isNotNull);
      expect(ok!.kind, NormalizedSessionEventKind.subagentCompleted);
      expect(ok.subagentError, isNull);

      final err = normalizeSessionEvent({
        'type': 'subagent_completed',
        'subagent_id': 'sub-x',
        'error': 'boom',
      });
      expect(err, isNotNull);
      expect(err!.subagentError, 'boom');
    });

    test('skips subagent rows without a subagent_id', () {
      expect(
        normalizeSessionEvent({'type': 'subagent_spawned', 'task': 't'}),
        isNull,
      );
      expect(
        normalizeSessionEvent({'type': 'subagent_completed'}),
        isNull,
      );
    });

    test('skips subagent_event with malformed inner payload', () {
      expect(
        normalizeSessionEvent({
          'type': 'subagent_event',
          'subagent_id': 'sub-x',
          'inner': 'not-a-map',
        }),
        isNull,
      );
    });
  });
}
