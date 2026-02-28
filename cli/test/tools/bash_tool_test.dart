import 'package:test/test.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';

void main() {
  group('BashTool', () {
    late BashTool tool;

    setUp(() {
      tool = BashTool(HostExecutor(const ShellConfig()));
    });

    test('executes command with default timeout', () async {
      final result = ContentPart.textOnly(await tool.execute({'command': 'echo hello'}));
      expect(result, contains('hello'));
    });

    test('respects timeout_seconds parameter', () async {
      final result = ContentPart.textOnly(await tool.execute({
        'command': 'echo no-timeout',
        'timeout_seconds': 0,
      }));
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
