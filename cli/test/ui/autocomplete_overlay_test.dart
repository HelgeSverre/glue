import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/ui/at_file_hint.dart';
import 'package:glue/src/ui/autocomplete_overlay.dart';
import 'package:glue/src/ui/shell_autocomplete.dart';
import 'package:glue/src/ui/slash_autocomplete.dart';

class _FakeShellCompleter extends ShellCompleter {
  List<ShellCandidate> next = [];

  _FakeShellCompleter() : super(shellType: ShellType.bash);

  @override
  Future<List<ShellCandidate>> complete(String line) async => next;

  @override
  int tokenStart(String line) {
    final i = line.lastIndexOf(' ');
    return i < 0 ? 0 : i + 1;
  }
}

void main() {
  group('AutocompleteOverlay contract', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('autocomplete_overlay_test_');
      File(p.join(tmp.path, 'hello.txt')).createSync();
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('SlashAutocomplete is an AutocompleteOverlay', () {
      final registry = SlashCommandRegistry();
      registry.register(SlashCommand(
        name: 'help',
        description: 'show help',
        execute: (_) => '',
      ));
      final AutocompleteOverlay o = SlashAutocomplete(registry);
      expect(o.active, isFalse);
      (o as SlashAutocomplete).update('/h', 2);
      expect(o.active, isTrue);
      expect(o.matchCount, 1);

      final result = o.accept('/h', 2);
      expect(result, isNotNull);
      expect(result!.text, '/help');
      expect(result.cursor, '/help'.length);
      expect(o.active, isFalse);
    });

    test('ShellAutocomplete is an AutocompleteOverlay', () async {
      final completer = _FakeShellCompleter()..next = [ShellCandidate('echo')];
      final AutocompleteOverlay o = ShellAutocomplete(completer);
      expect(o.active, isFalse);
      await (o as ShellAutocomplete).requestCompletions('ech', 3);
      expect(o.active, isTrue);
      expect(o.matchCount, 1);

      final result = o.accept('ech', 3);
      expect(result, isNotNull);
      expect(result!.text, 'echo ');
      expect(result.cursor, 'echo '.length);
      expect(o.active, isFalse);
    });

    test('AtFileHint is an AutocompleteOverlay', () {
      final AutocompleteOverlay o = AtFileHint(cwd: tmp.path);
      expect(o.active, isFalse);
      (o as AtFileHint).update('@hello', 6);
      expect(o.active, isTrue);

      final result = o.accept('@hello', 6);
      expect(result, isNotNull);
      expect(result!.text, '@hello.txt');
      expect(result.cursor, '@hello.txt'.length);
      expect(o.active, isFalse);
    });

    test('moveUp/moveDown/dismiss work through the interface', () {
      final registry = SlashCommandRegistry();
      registry.register(
          SlashCommand(name: 'a', description: '', execute: (_) => ''));
      registry.register(
          SlashCommand(name: 'ab', description: '', execute: (_) => ''));
      final AutocompleteOverlay o = SlashAutocomplete(registry)
        ..update('/a', 2);
      expect(o.active, isTrue);
      expect(o.selected, 0);
      o.moveDown();
      expect(o.selected, 1);
      o.moveUp();
      expect(o.selected, 0);
      o.moveUp();
      expect(o.selected, 1); // wraps
      o.dismiss();
      expect(o.active, isFalse);
    });

    test('accept returns null when overlay is inactive', () {
      final AutocompleteOverlay o = SlashAutocomplete(SlashCommandRegistry());
      expect(o.active, isFalse);
      expect(o.accept('anything', 0), isNull);
    });
  });
}
