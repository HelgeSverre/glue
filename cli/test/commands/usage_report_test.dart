import 'package:glue/src/commands/usage_report.dart';
import 'package:test/test.dart';

void main() {
  group('buildUsageReport', () {
    test('aggregates persisted usage rows by role', () {
      final report = buildUsageReport(
        usageEvents: [
          {
            'type': 'usage',
            'role': 'main',
            'input_tokens': 100,
            'output_tokens': 50,
            'cache_read_tokens': 800,
            'cache_creation_tokens': 200,
            'turn_count': 1,
          },
          {
            'type': 'usage',
            'role': 'main',
            'input_tokens': 60,
            'output_tokens': 30,
            'turn_count': 1,
          },
          {
            'type': 'usage',
            'role': 'subagent',
            'input_tokens': 40,
            'output_tokens': 10,
            'turn_count': 1,
          },
          // Non-usage rows are ignored.
          {'type': 'user_message', 'text': 'hi'},
        ],
      );

      expect(report.rows.map((r) => r.role), ['main', 'subagent']);
      final main = report.rows.first;
      expect(main.calls, 2);
      expect(main.input, 160);
      expect(main.output, 80);
      expect(main.cacheRead, 800);
      expect(main.cacheWrite, 200);
      expect(report.totalCalls, 3);
      expect(report.totalTokens, 100 + 50 + 800 + 200 + 60 + 30 + 40 + 10);
    });

    test('orders known roles main → subagent → title; unknown roles after', () {
      final report = buildUsageReport(
        usageEvents: [
          {'type': 'usage', 'role': 'title', 'input_tokens': 1},
          {'type': 'usage', 'role': 'subagent', 'input_tokens': 1},
          {'type': 'usage', 'role': 'audit', 'input_tokens': 1},
          {'type': 'usage', 'role': 'main', 'input_tokens': 1},
          {'type': 'usage', 'role': 'aardvark', 'input_tokens': 1},
        ],
      );
      expect(report.rows.map((r) => r.role),
          ['main', 'subagent', 'title', 'aardvark', 'audit']);
    });

    test('cacheHitRate is null when no LLM call recorded', () {
      final report = buildUsageReport(usageEvents: const []);
      expect(report.cacheHitRate, isNull);
      expect(report.totalCalls, 0);
    });

    test('cacheHitRate reflects cache reads as fraction of billed input', () {
      final report = buildUsageReport(
        usageEvents: [
          {
            'type': 'usage',
            'role': 'main',
            'input_tokens': 100,
            'cache_read_tokens': 900,
            'turn_count': 1,
          },
        ],
      );
      // 900 of (100 + 900) = 90%
      expect(report.cacheHitRate, closeTo(0.9, 1e-9));
    });
  });

  group('formatUsageReport', () {
    test('returns a friendly message when there are no rows', () {
      final report = buildUsageReport(usageEvents: const []);
      expect(formatUsageReport(report),
          'No LLM calls recorded yet for this session.');
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
      // Numbers thousand-grouped, padded.
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
