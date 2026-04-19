import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';
import 'package:test/test.dart';

void main() {
  group('SlashAutocomplete', () {
    late SlashCommandRegistry registry;
    late SlashAutocomplete ac;

    setUp(() {
      registry = SlashCommandRegistry();
      // Register 12 commands whose names all start with "cmd" so a single
      // prefix query produces a long match list.
      for (var i = 0; i < 12; i++) {
        registry.register(SlashCommand(
          name: 'cmd${i.toString().padLeft(2, '0')}',
          description: 'command number $i',
          execute: (_) => '',
        ));
      }
      ac = SlashAutocomplete(registry);
    });

    test('activates on / with prefix and collects matching commands', () {
      ac.update('/cmd', 4);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 12);
      expect(ac.selected, 0);
    });

    test('render window scrolls to keep selection visible past maxVisible', () {
      ac.update('/cmd', 4);
      for (var i = 0; i < 9; i++) {
        ac.moveDown();
      }
      expect(ac.selected, 9);

      final lines = ac.render(80);
      expect(lines.length, 8);
      expect(lines.any((l) => l.contains('/cmd09')), isTrue,
          reason: 'row 9 should be inside the visible window');
      expect(lines.any((l) => l.contains('/cmd00')), isFalse,
          reason: 'row 0 should have scrolled off');
    });

    test('render window snaps to the bottom when Up wraps past index 0', () {
      ac.update('/cmd', 4);
      ac.moveUp();
      expect(ac.selected, 11);

      final lines = ac.render(80);
      expect(lines.length, 8);
      expect(lines.any((l) => l.contains('/cmd11')), isTrue);
    });

    test('dismiss resets scroll state', () {
      ac.update('/cmd', 4);
      for (var i = 0; i < 10; i++) {
        ac.moveDown();
      }
      ac.dismiss();
      expect(ac.active, isFalse);
      expect(ac.selected, 0);

      // Re-activating starts at the top again.
      ac.update('/cmd', 4);
      final lines = ac.render(80);
      expect(lines.any((l) => l.contains('/cmd00')), isTrue);
    });
  });
}
