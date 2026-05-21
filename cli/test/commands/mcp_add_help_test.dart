import 'package:args/command_runner.dart';
import 'package:glue/src/commands/mcp_command.dart';
import 'package:test/test.dart';

void main() {
  group('glue mcp add --help', () {
    // We exercise this through the CommandRunner so the test mirrors what
    // users actually see — `description` is rendered at the top of the
    // auto-generated help block.
    final runner = CommandRunner<int>('glue', 'test')..addCommand(McpCommand());
    final help = runner.commands['mcp']!.subcommands['add']!.usage;

    test('mentions stdio + npx in examples', () {
      expect(help, contains('Examples:'));
      expect(
        help,
        contains('npx'),
        reason: 'npx-based servers are the most common shape',
      );
      expect(help, contains('--transport stdio'));
    });

    test('mentions hosted HTTP server with bearer auth example', () {
      expect(help, contains('--transport http'));
      expect(help, contains('--auth bearer'));
      expect(help, contains('https://'));
    });

    test('mentions docker as a local stdio shape', () {
      expect(
        help,
        contains('docker'),
        reason: 'a docker-run stdio example covers the local-container shape',
      );
    });
  });
}
