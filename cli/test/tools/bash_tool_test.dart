import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  group('BashTool', () {
    test('executes command with default timeout', () async {
      final tool = BashTool();
      final result = await tool.execute({'command': 'echo hello'});
      expect(result, contains('hello'));
    });

    test('respects timeout_seconds parameter', () async {
      final tool = BashTool();
      final result = await tool.execute({
        'command': 'echo no-timeout',
        'timeout_seconds': 0,
      });
      expect(result, contains('no-timeout'));
    });

    test('has timeout_seconds in parameters', () {
      final tool = BashTool();
      expect(
        tool.parameters.any((p) => p.name == 'timeout_seconds'),
        isTrue,
      );
    });
  });
}
