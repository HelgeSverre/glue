/// Keystroke-narrative integration test: drives `SlashAutocomplete`
/// against a minimal registry with real completers attached via
/// `attachArgCompleter`. Asserts observable behavior through the
/// transitions a user would experience typing a full command.
library;

import 'package:glue/glue.dart';
import 'package:glue/src/commands/arg_completers.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';
import 'package:test/test.dart';

SlashAutocomplete _setup() {
  final registry = SlashCommandRegistry();
  registry.register(SlashCommand(
    name: 'open',
    description: 'Open a Glue directory',
    execute: (_) => '',
  ));
  registry.register(SlashCommand(
    name: 'provider',
    description: 'Manage providers',
    execute: (_) => '',
  ));
  registry.register(SlashCommand(
    name: 'help',
    description: 'Show help',
    execute: (_) => '',
  ));
  registry.attachArgCompleter('open', openArgCandidates);
  registry.attachArgCompleter('provider', (prior, partial) {
    if (prior.isEmpty) return providerSubcommandCandidates(partial);
    return const [];
  });
  return SlashAutocomplete(registry);
}

void main() {
  group('SlashAutocomplete integration (keystroke narrative)', () {
    test('full /open session accept flow', () {
      final ac = _setup();

      // Type `/` → name mode, all commands.
      ac.update('/', 1);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 3); // open, provider, help

      // Type `o` → filters to /open (only one starts with 'o').
      ac.update('/o', 2);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
      expect(ac.selectedText, '/open ');

      // Type `p` → /open is the remaining match.
      ac.update('/op', 3);
      expect(ac.matchCount, 1);

      // Type space → transition to arg mode, 7 targets.
      ac.update('/open ', 6);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 7);

      // Type `s` → narrows to session, sessions, skills.
      ac.update('/open s', 7);
      expect(ac.matchCount, 3);
      expect(ac.selectedText, '/open session');

      // Accept (simulates Tab) → buffer becomes `/open session`.
      final result = ac.accept('/open s', 7);
      expect(result?.text, '/open session');
      expect(result?.cursor, '/open session'.length);
      expect(ac.active, isFalse);
    });

    test('provider add opens trailing-space subcommand', () {
      final ac = _setup();

      ac.update('/provider ', 10);
      expect(ac.matchCount, 4); // list, add, remove, test
      ac.moveDown(); // -> add (order is subcommands-map order)
      // Don't assume order; just find "add" and select it.
      // Reset and simulate typing `a` instead.
      ac.update('/provider a', 11);
      expect(ac.matchCount, 1);
      expect(ac.selectedText, '/provider add ');

      final result = ac.accept('/provider a', 11);
      expect(result?.text, '/provider add ');
      expect(result?.cursor, '/provider add '.length);
    });

    test('backspace across space reverts name mode', () {
      final ac = _setup();

      ac.update('/open ', 6);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 7);

      // User hits backspace, buffer drops the trailing space.
      ac.update('/open', 5);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1); // /open command candidate
      expect(ac.selectedText, '/open ');
    });

    test('Escape (dismiss) works from both modes', () {
      final ac = _setup();

      ac.update('/o', 2);
      expect(ac.active, isTrue);
      ac.dismiss();
      expect(ac.active, isFalse);

      ac.update('/open s', 7);
      expect(ac.active, isTrue);
      ac.dismiss();
      expect(ac.active, isFalse);
    });

    test('/help space dismisses (no completer)', () {
      final ac = _setup();
      ac.update('/help ', 6);
      expect(ac.active, isFalse);
    });

    test('unknown command + space dismisses', () {
      final ac = _setup();
      ac.update('/nope ', 6);
      expect(ac.active, isFalse);
    });
  });
}
