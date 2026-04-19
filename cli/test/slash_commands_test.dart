import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  late SlashCommandRegistry registry;

  setUp(() {
    registry = SlashCommandRegistry();
  });

  group('SlashCommandRegistry', () {
    test('registered commands appear in commands list', () {
      final cmd = SlashCommand(
        name: 'help',
        description: 'Show help',
        execute: (_) => 'help output',
      );
      registry.register(cmd);

      expect(registry.commands, hasLength(1));
      expect(registry.commands.first.name, 'help');
    });

    test('execute by name', () {
      registry.register(SlashCommand(
        name: 'help',
        description: 'Show help',
        execute: (_) => 'Help text',
      ));

      expect(registry.execute('/help'), 'Help text');
    });

    test('execute with args', () {
      registry.register(SlashCommand(
        name: 'model',
        description: 'Set model',
        execute: (args) => 'model=${args.join(",")}',
      ));

      expect(registry.execute('/model gpt-4'), 'model=gpt-4');
    });

    test('aliases respond to aliased names', () {
      registry.register(SlashCommand(
        name: 'exit',
        description: 'Exit',
        aliases: ['quit', 'q'],
        execute: (_) => 'bye',
      ));

      expect(registry.execute('/quit'), 'bye');
      expect(registry.execute('/q'), 'bye');
      expect(registry.execute('/exit'), 'bye');
    });

    test('hidden aliases respond to aliased names', () {
      registry.register(SlashCommand(
        name: 'exit',
        description: 'Exit',
        hiddenAliases: ['q'],
        execute: (_) => 'bye',
      ));

      expect(registry.execute('/q'), 'bye');
      expect(registry.execute('/exit'), 'bye');
    });

    test('unknown command returns error message', () {
      final result = registry.execute('/unknown');

      expect(result, isNotNull);
      expect(result, contains('Unknown command'));
    });

    test('case insensitivity', () {
      registry.register(SlashCommand(
        name: 'help',
        description: 'Show help',
        execute: (_) => 'Help text',
      ));

      expect(registry.execute('/HELP'), 'Help text');
    });

    test('no slash prefix returns null', () {
      registry.register(SlashCommand(
        name: 'help',
        description: 'Show help',
        execute: (_) => 'Help text',
      ));

      expect(registry.execute('help'), isNull);
    });

    test('empty input returns null', () {
      expect(registry.execute(''), isNull);
    });

    test('multiple whitespace parsed correctly', () {
      registry.register(SlashCommand(
        name: 'cmd',
        description: 'A command',
        execute: (args) => args.join('|'),
      ));

      expect(registry.execute('/cmd  arg1   arg2'), 'arg1|arg2');
    });

    test('multiple commands execute independently', () {
      registry.register(SlashCommand(
        name: 'alpha',
        description: 'Alpha',
        execute: (_) => 'a',
      ));
      registry.register(SlashCommand(
        name: 'beta',
        description: 'Beta',
        execute: (_) => 'b',
      ));
      registry.register(SlashCommand(
        name: 'gamma',
        description: 'Gamma',
        execute: (_) => 'g',
      ));

      expect(registry.execute('/alpha'), 'a');
      expect(registry.execute('/beta'), 'b');
      expect(registry.execute('/gamma'), 'g');
      expect(registry.commands, hasLength(3));
    });

    test('findByName returns registered command by primary name', () {
      final cmd = SlashCommand(
        name: 'open',
        description: 'Open something',
        execute: (_) => '',
      );
      registry.register(cmd);
      expect(registry.findByName('open'), same(cmd));
      expect(registry.findByName('OPEN'), same(cmd));
    });

    test('findByName resolves through aliases and hidden aliases', () {
      final cmd = SlashCommand(
        name: 'exit',
        description: 'Exit',
        aliases: ['quit'],
        hiddenAliases: ['q'],
        execute: (_) => '',
      );
      registry.register(cmd);
      expect(registry.findByName('exit'), same(cmd));
      expect(registry.findByName('quit'), same(cmd));
      expect(registry.findByName('q'), same(cmd));
    });

    test('findByName returns null for unknown name', () {
      expect(registry.findByName('nope'), isNull);
    });
  });

  group('SlashArgCandidate defaults', () {
    test('continues defaults to false and description to empty', () {
      const candidate = SlashArgCandidate(value: 'home');
      expect(candidate.continues, isFalse);
      expect(candidate.description, '');
      expect(candidate.value, 'home');
    });
  });

  group('attachArgCompleter', () {
    test('sets the completer on the target command', () {
      final cmd = SlashCommand(
        name: 'open',
        description: 'Open',
        execute: (_) => '',
      );
      registry.register(cmd);

      expect(cmd.completeArg, isNull);
      registry.attachArgCompleter(
        'open',
        (_, __) => const [SlashArgCandidate(value: 'home')],
      );
      expect(cmd.completeArg, isNotNull);

      final out = cmd.completeArg!(const [], '');
      expect(out, hasLength(1));
      expect(out.first.value, 'home');
    });

    test('resolves through aliases and hidden aliases', () {
      final cmd = SlashCommand(
        name: 'exit',
        description: 'Exit',
        aliases: ['quit'],
        hiddenAliases: ['q'],
        execute: (_) => '',
      );
      registry.register(cmd);

      registry.attachArgCompleter(
        'q',
        (_, __) => const [SlashArgCandidate(value: 'now')],
      );
      expect(cmd.completeArg, isNotNull);
    });

    test('throws StateError on unknown command name', () {
      expect(
        () => registry.attachArgCompleter('nope', (_, __) => const []),
        throwsStateError,
      );
    });

    test('command without completer still executes normally', () {
      registry.register(SlashCommand(
        name: 'simple',
        description: 'Simple',
        execute: (_) => 'ran',
      ));
      expect(registry.execute('/simple'), 'ran');
      expect(registry.findByName('simple')!.completeArg, isNull);
    });
  });
}
