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
      expect(ac.matchCount, 5);
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
      for (var i = 0; i < 5; i++) {
        ac.moveDown();
      }
      expect(ac.selected, 0); // wrapped
    });

    test('moveUp wraps around', () {
      ac.update('/', 1);
      expect(ac.selected, 0);
      ac.moveUp(); // wraps to last
      expect(ac.selected, 4);
    });

    test('accept returns selected command', () {
      ac.update('/c', 2);
      expect(ac.active, isTrue);
      ac.moveDown(); // select compact
      final result = ac.accept();
      expect(result, '/compact');
      expect(ac.active, isFalse);
    });

    test('accept returns first match by default', () {
      ac.update('/c', 2);
      final result = ac.accept();
      expect(result, '/clear');
    });

    test('accept returns null when inactive', () {
      final result = ac.accept();
      expect(result, isNull);
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
      expect(lines, hasLength(5));
    });

    test('render returns empty when inactive', () {
      final lines = ac.render(80);
      expect(lines, isEmpty);
    });

    test('overlayHeight matches match count', () {
      ac.update('/', 1);
      expect(ac.overlayHeight, 5);
      ac.update('/he', 3);
      expect(ac.overlayHeight, 1);
      ac.dismiss();
      expect(ac.overlayHeight, 0);
    });
  });
}
