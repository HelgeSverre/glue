import 'package:glue/src/commands/usage_report.dart';
import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

void main() {
  group('formatUsageReport', () {
    test('returns a friendly message when there are no rows', () {
      final report = buildUsageReport(usageEvents: const []);
      expect(
        formatUsageReport(report),
        'No LLM calls recorded yet for this session.',
      );
    });

    test('renders a table with header + rows + totals + cache hit rate', () {
      final report = buildUsageReport(
        modelLabel: 'anthropic/claude-sonnet-4.6',
        sessionId: 'sess-abc',
        usageEvents: [
          {
            'type': 'usage',
            'role': 'main',
            'input_tokens': 1000,
            'output_tokens': 500,
            'cache_read_tokens': 18000,
            'cache_creation_tokens': 3000,
            'turn_count': 5,
          },
          {
            'type': 'usage',
            'role': 'subagent',
            'input_tokens': 300,
            'output_tokens': 100,
            'turn_count': 2,
          },
        ],
      );

      final output = formatUsageReport(report);
      expect(output, contains('Token usage'));
      expect(output, contains('Model:        anthropic/claude-sonnet-4.6'));
      expect(output, contains('Session:      sess-abc'));
      expect(output, contains('LLM calls:    7'));
      expect(output, contains('Total tokens: 22,900'));
      // 18000 / (1300 + 18000) = ~93.3%
      expect(output, contains('Cache hit:    93.3%'));
      expect(output, contains('main'));
      expect(output, contains('subagent'));
      expect(output, contains('18,000'));
    });

    test('skips the cache hit line when no cache activity occurred', () {
      final report = buildUsageReport(
        usageEvents: [
          {
            'type': 'usage',
            'role': 'main',
            'input_tokens': 50,
            'output_tokens': 10,
            'turn_count': 1,
          },
        ],
      );
      expect(formatUsageReport(report), isNot(contains('Cache hit:')));
    });
  });
}
