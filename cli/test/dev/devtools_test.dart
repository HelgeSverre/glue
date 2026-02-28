import 'package:test/test.dart';
import 'package:glue/src/dev/devtools.dart';

void main() {
  group('GlueDev', () {
    test('log does not throw without initialization', () {
      // Should be safe to call before init — no-ops gracefully
      expect(() => GlueDev.log('test', 'hello'), returnsNormally);
    });

    test('timeSync executes function and returns result', () {
      final result = GlueDev.timeSync('test', () => 42);
      expect(result, 42);
    });

    test('startAsync returns a TimelineTask', () {
      final task = GlueDev.startAsync('test');
      expect(task, isNotNull);
      task.finish();
    });

    test('postToolExec does not throw', () {
      expect(
        () => GlueDev.postToolExec(
          tool: 'bash',
          durationMs: 123,
          resultSizeBytes: 456,
        ),
        returnsNormally,
      );
    });

    test('postAgentStep does not throw', () {
      expect(
        () => GlueDev.postAgentStep(
          iteration: 1,
          toolsChosen: ['bash'],
          tokenDelta: 100,
        ),
        returnsNormally,
      );
    });

    test('postLlmRequest does not throw', () {
      expect(
        () => GlueDev.postLlmRequest(
          provider: 'anthropic',
          model: 'claude-sonnet-4-6',
          ttfbMs: 200,
          streamDurationMs: 3000,
          inputTokens: 500,
          outputTokens: 1200,
        ),
        returnsNormally,
      );
    });

    test('postRenderMetrics does not throw', () {
      expect(
        () => GlueDev.postRenderMetrics(
          frameMs: 16.6,
          blockCount: 10,
          lineCount: 200,
          overBudget: false,
        ),
        returnsNormally,
      );
    });

    test('registerExtensions does not throw', () {
      expect(
        () => GlueDev.registerExtensions(
          (name) => <String, dynamic>{'ext': name},
        ),
        returnsNormally,
      );
    });

    test('UserTag constants are distinct', () {
      expect(GlueDev.tagRender.label, 'Render');
      expect(GlueDev.tagLlmStream.label, 'LlmStream');
      expect(GlueDev.tagToolExec.label, 'ToolExec');
      expect(GlueDev.tagAgentLoop.label, 'AgentLoop');
    });
  });
}
