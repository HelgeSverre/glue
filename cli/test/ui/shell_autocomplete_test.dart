import 'package:test/test.dart';
import 'package:glue/src/shell/shell_completer.dart';
import 'package:glue/src/ui/shell_autocomplete.dart';

/// A mock ShellCompleter that returns predetermined results.
class _MockCompleter extends ShellCompleter {
  List<ShellCandidate> nextResults = [];

  _MockCompleter() : super(shellType: ShellType.bash);

  @override
  Future<List<ShellCandidate>> complete(String buffer) async {
    return nextResults;
  }
}

void main() {
  group('ShellAutocomplete', () {
    late _MockCompleter completer;
    late ShellAutocomplete ac;

    setUp(() {
      completer = _MockCompleter();
      ac = ShellAutocomplete(completer);
    });

    test('starts inactive', () {
      expect(ac.active, isFalse);
      expect(ac.overlayHeight, 0);
      expect(ac.matchCount, 0);
      expect(ac.selected, 0);
    });

    test('requestCompletions activates with results', () async {
      completer.nextResults = [
        ShellCandidate('echo'),
        ShellCandidate('exit'),
      ];
      await ac.requestCompletions('e', 1);
      expect(ac.active, isTrue);
      expect(ac.matchCount, 2);
      expect(ac.selected, 0);
    });

    test('empty buffer dismisses', () async {
      completer.nextResults = [ShellCandidate('echo')];
      await ac.requestCompletions('e', 1);
      expect(ac.active, isTrue);

      await ac.requestCompletions('', 0);
      expect(ac.active, isFalse);
    });

    test('no matches dismisses', () async {
      completer.nextResults = [];
      await ac.requestCompletions('xyznonexistent', 14);
      expect(ac.active, isFalse);
    });

    test('moveDown wraps around', () async {
      completer.nextResults = [
        ShellCandidate('a'),
        ShellCandidate('b'),
        ShellCandidate('c'),
      ];
      await ac.requestCompletions('x', 1);
      expect(ac.selected, 0);

      ac.moveDown(); // 1
      ac.moveDown(); // 2
      ac.moveDown(); // wraps to 0
      expect(ac.selected, 0);
    });

    test('moveUp wraps around', () async {
      completer.nextResults = [
        ShellCandidate('a'),
        ShellCandidate('b'),
        ShellCandidate('c'),
      ];
      await ac.requestCompletions('x', 1);
      expect(ac.selected, 0);

      ac.moveUp(); // wraps to 2
      expect(ac.selected, 2);
    });

    test('moveUp and moveDown do nothing when inactive', () {
      ac.moveUp();
      ac.moveDown();
      expect(ac.selected, 0);
    });

    test('accept splices correctly for single-word input', () async {
      completer.nextResults = [ShellCandidate('echo')];
      await ac.requestCompletions('ech', 3);

      final result = ac.accept('', 0);
      expect(result, isNotNull);
      expect(result!.text, 'echo ');
      expect(result.cursor, 5); // "echo " length
      expect(ac.active, isFalse);
    });

    test('accept splices correctly for multi-word input', () async {
      completer.nextResults = [ShellCandidate('checkout')];
      // "git ch" → tokenStart=4, token="ch"
      await ac.requestCompletions('git ch', 6);

      final result = ac.accept('', 0);
      expect(result, isNotNull);
      expect(result!.text, 'git checkout ');
      expect(result.cursor, 13); // "git checkout " length
    });

    test('accept adds trailing space for non-directory', () async {
      completer.nextResults = [
        ShellCandidate('file.txt', isDirectory: false),
      ];
      await ac.requestCompletions('cat f', 5);

      final result = ac.accept('', 0);
      expect(result, isNotNull);
      expect(result!.text, endsWith('file.txt '));
    });

    test('accept adds trailing slash for directory', () async {
      completer.nextResults = [
        ShellCandidate('src', isDirectory: true),
      ];
      await ac.requestCompletions('ls s', 4);

      final result = ac.accept('', 0);
      expect(result, isNotNull);
      expect(result!.text, endsWith('src/'));
      // No trailing space — user continues typing path.
      expect(result.text.endsWith('src/ '), isFalse);
    });

    test('accept with selection via moveDown', () async {
      completer.nextResults = [
        ShellCandidate('alpha'),
        ShellCandidate('bravo'),
      ];
      await ac.requestCompletions('x', 1);

      ac.moveDown(); // select bravo
      final result = ac.accept('', 0);
      expect(result, isNotNull);
      expect(result!.text, 'bravo ');
    });

    test('accept returns null when inactive', () {
      final result = ac.accept('', 0);
      expect(result, isNull);
    });

    test('dismiss resets all state', () async {
      completer.nextResults = [
        ShellCandidate('a'),
        ShellCandidate('b'),
      ];
      await ac.requestCompletions('x', 1);
      ac.moveDown();

      ac.dismiss();
      expect(ac.active, isFalse);
      expect(ac.selected, 0);
      expect(ac.matchCount, 0);
      expect(ac.overlayHeight, 0);
    });

    test('stale async results are discarded', () async {
      // Simulate two rapid requests — only the second should take effect.
      completer.nextResults = [ShellCandidate('first')];
      final firstFuture = ac.requestCompletions('a', 1);

      completer.nextResults = [ShellCandidate('second')];
      final secondFuture = ac.requestCompletions('b', 1);

      await firstFuture;
      await secondFuture;

      // The first request was stale — only second should be active.
      expect(ac.active, isTrue);
      final result = ac.accept('', 0);
      expect(result!.text, 'second ');
    });

    test('render returns correct number of lines', () async {
      completer.nextResults = [
        ShellCandidate('a'),
        ShellCandidate('b'),
        ShellCandidate('c'),
      ];
      await ac.requestCompletions('x', 1);
      final lines = ac.render(80);
      expect(lines, hasLength(3));
    });

    test('render returns empty when inactive', () {
      final lines = ac.render(80);
      expect(lines, isEmpty);
    });

    test('overlayHeight capped at maxVisible', () async {
      completer.nextResults =
          List.generate(20, (i) => ShellCandidate('item_$i'));
      await ac.requestCompletions('x', 1);
      expect(ac.matchCount, 20);
      expect(ac.overlayHeight, 8); // maxVisibleDropdownItems
    });

    test('overlayHeight matches match count when under max', () async {
      completer.nextResults = [
        ShellCandidate('a'),
        ShellCandidate('b'),
      ];
      await ac.requestCompletions('x', 1);
      expect(ac.overlayHeight, 2);
    });

    test('render lines include description when present', () async {
      completer.nextResults = [
        ShellCandidate('echo', description: 'Display a line of text'),
      ];
      await ac.requestCompletions('ech', 3);
      final lines = ac.render(80);
      expect(lines, hasLength(1));
      expect(lines[0], contains('echo'));
      expect(lines[0], contains('Display a line of text'));
    });

    test('render shows directory icon for directories', () async {
      completer.nextResults = [
        ShellCandidate('src', isDirectory: true),
      ];
      await ac.requestCompletions('s', 1);
      final lines = ac.render(80);
      expect(lines[0], contains('📁'));
    });

    test('tokenStart is set correctly', () async {
      completer.nextResults = [ShellCandidate('checkout')];
      await ac.requestCompletions('git ch', 6);
      expect(ac.tokenStart, 4); // "git " has length 4
    });

    test('accept preserves text after cursor', () async {
      completer.nextResults = [ShellCandidate('checkout')];
      // Cursor in the middle: "git ch|out" — cursor at 6, full buffer is "git chout"
      await ac.requestCompletions('git chout', 6);

      final result = ac.accept('', 0);
      expect(result, isNotNull);
      // before="git ", completion="checkout ", after="out"
      expect(result!.text, 'git checkout out');
      expect(result.cursor, 13); // cursor after "git checkout "
    });
  });
}
