import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:test/test.dart';

void main() {
  group('BashTool', () {
    late BashTool tool;

    setUp(() {
      tool = BashTool(HostExecutor(const ShellConfig()));
    });

    test('executes command with default timeout', () async {
      final result = (await tool.execute({'command': 'echo hello'})).content;
      expect(result, contains('hello'));
    });

    test('respects timeout_seconds parameter', () async {
      final result = (await tool.execute({
        'command': 'echo no-timeout',
        'timeout_seconds': 0,
      }))
          .content;
      expect(result, contains('no-timeout'));
    });

    test('has timeout_seconds in parameters', () {
      expect(
        tool.parameters.any((p) => p.name == 'timeout_seconds'),
        isTrue,
      );
    });
  });
}
