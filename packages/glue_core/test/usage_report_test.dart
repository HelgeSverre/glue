import 'package:glue_core/glue_core.dart';
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
          {'type': 'user_message', 'text': 'hi'}, // ignored
        ],
      );

      expect(report.rows.map((UsageReportRow r) => r.role), [
        'main',
        'subagent',
      ]);
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
      expect(report.rows.map((UsageReportRow r) => r.role), [
        'main',
        'subagent',
        'title',
        'aardvark',
        'audit',
      ]);
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
      expect(report.cacheHitRate, closeTo(0.9, 1e-9));
    });
  });

  group('UsageReport.toJson', () {
    test('round-trips structured data with nested totals + by_role', () {
      final report = buildUsageReport(
        modelLabel: 'anthropic/claude-sonnet-4.6',
        sessionId: 'sess-abc',
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
            'role': 'subagent',
            'input_tokens': 30,
            'output_tokens': 5,
            'turn_count': 1,
          },
        ],
      );

      final json = report.toJson();
      expect(json['model'], 'anthropic/claude-sonnet-4.6');
      expect(json['session_id'], 'sess-abc');
      final totals = json['totals'] as Map;
      expect(totals['calls'], 2);
      expect(totals['input_tokens'], 130);
      expect(totals['output_tokens'], 55);
      expect(totals['cache_read_tokens'], 800);
      expect(totals['cache_creation_tokens'], 200);
      expect(totals['total_tokens'], 1185);
      expect(totals['cache_hit_rate'], closeTo(800 / 930, 1e-9));

      final byRole = json['by_role'] as List;
      expect(byRole, hasLength(2));
      expect((byRole.first as Map)['role'], 'main');
      expect((byRole.last as Map)['role'], 'subagent');
      // Zero cache fields are omitted on the row level too.
      expect((byRole.last as Map).containsKey('cache_read_tokens'), isFalse);
    });

    test('omits cache_hit_rate when no LLM call has been recorded', () {
      final empty = buildUsageReport(usageEvents: const []).toJson();
      final totals = empty['totals'] as Map;
      expect(totals.containsKey('cache_hit_rate'), isFalse);
    });
  });
}
