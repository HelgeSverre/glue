import 'package:test/test.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';

SlashCommandRegistry _makeRegistry() {
  final reg = SlashCommandRegistry();
  reg.register(SlashCommand(
    name: 'help',
    description: 'Show available commands',
    execute: (_) => '',
  ));
  reg.register(SlashCommand(
    name: 'clear',
    description: 'Clear conversation history',
    execute: (_) => '',
  ));
  reg.register(SlashCommand(
    name: 'compact',
    description: 'Toggle compact mode',
    execute: (_) => '',
  ));
  reg.register(SlashCommand(
    name: 'model',
    description: 'Show or change model',
    execute: (_) => '',
  ));
  reg.register(SlashCommand(
    name: 'exit',
    description: 'Exit the application',
    aliases: ['quit'],
    hiddenAliases: ['q'],
    execute: (_) => '',
  ));
  return reg;
}

void main() {
  group('SlashAutocomplete', () {
    late SlashAutocomplete ac;

    setUp(() {
      ac = SlashAutocomplete(_makeRegistry());
    });

    test('starts inactive', () {
      expect(ac.active, isFalse);
      expect(ac.overlayHeight, 0);
    });

    test('activates on "/" prefix', () {
      ac.update('/', 1);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 6); // 5 commands + quit alias
    });

    test('filters by prefix', () {
      ac.update('/c', 2);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 2); // clear, compact
    });

    test('filters to single match', () {
      ac.update('/he', 3);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
    });

    test('dismisses when no matches', () {
      ac.update('/xyz', 4);
      expect(ac.active, isFalse);
    });

    test('dismisses on space after command', () {
      ac.update('/help ', 6);
      expect(ac.active, isFalse);
    });

    test('dismisses on empty buffer', () {
      ac.update('/', 1);
      expect(ac.active, isTrue);
      ac.update('', 0);
      expect(ac.active, isFalse);
    });

    test('dismisses when buffer does not start with /', () {
      ac.update('hello', 5);
      expect(ac.active, isFalse);
    });

    test('dismisses when cursor not at end', () {
      ac.update('/he', 1); // cursor at position 1, not end
      expect(ac.active, isFalse);
    });

    test('moveDown wraps around', () {
      ac.update('/', 1);
      expect(ac.selected, 0);
      for (var i = 0; i < 6; i++) {
        ac.moveDown();
      }
      expect(ac.selected, 0); // wrapped
    });

    test('moveUp wraps around', () {
      ac.update('/', 1);
      expect(ac.selected, 0);
      ac.moveUp(); // wraps to last
      expect(ac.selected, 5);
    });

    test('accept returns selected command', () {
      ac.update('/c', 2);
      expect(ac.active, isTrue);
      ac.moveDown(); // select compact
      final result = ac.accept('', 0);
      expect(result?.text, '/compact');
      expect(ac.active, isFalse);
    });

    test('accept returns first match by default', () {
      ac.update('/c', 2);
      final result = ac.accept('', 0);
      expect(result?.text, '/clear');
    });

    test('accept returns null when inactive', () {
      final result = ac.accept('', 0);
      expect(result, isNull);
    });

    test('hidden aliases do not appear in autocomplete', () {
      ac.update('/q', 2);
      expect(ac.active, isTrue);
      expect(ac.selectedText, '/quit'); // /quit matches, not /q
      expect(ac.matchCount, 1); // only /quit, not /q
    });

    test('dismiss resets state', () {
      ac.update('/', 1);
      ac.moveDown();
      ac.dismiss();
      expect(ac.active, isFalse);
      expect(ac.selected, 0);
      expect(ac.matchCount, 0);
    });

    test('selected clamps when matches shrink', () {
      ac.update('/', 1);
      ac.moveDown();
      ac.moveDown(); // selected = 2
      ac.update('/he', 3); // only 1 match now
      expect(ac.selected, 0);
    });

    test('render produces correct number of lines', () {
      ac.update('/', 1);
      final lines = ac.render(80);
      expect(lines, hasLength(6));
    });

    test('render returns empty when inactive', () {
      final lines = ac.render(80);
      expect(lines, isEmpty);
    });

    test('overlayHeight matches match count', () {
      ac.update('/', 1);
      expect(ac.overlayHeight, 6);
      ac.update('/he', 3);
      expect(ac.overlayHeight, 1);
      ac.dismiss();
      expect(ac.overlayHeight, 0);
    });
  });

  group('SlashAutocomplete arg mode', () {
    late SlashCommandRegistry registry;
    late SlashAutocomplete ac;

    setUp(() {
      registry = _makeRegistry();
      // Attach a completer to /model with 3 static candidates.
      registry.attachArgCompleter('model', (prior, partial) {
        if (prior.isNotEmpty) return const [];
        const values = ['sonnet', 'opus', 'haiku'];
        return values
            .where((v) => v.startsWith(partial))
            .map((v) => SlashArgCandidate(value: v, description: 'Claude $v'))
            .toList();
      });
      // Attach a 2-level completer to /exit (nonsensical semantically, but
      // proves alias lookup works — /q should hit this completer too).
      registry.attachArgCompleter('exit', (prior, partial) {
        const subs = ['now', 'later'];
        return subs
            .where((v) => v.startsWith(partial))
            .map((v) => SlashArgCandidate(
                  value: v,
                  description: 'Exit $v',
                  continues: v == 'later',
                ))
            .toList();
      });
      ac = SlashAutocomplete(registry);
    });

    test('activates in arg mode after space on known command', () {
      ac.update('/model ', 7);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 3); // sonnet, opus, haiku
    });

    test('narrows arg candidates by prefix', () {
      ac.update('/model s', 8);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
      expect(ac.selectedText, '/model sonnet');
    });

    test('dismisses for unknown command + space', () {
      ac.update('/notarealcmd ', 13);
      expect(ac.active, isFalse);
    });

    test('dismisses when command has no completer', () {
      ac.update('/help ', 6);
      expect(ac.active, isFalse);
    });

    test('dismisses when completer returns empty list', () {
      ac.update('/model zzz', 10);
      expect(ac.active, isFalse);
    });

    test('accept splices arg value into buffer', () {
      ac.update('/model s', 8);
      final result = ac.accept('/model s', 8);
      expect(result?.text, '/model sonnet');
      expect(result?.cursor, '/model sonnet'.length);
    });

    test('accept with continues:true appends trailing space', () {
      ac.update('/exit l', 7);
      expect(ac.matchCount, 1);
      final result = ac.accept('/exit l', 7);
      expect(result?.text, '/exit later ');
      expect(result?.cursor, '/exit later '.length);
    });

    test('alias lookup reaches parent command completer', () {
      ac.update('/q n', 4);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
      final result = ac.accept('/q n', 4);
      expect(result?.text, '/q now');
    });

    test('name mode shows trailing space for commands with completer', () {
      ac.update('/mod', 4);
      expect(ac.active, isTrue);
      // /model has a completer → selectedText includes trailing space.
      expect(ac.selectedText, '/model ');
      final result = ac.accept('/mod', 4);
      expect(result?.text, '/model ');
    });

    test('name mode → arg mode transition on space', () {
      ac.update('/mod', 4); // name mode, /model selected
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
      ac.update('/model ', 7); // space typed
      expect(ac.active, isTrue);
      expect(ac.matchCount, 3); // arg candidates
    });

    test('arg mode → name mode on backspace across space', () {
      ac.update('/model ', 7);
      expect(ac.matchCount, 3);
      ac.update('/model', 6); // backspace removed the space
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1); // back to /model name candidate
      expect(ac.selectedText, '/model ');
    });

    test('nested args: priorArgs populated correctly', () {
      // Use a completer that inspects prior args.
      registry.attachArgCompleter('clear', (prior, partial) {
        // Only offers candidates when prior is ['all'].
        if (prior.length == 1 && prior[0] == 'all') {
          return const [SlashArgCandidate(value: 'confirmed')];
        }
        return const [];
      });

      ac.update('/clear all ', 11);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 1);
      expect(ac.selectedText, '/clear all confirmed');
    });
  });

  group('SlashAutocomplete whitespace edge cases', () {
    late SlashAutocomplete ac;

    setUp(() {
      final registry = _makeRegistry();
      registry.attachArgCompleter(
        'model',
        (_, __) => const [SlashArgCandidate(value: 'sonnet')],
      );
      ac = SlashAutocomplete(registry);
    });

    test('double space dismisses', () {
      ac.update('/model  s', 9);
      expect(ac.active, isFalse);
    });

    test('tab char dismisses', () {
      ac.update('/model\ts', 8);
      expect(ac.active, isFalse);
    });

    test('slash + space with no command dismisses', () {
      ac.update('/ ', 2);
      expect(ac.active, isFalse);
    });
  });
}
