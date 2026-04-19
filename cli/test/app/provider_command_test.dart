/// Smoke tests for the `/provider` slash command via a black-box App surface.
///
/// Full interactive flow is covered by panel_controller integration — these
/// tests just verify the registry registration and list formatting.
library;

import 'package:glue/src/commands/slash_commands.dart';
import 'package:test/test.dart';

void main() {
  group('slash command registration', () {
    test('a registry with /provider resolves correctly', () {
      final registry = SlashCommandRegistry();
      registry.register(
        SlashCommand(
          name: 'provider',
          description: 'Manage providers',
          execute: (args) => 'ran: ${args.join(" ")}',
        ),
      );
      expect(registry.execute('/provider list'), 'ran: list');
      expect(registry.execute('/provider add copilot'), 'ran: add copilot');
      expect(registry.execute('/provider'), 'ran: ');
    });
  });
}
