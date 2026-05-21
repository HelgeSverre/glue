import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

void main() {
  group('UsageStats', () {
    test('records a UsageInfo and increments turn count', () {
      final stats = UsageStats();
      stats.record(
        UsageInfo(
          inputTokens: 100,
          outputTokens: 20,
          cacheReadTokens: 800,
          cacheCreationTokens: 50,
        ),
      );

      expect(stats.inputTokens, 100);
      expect(stats.outputTokens, 20);
      expect(stats.cacheReadTokens, 800);
      expect(stats.cacheCreationTokens, 50);
      expect(stats.turnCount, 1);
      expect(stats.totalTokens, 970);
      expect(stats.billedInputTokens, 900);
      expect(stats.cacheHitRate, closeTo(800 / 900, 1e-9));
    });

    test('treats null cache fields on UsageInfo as zero', () {
      final stats = UsageStats();
      stats.record(UsageInfo(inputTokens: 50, outputTokens: 10));
      expect(stats.cacheReadTokens, 0);
      expect(stats.cacheCreationTokens, 0);
      expect(stats.turnCount, 1);
      expect(stats.cacheHitRate, 0.0);
    });

    test('cacheHitRate is null when no LLM call has been recorded', () {
      expect(UsageStats().cacheHitRate, isNull);
    });

    test('merge folds another stats object into this one', () {
      final parent = UsageStats(inputTokens: 100, outputTokens: 50);
      parent.merge(
        UsageStats(
          inputTokens: 200,
          outputTokens: 30,
          cacheReadTokens: 500,
          turnCount: 3,
        ),
      );
      expect(parent.inputTokens, 300);
      expect(parent.outputTokens, 80);
      expect(parent.cacheReadTokens, 500);
      expect(parent.turnCount, 3);
    });

    test('snapshot decouples future mutations', () {
      final live = UsageStats(inputTokens: 10);
      final snap = live.snapshot();
      live.inputTokens = 999;
      expect(snap.inputTokens, 10);
    });

    test('toJson omits zero cache fields, fromJson round-trips', () {
      final lean = UsageStats(
        inputTokens: 100,
        outputTokens: 50,
        turnCount: 1,
      ).toJson();
      expect(lean.containsKey('cache_read_tokens'), isFalse);
      expect(lean.containsKey('cache_creation_tokens'), isFalse);

      final full = UsageStats(
        inputTokens: 100,
        outputTokens: 50,
        cacheReadTokens: 800,
        cacheCreationTokens: 200,
        turnCount: 2,
      ).toJson();
      expect(full['cache_read_tokens'], 800);
      expect(full['cache_creation_tokens'], 200);

      final restored = UsageStats.fromJson(full);
      expect(restored.inputTokens, 100);
      expect(restored.outputTokens, 50);
      expect(restored.cacheReadTokens, 800);
      expect(restored.cacheCreationTokens, 200);
      expect(restored.turnCount, 2);
    });
  });

  group('AgentUsage event', () {
    test('carries the underlying UsageInfo', () {
      final usage = UsageInfo(inputTokens: 1, outputTokens: 2);
      final event = AgentUsage(usage);
      expect(event, isA<AgentEvent>());
      expect(event.usage, same(usage));
    });
  });
}
