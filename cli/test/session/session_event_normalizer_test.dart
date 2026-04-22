import 'package:glue/src/session/session_event_normalizer.dart';
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
  });
}
