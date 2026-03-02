import 'package:test/test.dart';
import 'package:glue/src/dev/devtools.dart';

void main() {
  group('GlueDev', () {
    test('timeSync executes function and returns result', () {
      final result = GlueDev.timeSync('test', () => 42);
      expect(result, 42);
    });

    test('startAsync returns a TimelineTask', () {
      final task = GlueDev.startAsync('test');
      expect(task, isNotNull);
      task.finish();
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
